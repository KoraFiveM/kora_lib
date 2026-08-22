local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

local net = mocks.install()

dofile(repoRoot .. "config.lua")
dofile(repoRoot .. "build/initiate.lua")

dofile(repoRoot .. "modules/theme/shared.lua")

harness.test("accentColor returns the configured value when it's a valid hex", function()
    harness.assertEqual(QB.theme.accentColor(), "#DC143C", "should read Config.ui.accentColor as-is")
end)

harness.test("accentColor falls back to the default on a malformed config value", function()
    local original = Config.ui.accentColor
    Config.ui.accentColor = "not-a-colour"

    harness.assertEqual(QB.theme.accentColor(), "#DC143C", "a malformed config value must fall back to the safe default")

    Config.ui.accentColor = original
end)

-- Critical parity check: web/src/styles/globals.css's :root block hardcodes
-- these as the static pre-JS default, computed from the exact same
-- applyAccentColor formula this module ports from
-- web/src/components/theme/ThemeSynchronizer.tsx. If a future edit to either
-- implementation breaks parity, this fails immediately.
--
-- NOTE: globals.css's checked-in --brand-hover/--brand-pressed values use
-- saturation 83.2%, not 83.3% -- a pre-existing 0.1% drift in that static
-- fallback (every other token, including primary's own 83.3%, matches
-- exactly). ThemeSynchronizer.tsx reuses hslFromHex's *same* `saturation`
-- variable, unrounded again, for every derived token -- so 83.3% is the
-- value a faithful port must produce; asserting 83.2% here would be
-- asserting the drift, not the formula.
harness.test("tokens('#DC143C') matches the formula's output for qblib's default accent", function()
    local tokens = QB.theme.tokens("#DC143C")

    harness.assertEqual(tokens.primary, "348 83.3% 47.1%", "primary")
    harness.assertEqual(tokens.ring, "348 83.3% 47.1%", "ring should equal primary")
    harness.assertEqual(tokens["brand-hover"], "348 83.3% 42%", "brand-hover")
    harness.assertEqual(tokens["brand-pressed"], "348 83.3% 36.5%", "brand-pressed")
    harness.assertEqual(tokens["brand-soft"], "348 83.3% 47.1% / 0.14", "brand-soft")
    harness.assertEqual(tokens["brand-border"], "348 83.3% 47.1% / 0.45", "brand-border")
    harness.assertEqual(tokens["primary-foreground"], "0 0% 100%", "primary-foreground (white passes contrast on crimson)")
end)

harness.test("tokens() defaults to QB.theme.accentColor() when called with no argument", function()
    harness.assertEqual(QB.theme.tokens().primary, QB.theme.tokens("#DC143C").primary, "no-arg call should use the configured accent")
end)

-- A second, non-red-dominant hex exercises hslFromHex's green/blue-dominant
-- hue branches -- crimson (#DC143C) only ever exercises the red-dominant one.
harness.test("tokens() computes a plausible dark foreground for a light, blue-dominant accent", function()
    local tokens = QB.theme.tokens("#7C3AED")

    harness.assertEqual(tokens.primary, "262.1 83.3% 57.8%", "primary for a violet accent")
    harness.assertEqual(tokens["primary-foreground"], "0 0% 100%", "white still passes contrast on this violet")
end)

harness.test("tokens() falls back to the default accent for a malformed argument", function()
    harness.assertEqual(QB.theme.tokens("nonsense").primary, "348 83.3% 47.1%", "an invalid hex argument should fall back like accentColor() does")
end)

-- modules/theme/client.lua only wires the NUI callback (a client-only
-- native); mocked here rather than in test/mocks.lua per the root AGENTS.md
-- convention for module-specific natives.
local nuiCallbacks = {}
_G.RegisterNUICallback = function(name, fn)
    nuiCallbacks[name] = fn
end
_G.SendNUIMessage = function(payload) end

dofile(repoRoot .. "modules/nui/client.lua")
dofile(repoRoot .. "modules/theme/client.lua")

harness.test("qblib:nui:theme callback delegates to QB.theme.accentColor()", function()
    local response
    nuiCallbacks["qblib:nui:theme"]({}, function(result) response = result end)

    harness.assertEqual(response.accentColor, "#DC143C", "the callback's response shape/value must be unchanged by the refactor")
end)

harness.test("push() sends a qblib:theme message carrying the current accent colour", function()
    local sent
    _G.SendNUIMessage = function(payload) sent = payload end

    QB.theme.push()

    harness.assertEqual(sent.action, "qblib:theme", "push should send the qblib:theme action")
    harness.assertEqual(sent.data.accentColor, "#DC143C", "push should carry the current accent colour")
end)

harness.report("theme")
