-- Presentation-only benchmark. No FiveM client or browser is required.
-- Run from the repository root: lua test/bench_config_editor.lua
local definition
local entries = {}
for resourceIndex = 1, 60 do
    local fields, values = {}, {}
    for fieldIndex = 1, 500 do
        local key = ('setting%04d'):format(fieldIndex)
        fields[key] = { kind = 'integer', path = { key }, label = key,
            description = 'A benchmark setting.', live = true, advanced = fieldIndex % 2 == 0 }
        values[key] = fieldIndex
    end
    entries[resourceIndex] = { resource = ('resource%02d'):format(resourceIndex),
        schema = { kind = 'object', fields = fields }, configured = values, values = values,
        revision = 1, loaded = true }
end
QB = { config = {}, callback = { trigger = function(name)
    if name == 'qblib:configCatalog' then return entries end
    error('Unexpected callback: ' .. name)
end }, nui = {
    registerApp = function(value) definition = value end,
    openApp = function() end,
}, notify = { send = function() end } }
function RegisterNetEvent() end
dofile('modules/config/editor_client.lua')
local started = os.clock()
QB.config.open('resource01')
local initialMs = (os.clock() - started) * 1000
local result
started = os.clock()
for _ = 1, 100 do
    result = definition.onAction('config:advanced', { viewId = 'resource:resource01' })
end
local averageMs = (os.clock() - started) * 10
local populated, rows = 0, 0
for _, item in ipairs(result.update.navigation) do
    if item.id ~= 'resources' and item.content.blocks[1].type == 'table' then
        populated = populated + 1
        rows = rows + #item.content.blocks[1].rows
    end
end
assert(populated == 1 and rows == 250, 'only the selected resource may send populated settings rows')
print(('30,000 settings: initial %.2f ms; average toggle %.2f ms; %d populated resource page, %d rows'):format(
    initialMs, averageMs, populated, rows))
