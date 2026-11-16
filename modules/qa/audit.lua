local isServer = IsDuplicityVersion()
local resource = GetCurrentResourceName()
local realm = isServer and 'server' or 'client'
local command = 'kora_lib_audit_' .. realm
local running = false

local function equal(actual, expected)
    assert(actual == expected, ('expected %s, got %s'):format(tostring(expected), tostring(actual)))
end

local function fixtures()
    local util = Kora.util
    local a = { x = 3, y = 4, z = 0 }
    local origin = { x = 0, y = 0, z = 0 }
    return {
        ['util.deepClone'] = function()
            local source = { data = { 7 } }
            local copy = util.deepClone(source)
            equal(copy.data[1], 7)
            assert(copy ~= source and copy.data ~= source.data)
        end,
        ['util.fnv1a'] = function()
            equal(util.fnv1a('hello'), '4f9f2cab')
            local key = 'Modules.Util.util_fnv1a'
            local message = KoraLang(key)
            local ok, err = pcall(util.fnv1a, false)
            assert(message ~= key and not ok and tostring(err):find(message, 1, true))
            return key .. ' => ' .. message
        end,
        ['util.trim'] = function() equal(util.trim('  Kora  '), 'Kora') end,
        ['util.cleanText'] = function() equal(util.cleanText('  Kora  '), 'Kora') end,
        ['util.truncateUtf8'] = function() equal(util.truncateUtf8('Kora', 2), 'Ko') end,
        ['util.isFiniteNumber'] = function()
            equal(util.isFiniteNumber(10), true)
            equal(util.isFiniteNumber(math.huge), false)
        end,
        ['util.isInteger'] = function()
            equal(util.isInteger(10), true)
            equal(util.isInteger(10.5), false)
        end,
        ['util.isCallable'] = function()
            equal(util.isCallable(equal), true)
            equal(util.isCallable(false), false)
        end,
        ['util.decodeJson'] = function() equal(util.decodeJson('{"value":7}').value, 7) end,
        ['util.clamp'] = function() equal(util.clamp(11, 0, 10), 10) end,
        ['util.round'] = function() equal(util.round(1.236, 2), 1.24) end,
        ['util.randomFloat'] = function()
            local value = util.randomFloat(2, 3)
            assert(value >= 2 and value <= 3)
        end,
        ['util.weightedChoice'] = function() equal(util.weightedChoice({ { 'only', 1 } }), 'only') end,
        ['util.tableContains'] = function()
            equal(util.tableContains({ 1, 2 }, 2), true)
            equal(util.tableContains({ 1, 2 }, 3), false)
        end,
        ['util.lerp'] = function() equal(util.lerp(0, 20, 0.25), 5) end,
        ['util.vecAdd'] = function() equal(util.vecAdd(a, a).x, 6) end,
        ['util.vecSub'] = function() equal(util.vecSub(a, a).y, 0) end,
        ['util.vecScale'] = function() equal(util.vecScale(a, 2).y, 8) end,
        ['util.vecLength'] = function() equal(util.vecLength(a), 5) end,
        ['util.vecDistance'] = function() equal(util.vecDistance(origin, a), 5) end,
        ['util.vecDistance2d'] = function() equal(util.vecDistance2d(origin, a), 5) end,
        ['util.nearest'] = function()
            local nearest, distance = util.nearest({ a, origin }, origin, { coordsOf = function(point) return point end })
            equal(nearest, origin)
            equal(distance, 0)
        end,
        ['util.vecNormalize'] = function() assert(math.abs(util.vecNormalize(a).x - 0.6) < 0.000001) end,
        ['util.headingToDirection'] = function() equal(util.headingToDirection(0).y, 1) end,
        ['util.directionToHeading'] = function() equal(util.directionToHeading({ x = 0, y = 1 }), 0) end,
        ['util.bearing'] = function() equal(util.bearing(origin, { x = 0, y = 1 }), 0) end,
        ['util.rateLimiter'] = function()
            local limiter = util.rateLimiter(1, 100)
            equal(limiter:consume('audit', 0), true)
            equal(limiter:consume('audit', 1), false)
            equal(limiter:consume('audit', 100), true)
        end,
        ['random.pick'] = function() equal(Kora.random.pick({ 'only' }), 'only') end,
        ['rewards.generate'] = function()
            local rewards = Kora.rewards.generate({ { name = 'audit', amount = 2, chance = 1 } })
            equal(#rewards, 1)
            equal(rewards[1].amount, 2)
        end,
        ['loops.controlled'] = function()
            equal(Kora.loops.controlled(function() return 'ready' end, 1), 'ready')
        end,
        ['vehicle.normalizePlate'] = function()
            equal(Kora.vehicle.normalizePlate('  ab 12 '), 'AB 12')
            local value, reason = Kora.vehicle.normalizePlate(false)
            equal(value, nil)
            equal(reason, 'invalid_type')
        end,
        ['locale.getLanguage'] = function()
            local language = Kora.locale.getLanguage()
            assert(type(language) == 'string' and language:match('^[%w][%w_-]*$'))
        end,
        ['locale.getLanguages'] = function()
            equal(util.tableContains(Kora.locale.getLanguages(), 'en'), true)
        end,
        ['locale.translate'] = function()
            local key = 'app.page'
            local text = Kora.locale.translate(resource, key, { current = 1, total = 2 })
            assert(type(text) == 'string' and text ~= key and not text:find('%{', 1, true))
            return key .. ' => ' .. text
        end,
    }
end

local function functionsInRealm()
    local names = {}
    for name, entry in pairs(Kora) do
        if type(entry) == 'function' then
            names[#names + 1] = name
        elseif type(entry) == 'table' then
            for member, value in pairs(entry) do
                if type(value) == 'function' then names[#names + 1] = name .. '.' .. member end
            end
        end
    end
    table.sort(names)
    return names
end

local function runAudit(summary)
    local checks = fixtures()
    local names = functionsInRealm()
    local report = { pass = 0, fail = 0, untested = 0, localePass = 0, localeFail = 0 }
    local written = 0

    local function emit(status, subject, detail)
        if summary and status ~= 'FAIL' then return end
        print(('[kora_lib audit/%s] [%s] %s%s'):format(realm, status, subject, detail and (' | ' .. tostring(detail)) or ''))
        written = written + 1
        if written % 40 == 0 then Wait(0) end
    end

    local function checkFunction(name, check)
        local ok, detail = pcall(check)
        local status = ok and 'pass' or 'fail'
        report[status] = report[status] + 1
        emit(status:upper(), name, detail)
    end

    print(('[kora_lib audit/%s] Kora functions in realm: %d | configured locale: %s | selected locale: %s')
        :format(realm, #names, GetConvar('kora_locale', 'en'), Kora.locale.getLanguage()))
    for _, name in ipairs(names) do
        local check = checks[name]
        if check then
            checkFunction(name, check)
            checks[name] = nil
        else
            report.untested = report.untested + 1
            emit('UNTESTED', name, 'no runtime fixture')
        end
    end
    for name in pairs(checks) do
        checkFunction(name, function() error('expected function is missing from the live registry', 0) end)
    end

    local source = LoadResourceFile(resource, 'locales/en.lua')
    local loader, loadError
    if source then loader, loadError = load(source, '@locales/en.lua', 't', {}) end
    local loaded, catalog
    if loader then loaded, catalog = pcall(loader) end
    if not loaded or type(catalog) ~= 'table' then
        report.localeFail = report.localeFail + 1
        emit('FAIL', 'locales/en.lua', loadError or catalog or 'missing catalog')
    else
        local configuredEnglish = GetConvar('kora_locale', 'en') == 'en'
        local selectedEnglish = Kora.locale.getLanguage() == 'en'
        local function checkCatalog(values, prefix)
            local keys = {}
            for key in pairs(values) do keys[#keys + 1] = key end
            table.sort(keys)
            for _, part in ipairs(keys) do
                local key = prefix .. part
                local english = values[part]
                if type(english) == 'table' then
                    checkCatalog(english, key .. '.')
                else
                    local ok, text = pcall(function()
                        local internal = KoraLang(key)
                        local public = Kora.locale.translate(resource, key)
                        local function checkText(value, label)
                            assert(type(value) == 'string' and value:match('%S') and value ~= key,
                                label .. ' locale has missing or blank text')
                        end
                        checkText(english, 'English')
                        checkText(internal, 'configured')
                        checkText(public, 'selected')
                        if configuredEnglish then equal(internal, english) end
                        if selectedEnglish then equal(public, english) end
                        if internal ~= english or public ~= english then
                            return ('en=%q configured=%q selected=%q'):format(english, internal, public)
                        end
                        return ('en=%q'):format(english)
                    end)
                    local status = ok and 'localePass' or 'localeFail'
                    report[status] = report[status] + 1
                    emit(ok and 'PASS' or 'FAIL', 'locale ' .. key, text)
                end
            end
        end
        checkCatalog(catalog, '')
    end

    local outcome = (report.fail + report.localeFail > 0 and 'FAIL') or (report.untested > 0 and 'INCOMPLETE') or 'PASS'
    print(('[kora_lib audit/%s] [%s] functions: %d passed, %d failed, %d untested | locale keys: %d passed, %d failed')
        :format(realm, outcome, report.pass, report.fail, report.untested, report.localePass, report.localeFail))
end

RegisterCommand(command, function(_, args)
    if running then
        print(('[kora_lib audit/%s] An audit is already running.'):format(realm))
        return
    end

    running = true
    CreateThread(function()
        local ok, err = pcall(runAudit, args[1] == 'summary')
        running = false
        if not ok then
            print(('[kora_lib audit/%s] [FAIL] %s'):format(realm, tostring(err)))
        end
    end)
end, isServer)
