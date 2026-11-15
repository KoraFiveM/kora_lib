local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

local mock = mocks.install()

dofile(repoRoot .. "config.lua")
dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "modules/logging/shared.lua")
dofile(repoRoot .. "local/resources/client.lua")

local primaryCalls = 0
local tokenCalls = 0
local lastOverrides
local tokenResult = { primary = "262.1 83.3% 57.8%", background = "0 0% 6.3%" }
local fontResult = {
    body = { id = "poppins", label = "Poppins", stack = '"Kora Poppins", sans-serif', source = "config" },
    heading = { id = "default", label = "Default", stack = '"Kora Poppins", sans-serif', source = "default" },
    mono = { id = "default", label = "Default", stack = "monospace", source = "default" },
}

_G.exports = {
    kora_theme = {
        getPrimaryColor = function()
            primaryCalls = primaryCalls + 1
            return "#7C3AED"
        end,
        getTokens = function(_, overrides)
            tokenCalls = tokenCalls + 1
            lastOverrides = overrides
            return tokenResult
        end,
        getFonts = function()
            return fontResult
        end,
    },
}

dofile(repoRoot .. "modules/theme/shared.lua")

harness.test("accentColor permanently forwards to kora_theme", function()
    harness.assertEqual(Kora.theme.accentColor(), "#7C3AED", "primary value")
    harness.assertEqual(primaryCalls, 1, "kora_theme export call count")
end)

harness.test("tokens permanently forwards string overrides to kora_theme", function()
    local result = Kora.theme.tokens("#7C3AED")
    harness.assertEqual(result, tokenResult, "returned token table")
    harness.assertEqual(lastOverrides, "#7C3AED", "string override")
    harness.assertEqual(tokenCalls, 1, "kora_theme export call count")
end)

harness.test("tokens permanently forwards semantic override tables to kora_theme", function()
    local overrides = { primary = "#DC143C", warning = "#F59E0B" }
    Kora.theme.tokens(overrides)
    harness.assertEqual(lastOverrides, overrides, "table override")
end)

harness.test("getFonts forwards the resolved kora_theme fonts", function()
    harness.assertEqual(Kora.theme.getFonts(), fontResult, "resolved fonts")
    harness.assertEqual(Kora.theme.getFonts().body.stack, '"Kora Poppins", sans-serif', "body stack")
end)

local nuiCallbacks = {}
_G.RegisterNUICallback = function(name, fn)
    nuiCallbacks[name] = fn
end

local refreshCalls = 0
local refreshResult = { primary = "262.1 83.3% 57.8%" }
_G.KoraTheme = {
    refresh = function()
        refreshCalls = refreshCalls + 1
        return refreshResult
    end,
}

dofile(repoRoot .. "modules/nui/client.lua")
dofile(repoRoot .. "modules/theme/client.lua")

harness.test("legacy kora_lib theme callback keeps its response shape", function()
    local response
    nuiCallbacks["kora_lib:nui:theme"]({}, function(result) response = result end)
    harness.assertEqual(response.accentColor, "#7C3AED", "legacy accentColor")
end)

harness.test("push delegates to the imported kora_theme bridge", function()
    harness.assertEqual(Kora.theme.push(), refreshResult, "bridge return value")
    harness.assertEqual(refreshCalls, 1, "bridge refresh call count")
end)

harness.test("onFontsChanged runs on kora_theme font changes until unsubscribed", function()
    local received, calls = nil, 0
    local unsubscribe = Kora.theme.onFontsChanged(function(fonts)
        calls = calls + 1
        received = fonts
    end)
    mock.fire("kora_theme:fontsChanged")
    harness.assertEqual(calls, 1, "handler call count")
    harness.assertEqual(received, fontResult, "handler receives the resolved fonts")
    unsubscribe()
    mock.fire("kora_theme:fontsChanged")
    harness.assertEqual(calls, 1, "unsubscribed handler is not called")
end)

harness.report("theme")
