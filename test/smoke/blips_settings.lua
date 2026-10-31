local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')
local mocks = require('mocks')

local net = mocks.install()

dofile(repoRoot .. 'config.lua')
dofile(repoRoot .. 'build/initiate.lua')

local categories = {
    { id = 13, name = 'Bank', label = 'Banks', visible = true, count = 2 },
    { id = 14, name = 'Bar', label = 'Bars', visible = false, count = 1 },
}
local registered = {
    {
        handle = 101,
        category = 13,
        categoryKey = 'Bank',
        name = 'Pacific Standard',
        label = 'Bank: Pacific Standard',
        sprite = 108,
        color = 29,
        display = 4,
        resource = 'qb-banking',
        visible = true,
    },
    {
        handle = 102,
        category = 13,
        categoryKey = 'Bank',
        name = 'Legion Fleeca',
        label = 'Bank: Legion Fleeca',
        sprite = 999,
        color = 123,
        display = 4,
        resource = 'qb-banking',
        visible = true,
    },
    {
        handle = 103,
        category = 14,
        name = 'bar',
        label = 'Bahama Mamas',
        sprite = 93,
        color = 1,
        display = 4,
        resource = 'qb-nightclubs',
        visible = false,
    },
}
local visibleByCategory = { [13] = true, [14] = false }
local hideCalls, showCalls = {}, {}

Kora.blips = {
    getCategories = function() return categories end,
    getCategory = function(target)
        for index = 1, #categories do
            if categories[index].id == target or categories[index].name == target then return categories[index] end
        end
    end,
    getRegistered = function() return registered end,
    isCategoryVisible = function(target) return visibleByCategory[target] end,
    hideCategory = function(target)
        hideCalls[#hideCalls + 1] = target
        visibleByCategory[target] = false
        for index = 1, #categories do
            if categories[index].id == target then categories[index].visible = false end
        end
        return true
    end,
    showCategory = function(target)
        showCalls[#showCalls + 1] = target
        visibleByCategory[target] = true
        for index = 1, #categories do
            if categories[index].id == target then categories[index].visible = true end
        end
        return true
    end,
}

local registeredApp, lastUpdate
local appOpen = false
local openCalls, closeCalls = 0, 0
Kora.nui = {
    registerApp = function(definition)
        registeredApp = definition
        return definition.id
    end,
    updateApp = function(_, update)
        lastUpdate = update
        return true
    end,
    openApp = function()
        openCalls = openCalls + 1
        appOpen = true
        return promise.new()
    end,
    closeApp = function()
        closeCalls = closeCalls + 1
        appOpen = false
        return true
    end,
    isAppOpen = function() return appOpen end,
}

local admin = true
Kora.callback = {
    trigger = function()
        local result = promise.new()
        result:resolve(admin)
        return result
    end,
}

dofile(repoRoot .. 'modules/blips/settings.lua')

local function itemById(navigation, id)
    local items = navigation[1].content.blocks[1].items
    for index = 1, #items do
        if items[index].id == id then return items[index] end
    end
end

local function metadataValue(item, label)
    for index = 1, #(item.metadata or {}) do
        if item.metadata[index].label == label then return item.metadata[index].value end
    end
end

harness.test('registers a compact AppShell and the /blips command', function()
    harness.assertEqual(registeredApp.id, 'kora_lib:blips', 'settings app should use a namespaced id')
    harness.assertEqual(registeredApp.layout, 'compact', 'settings should use the focused compact layout')
    harness.assertTrue(type(net.commands.blips) == 'function', '/blips should be a client command')
end)

harness.test('shows categories with registered blips as children and official artwork', function()
    net.commands.blips()
    harness.assertEqual(openCalls, 1, '/blips should open the settings app')

    local bank = itemById(lastUpdate.navigation, 'category:13')
    harness.assertEqual(bank.badge, 'Visible', 'category state should be visible at a glance')
    harness.assertEqual(bank.actions[1].label, 'Hide category', 'toggle should describe its immediate result')
    harness.assertEqual(#bank.children, 2, 'registered blips should be nested beneath their category')

    local known = bank.children[2]
    if known.label ~= 'Pacific Standard' then known = bank.children[1] end
    harness.assertEqual(known.image,
        'https://docs-backend.fivem.net/blips/radar_financier_strand.png',
        'known sprites should use the official FiveM radar-name asset')
    harness.assertEqual(metadataValue(known, 'Blip colour'), 'Dark Blue · 29 · #4561AB',
        'color metadata should include its documented name, index, and hex')
    harness.assertEqual(metadataValue(known, 'Owner resource'), 'qb-banking',
        'admins should see the creating resource')

    local unknown = bank.children[1]
    if unknown.label ~= 'Legion Fleeca' then unknown = bank.children[2] end
    harness.assertEqual(unknown.image, nil, 'unknown sprites should not request a guessed image URL')
    harness.assertEqual(unknown.icon, 'MapPin', 'unknown sprites should retain a generic visual')
    harness.assertEqual(metadataValue(unknown, 'FiveM docs'),
        'https://docs.fivem.net/docs/game-references/blips/',
        'unknown sprites should retain the official reference link')
end)

harness.test('toggles a category immediately and refreshes the open app', function()
    local result = registeredApp.onAction('kora_lib:blips:toggleCategory', { itemId = 'category:13' })
    harness.assertEqual(hideCalls[#hideCalls], 13, 'visible category should be hidden')
    harness.assertEqual(itemById(lastUpdate.navigation, 'category:13').badge, 'Hidden',
        'open AppShell should refresh immediately after the toggle')
    harness.assertEqual(result.notice.tone, 'success', 'successful toggle should give in-shell feedback')

    result = registeredApp.onAction('kora_lib:blips:toggleCategory', { itemId = 'category:14' })
    harness.assertEqual(showCalls[#showCalls], 14, 'hidden category should be shown')
    harness.assertEqual(result.notice.message, 'Bars blips shown.', 'feedback should name the affected category')
end)

harness.test('fails closed and hides resource ownership from non-admins', function()
    appOpen = false
    admin = false
    net.commands.blips()
    local bank = itemById(lastUpdate.navigation, 'category:13')
    harness.assertEqual(metadataValue(bank.children[1], 'Owner resource'), nil,
        'non-admin viewers must not receive owner metadata')
end)

harness.test('running /blips while open closes the current app', function()
    net.commands.blips()
    harness.assertEqual(closeCalls, 1, 'second command invocation should close the app')
end)

harness.report('blips settings smoke')
