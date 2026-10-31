local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

mocks.install()

dofile(repoRoot .. "config.lua")
dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "local/resources/client.lua")

local primaryCalls = 0
local tokenCalls = 0
local lastOverrides
local tokenResult = { primary = "262.1 83.3% 57.8%", background = "0 0% 6.3%" }

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
    },
}

dofile(repoRoot .. "modules/theme/shared.lua")

harness.test("accentColor permanently forwards to qbtheme", function()
    harness.assertEqual(Kora.theme.accentColor(), "#7C3AED", "primary value")
    harness.assertEqual(primaryCalls, 1, "qbtheme export call count")
end)

harness.test("tokens permanently forwards string overrides to qbtheme", function()
    local result = Kora.theme.tokens("#7C3AED")
    harness.assertEqual(result, tokenResult, "returned token table")
    harness.assertEqual(lastOverrides, "#7C3AED", "string override")
    harness.assertEqual(tokenCalls, 1, "qbtheme export call count")
end)

harness.test("tokens permanently forwards semantic override tables to qbtheme", function()
    local overrides = { primary = "#DC143C", warning = "#F59E0B" }
    Kora.theme.tokens(overrides)
    harness.assertEqual(lastOverrides, overrides, "table override")
end)

local nuiCallbacks = {}
_G.RegisterNUICallback = function(name, fn)
    nuiCallbacks[name] = fn
end

local refreshCalls = 0
local refreshResult = { primary = "262.1 83.3% 57.8%" }
_G.QBTheme = {
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

harness.test("push delegates to the imported qbtheme bridge", function()
    harness.assertEqual(Kora.theme.push(), refreshResult, "bridge return value")
    harness.assertEqual(refreshCalls, 1, "bridge refresh call count")
end)

harness.report("theme")
