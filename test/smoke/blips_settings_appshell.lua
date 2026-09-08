local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')
local mocks = require('mocks')

local net = mocks.install()
dofile(repoRoot .. 'config.lua')
dofile(repoRoot .. 'build/initiate.lua')
dofile(repoRoot .. 'local/resources/client.lua')

local sentMessages = {}
_G.RegisterNUICallback = function() end
_G.SendNUIMessage = function(payload) sentMessages[#sentMessages + 1] = payload end
_G.SetNuiFocus = function() end
_G.QBTheme = { apply = function() end }

dofile(repoRoot .. 'modules/nui/client.lua')

QB.blips = {
    getCategories = function()
        return { { id = 14, name = 'Bar', label = 'Bars', visible = true, count = 1 } }
    end,
    getCategory = function() return { id = 14, name = 'Bar', label = 'Bars', visible = true } end,
    getRegistered = function()
        return { {
            handle = 93,
            category = 14,
            categoryKey = 'Bar',
            name = 'Bahama Mamas',
            label = 'Bar: Bahama Mamas',
            sprite = 93,
            color = 1,
            display = 4,
            resource = 'qb-nightclubs',
            visible = true,
        } }
    end,
    isCategoryVisible = function() return true end,
    hideCategory = function() return true end,
    showCategory = function() return true end,
}
QB.callback.trigger = function()
    local result = promise.new()
    result:resolve(true)
    return result
end

harness.test('settings definition passes the production AppShell validator', function()
    dofile(repoRoot .. 'modules/blips/settings.lua')
    net.commands.blips()

    local openMessage
    for index = #sentMessages, 1, -1 do
        if sentMessages[index].action == 'openApp' then openMessage = sentMessages[index] break end
    end
    harness.assertTrue(openMessage ~= nil, 'validated settings app should open through the real NUI module')
    harness.assertEqual(openMessage.data.payload.app.id, 'qblib:blips', 'browser should receive the settings app')
end)

harness.report('blips settings AppShell smoke')
