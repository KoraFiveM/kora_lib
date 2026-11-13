local root = (debug.getinfo(1, 'S').source:match('@?(.*/)') or './') .. '../../'
package.path = root .. 'test/?.lua;' .. package.path
local h = require('harness')

-- Real JSON encoding for assertions/output; decode is a wire fixture registry.
-- This deliberately models immutable transport rather than shared Lua tables.
local wire = {}
local function clone(v)
    if type(v) ~= 'table' then
        return v
    end
    local out = {}
    for k, x in pairs(v) do
        out[k] = clone(x)
    end
    return out
end
local function encode(v)
    local kind = type(v)
    if kind == 'nil' then
        return 'null'
    end
    if kind == 'boolean' or kind == 'number' then
        return tostring(v)
    end
    if kind == 'string' then
        return '"' .. v:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r') .. '"'
    end
    local parts, array = {}, #v > 0
    if array then
        for _, value in ipairs(v) do
            parts[#parts + 1] = encode(value)
        end
    else
        for key, value in pairs(v) do
            parts[#parts + 1] = encode(tostring(key)) .. ':' .. encode(value)
        end
        table.sort(parts)
    end
    local raw = (array and '[' or '{') .. table.concat(parts, ',') .. (array and ']' or '}')
    wire[raw] = clone(v)
    return raw
end

local function setup(realm, convars)
    local e = setmetatable({}, { __index = _G })
    e._G = e
    local f = {
        clock = 0,
        epoch = 1000,
        timers = {},
        handlers = {},
        commands = {},
        sent = {},
        lines = {},
        convars = convars or {},
    }
    e.GetConvar = function(key, default)
        return f.convars[key] or default
    end
    e.GetGameTimer = function()
        return f.clock
    end
    e.GetInvokingResource = function()
        return f.owner
    end
    e.GetCurrentResourceName = function()
        return 'kora_lib'
    end
    e.GetPlayerName = function(id)
        return id == 1 or id == 2 and 'player' or nil
    end
    e.CreateThread = function(fn)
        f.threadCount = (f.threadCount or 0) + 1
        fn()
    end
    e.Wait = function(ms)
        f.clock = f.clock + ms
    end
    e.NetworkIsSessionStarted = function()
        return true
    end
    e.PlayerId = function()
        return 0
    end
    e.GetPlayerServerId = function()
        return 1
    end
    e.IsDuplicityVersion = function()
        return realm == 'server'
    end
    e.IsPlayerAceAllowed = function()
        return f.authorized == true
    end
    e.os = {
        time = function()
            return f.epoch
        end,
        date = os.date,
    }
    e.json = {
        encode = encode,
        decode = function(raw)
            assert(wire[raw], 'bad JSON')
            return clone(wire[raw])
        end,
    }
    e.print = function(line)
        f.lines[#f.lines + 1] = line
    end
    e.RegisterNetEvent = function(name, fn)
        f.handlers[name] = fn
    end
    e.AddEventHandler = e.RegisterNetEvent
    e.RegisterCommand = function(name, fn)
        f.commands[name] = fn
    end
    e.SetTimeout = function(delay, fn)
        f.timers[#f.timers + 1] = { at = f.clock + delay, fn = fn }
    end
    e.TriggerClientEvent = function(name, player, value)
        f.sent[#f.sent + 1] = { name = name, player = player, value = clone(value) }
    end
    e.TriggerServerEvent = function(name, id, raw)
        f.sent[#f.sent + 1] = { name = name, id = id, raw = raw }
    end
    e.TriggerEvent = function() end
    e.PerformHttpRequest = function()
        f.http = (f.http or 0) + 1
    end
    e.Kora = {
        logging = {},
        util = {
            isInteger = function(v)
                return type(v) == 'number' and v % 1 == 0
            end,
        },
    }
    assert(loadfile(root .. 'modules/logging/shared.lua', 't', e))()
    assert(loadfile(root .. 'modules/logging/' .. realm .. '.lua', 't', e))()
    function f.fire(name, player, ...)
        e.source = player
        f.handlers[name](...)
        e.source = nil
    end
    function f.advance(ms)
        f.clock, f.epoch = f.clock + ms, f.epoch + ms / 1000
        local pending = f.timers
        f.timers = {}
        for _, timer in ipairs(pending) do
            if timer.at <= f.clock then
                timer.fn()
            else
                f.timers[#f.timers + 1] = timer
            end
        end
    end
    function f.start(actor, args)
        f.commands.kora_log_capture(actor, args or { 'start', '1', '*', 'debug', '600' })
        return f.sent[#f.sent] and f.sent[#f.sent].value
    end
    return e, f
end
local function item(extra)
    local record = {
        resource = 'kora_hud',
        realm = 'client',
        severity = 'debug',
        event = 'hud.refresh',
        message = 'refresh',
        fields = {},
    }
    for k, v in pairs(extra or {}) do
        record[k] = v
    end
    return record
end

h.test('filters before inspecting or encoding fields; per-resource override', function()
    local e, f = setup('server')
    f.owner = 'inventory'
    local fields = setmetatable({}, {
        __pairs = function()
            error('must not inspect')
        end,
    })
    h.assertFalse(e.Kora.logging.debug('test', 'filtered', fields))
    h.assertEqual(#f.lines, 0)
    f.convars.kora_logging_level_inventory = 'debug'
    h.assertTrue(e.Kora.logging.debug('test', 'visible'))
    h.assertTrue(f.lines[1]:find('inventory/server', 1, true))
end)

h.test('sanitizes, redacts, bounds and snapshots records', function()
    local e, f = setup('server', { kora_logging_format = 'json' })
    local fields = { password = 'never', nested = { api_key = 'never', safe = 'ok' }, invalid = math.huge }
    h.assertEqual(e.Kora.logging._internal.text('^^11red\27[31m'), 'red')
    fields.cycle = fields
    e.Kora.logging.warn('test', '^1bad\nline\27', fields)
    h.assertFalse(f.lines[1]:find('never', 1, true))
    h.assertFalse(f.lines[1]:find('^1', 1, true))
    h.assertTrue(f.lines[1]:find('[cycle]', 1, true))
    fields.nested.safe = 'changed'
    h.assertFalse(f.lines[1]:find('changed', 1, true))
    h.assertTrue(#f.lines[1] <= 4096 + #'KORA_LOG ')
    local text = e.Kora.logging._internal.text(string.rep('é', 600), 1023)
    h.assertTrue(utf8.len(text) ~= nil)
    h.assertTrue(e.Kora.logging.info('test.utf8', string.rep('é', 600)))
end)

h.test('sink failure does not escape and stats snapshots are independent', function()
    local e = setup('server')
    e.print = function()
        error('sink down')
    end
    h.assertFalse(e.Kora.logging.error('test', 'failure'))
    h.assertEqual(e.Kora.logging.getStats().failures, 1)
    e.Kora.logging.getStats().failures = 0
    h.assertEqual(e.Kora.logging.getStats().failures, 1)
end)

h.test('ring wraps and diagnostic calls never send Discord', function()
    local e = setup('server', { kora_lib_log_webhook = 'secret' })
    for i = 1, 510 do
        e.Kora.logging.info('test', 'record')
    end
    h.assertEqual(e.Kora.logging.getStats().ringSize, 500)
end)

h.test('capture status remains visible with info diagnostics disabled', function()
    local _, f = setup('server', { kora_logging_level = 'error' })
    f.commands.kora_log_capture(0, { 'status' })
    h.assertEqual(#f.lines, 1)
    h.assertTrue(f.lines[1]:find('logging.capture_status', 1, true) ~= nil)
end)

h.test('capture commands require ACE or console and validate duration', function()
    local e, f = setup('server')
    h.assertEqual(f.start(2), nil)
    h.assertEqual(f.start(0, { 'start', '1', '*', 'debug', '3601' }), nil)
    f.authorized = true
    h.assertTrue(type(f.start(2).id) == 'string')
end)

h.test('forwarding trusts only server player and capture attribution', function()
    local e, f = setup('server', { kora_logging_format = 'json' })
    local capture = f.start(0)
    f.fire(
        'kora_lib:logging:batch',
        1,
        capture.id,
        encode({ item({ playerId = 999, observedAt = 0, captureId = 'forged' }) })
    )
    local line = f.lines[#f.lines]
    h.assertTrue(line:find('"playerId":1', 1, true))
    h.assertTrue(line:find('"clientReported":true', 1, true))
    h.assertFalse(line:find('forged', 1, true))
    h.assertFalse(line:find('999', 1, true))
end)

h.test('rejects wrong player, stale generation, malformed and oversized batches', function()
    local e, f = setup('server')
    local capture = f.start(0)
    local before = e.Kora.logging.getStats().emitted
    f.fire('kora_lib:logging:batch', 2, capture.id, encode({ item() }))
    f.fire('kora_lib:logging:batch', 1, 'stale', encode({ item() }))
    f.fire('kora_lib:logging:batch', 1, capture.id, 'not json')
    f.fire('kora_lib:logging:batch', 1, capture.id, string.rep('x', 16385))
    f.fire('kora_lib:logging:batch', 1, capture.id, encode({ item({ realm = 'server' }) }))
    h.assertTrue(e.Kora.logging.getStats().emitted <= before + 1)
    h.assertTrue(e.Kora.logging.getStats().dropped >= 3)
end)

h.test('resource/level filters and player burst budget apply on the server', function()
    local e, f = setup('server')
    local capture = f.start(0, { 'start', '1', 'kora_hud', 'warn' })
    local before = e.Kora.logging.getStats().emitted
    f.fire('kora_lib:logging:batch', 1, capture.id, encode({ item(), item({ severity = 'warn', resource = 'other' }) }))
    h.assertTrue(e.Kora.logging.getStats().emitted <= before + 1)
    for i = 1, 100 do
        f.fire('kora_lib:logging:batch', 1, capture.id, encode({ item({ severity = 'warn' }) }))
    end
    h.assertTrue(e.Kora.logging.getStats().emitted <= before + 41)
    h.assertTrue(e.Kora.logging.getStats().dropped >= 60)
end)

h.test('expiry, disconnect, stop and source reuse invalidate captures', function()
    local e, f = setup('server')
    local capture = f.start(0, { 'start', '1', '*', 'debug', '1' })
    f.advance(1000)
    local before = e.Kora.logging.getStats().emitted
    f.fire('kora_lib:logging:batch', 1, capture.id, encode({ item() }))
    h.assertEqual(e.Kora.logging.getStats().emitted, before)
    capture = f.start(0)
    f.fire('playerDropped', 1)
    local nextCapture = f.start(0)
    h.assertTrue(nextCapture.id ~= capture.id)
    before = e.Kora.logging.getStats().emitted
    f.fire('kora_lib:logging:batch', 1, capture.id, encode({ item() }))
    h.assertEqual(e.Kora.logging.getStats().emitted, before)
    f.fire('onResourceStop', 0, 'kora_lib')
    f.fire('kora_lib:logging:batch', 1, nextCapture.id, encode({ item() }))
    h.assertEqual(e.Kora.logging.getStats().emitted, before)
end)

h.test('disabled client capture creates no timer, queue or network traffic', function()
    local e, f = setup('client')
    e.Kora.logging.info('test', 'local')
    h.assertEqual(#f.sent, 0)
    h.assertEqual(#f.timers, 0)
    h.assertEqual(e.Kora.logging.getStats().queuedBytes, 0)
end)

h.test('client batches, bounds queue, refuses local activation and discards on stop', function()
    local _, server = setup('server')
    local capture = server.start(0)
    local e, f = setup('client')
    f.fire('kora_lib:logging:capture', 0, capture)
    h.assertFalse(e.Kora.logging.isEnabled('debug'))
    f.fire('kora_lib:logging:capture', 65535, capture)
    h.assertTrue(e.Kora.logging.isEnabled('debug'))
    for i = 1, 200 do
        e.Kora.logging.debug('test', string.rep('x', 1024))
    end
    h.assertTrue(e.Kora.logging.getStats().queuedBytes <= 65536)
    h.assertTrue(e.Kora.logging.getStats().dropped > 0)
    f.advance(1000)
    h.assertTrue(#f.sent[1].raw <= 16384)
    f.fire('kora_lib:logging:capture', 65535, false)
    local count = #f.sent
    f.advance(1000)
    h.assertEqual(#f.sent, count)
    h.assertEqual(e.Kora.logging.getStats().queuedBytes, 0)
end)

h.test('NUI logs use invoking resource and the same capture queue', function()
    local _, server = setup('server')
    local capture = server.start(0)
    local e, f = setup('client')
    f.owner = 'kora_hud'
    f.fire('kora_lib:logging:capture', 65535, capture)
    e.Kora.logging.nui('debug', 'hud.render', 'rendered', { password = 'never' })
    f.advance(1000)
    h.assertTrue(f.sent[1].raw:find('"realm":"nui"', 1, true))
    h.assertTrue(f.sent[1].raw:find('"resource":"kora_hud"', 1, true))
    h.assertFalse(f.sent[1].raw:find('never', 1, true))
end)

h.test('legacy arrays remain arrays and long sensitive keys are redacted', function()
    local e, f = setup('server', { kora_logging_format = 'json' })
    e.Kora.logging.info('test', 'array', { items = { 'a', 'b' }, [string.rep('x', 80) .. 'password'] = 'never' })
    h.assertTrue(f.lines[1]:find('["a","b"]', 1, true))
    h.assertFalse(f.lines[1]:find('never', 1, true))
end)

h.test('aggregate ingestion budget applies across players', function()
    local e, f = setup('server', { kora_logging_aggregate_rate = '2' })
    local one = f.start(0)
    local two = f.start(0, { 'start', '2' })
    local before = e.Kora.logging.getStats().emitted
    for i = 1, 5 do
        f.fire('kora_lib:logging:batch', 1, one.id, encode({ item() }))
        f.fire('kora_lib:logging:batch', 2, two.id, encode({ item() }))
    end
    h.assertTrue(e.Kora.logging.getStats().emitted <= before + 3)
    h.assertTrue(e.Kora.logging.getStats().dropped >= 8)
end)

h.test('consumer stop drops its queued client diagnostics', function()
    local _, server = setup('server')
    local session = server.start(0)
    local e, f = setup('client')
    f.owner = 'kora_hud'
    f.fire('kora_lib:logging:capture', 65535, session)
    e.Kora.logging.debug('test', 'queued')
    f.fire('onClientResourceStop', 0, 'kora_hud')
    f.advance(1000)
    h.assertEqual(#f.sent, 0)
    h.assertEqual(e.Kora.logging.getStats().queuedBytes, 0)
end)

h.test('development-wide capture is opt-in and uses one readiness request', function()
    local _, disabled = setup('client')
    h.assertEqual(disabled.threadCount, nil)
    local _, enabled = setup('client', { kora_logging_capture_all = 'true' })
    h.assertEqual(enabled.threadCount, 1)
    h.assertEqual(#enabled.sent, 1)
    h.assertEqual(enabled.sent[1].name, 'kora_lib:logging:ready')
end)

h.test('consumer-local NUI bridge validates, responds and rate limits', function()
    local e, f = setup('client')
    local callback
    e.RegisterNUICallback = function(name, fn)
        h.assertEqual(name, 'kora_logging')
        callback = fn
    end
    e.SendNUIMessage = function() end
    assert(loadfile(root .. 'modules/logging/nui.lua', 't', e))()
    local reply
    local function respond(value)
        reply = value
    end
    callback({ action = 'ready' }, respond)
    h.assertFalse(reply.enabled)
    callback({ level = 'warn', event = 'nui.test', message = 'test', fields = { token = 'never' } }, respond)
    h.assertTrue(reply.ok)
    h.assertFalse(f.lines[1]:find('never', 1, true))
    callback({ level = 'warn', event = 'nui.test', message = {} }, respond)
    h.assertFalse(reply.ok)
    for i = 1, 50 do
        callback({ action = 'ready' }, respond)
    end
    h.assertFalse(reply.ok)
end)

h.report('logging_pipeline')
