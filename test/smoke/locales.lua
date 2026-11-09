local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')
local mocks = require('mocks')
mocks.install()

local convars = { qb_locale = 'en', qb_locales = 'en,de' }
local kvps = {}
local events = {}
local files = {
    ['example/locales/en.lua'] = "return { greeting = 'Hello %{name}', positional = 'Hello %s', fallback = 'English', literal = 'Value: %{a.b}' }",
    ['example/locales/de.lua'] = "return { greeting = 'Hallo %{name}', positional = 'Hallo %s' }",
    ['legacy/locales/en.lua'] = "local Translations = { greeting = 'Legacy English' }\nLang = Lang or Locale:new({ warnOnMissing = true })\nLang:addLocale('en', Translations)\nreturn Translations",
}

_G.GetConvar = function(name, fallback) return convars[name] or fallback end
_G.GetResourceKvpString = function(key) return kvps[key] end
_G.SetResourceKvp = function(key, value) kvps[key] = value end
_G.TriggerEvent = function(name, ...) events[#events + 1] = { name = name, ... } end
_G.LoadResourceFile = function(resource, path) return files[resource .. '/' .. path] end
_G.GetCurrentResourceName = function() return 'example' end

dofile(repoRoot .. 'build/initiate.lua')
dofile(repoRoot .. 'modules/locales/shared.lua')
dofile(repoRoot .. 'modules/locales/client.lua')

harness.test('uses the configured fallback before a player preference exists', function()
    harness.assertEqual(Kora.lang('greeting', { name = 'Ada' }), 'Hello Ada')
end)

harness.test('treats named placeholders and replacements as literal text', function()
    harness.assertEqual(Kora.lang('literal', { ['a.b'] = '50% complete' }), 'Value: 50% complete')
end)

harness.test('falls back to English when the configured language is invalid', function()
    local configured = convars.qb_locale
    convars.qb_locale = '../outside'
    Kora.locale._language = nil

    harness.assertEqual(Kora.locale.getLanguage(), 'en')
    harness.assertEqual(Kora.lang('greeting', { name = 'Ada' }), 'Hello Ada')

    convars.qb_locale = configured
end)

harness.test('rejects malformed explicit resource names before locale file lookup', function()
    harness.assertThrows(function() Kora.locale.translate('../legacy', 'greeting') end)
end)

harness.test('stores a player language in client KVP and switches lookup immediately', function()
    local ok, err = Kora.locale.setLanguage('de')
    harness.assertTrue(ok, err)
    harness.assertEqual(kvps.locale, 'de', 'language should be stored in kora_lib client KVP')
    harness.assertEqual(Kora.locale.getLanguage(), 'de')
    harness.assertEqual(Kora.lang('greeting', { name = 'Ada' }), 'Hallo Ada')
    harness.assertEqual(Kora.lang('positional', 'Ada'), 'Hallo Ada')
    harness.assertEqual(Kora.lang('fallback'), 'English', 'missing selected-language keys should fall back to English')
    harness.assertEqual(events[#events - 1].name, 'kora_lib:client:localeChanged')
    harness.assertEqual(events[#events].name, 'qblib:client:localeChanged', 'deprecated alias for older listeners')
end)

harness.test('rejects a language the server has not offered', function()
    local ok = Kora.locale.setLanguage('fr')
    harness.assertFalse(ok)
    harness.assertEqual(Kora.locale.getLanguage(), 'de', 'a rejected choice must not overwrite the preference')
end)

harness.test('loads compatibility locale tables without executing their side effects', function()
    harness.assertEqual(Kora.locale.translate('legacy', 'greeting'), 'Legacy English')
end)

harness.report('locales')
