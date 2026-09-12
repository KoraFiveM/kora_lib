local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

local net = mocks.install()

dofile(repoRoot .. "config.lua")
dofile(repoRoot .. "build/initiate.lua")

-- Same "mock QB.nui directly, resolve synchronously" trick
-- test/smoke/minigames.lua and compat_qb_menu.lua use -- ShowInput has to
-- consume QB.nui.openInputDialog's result itself (to return the legacy
-- table-or-false shape), not just hand a promise back to its own caller.
local sentFields = nil
local sentTitle = nil
local nextResult = nil

QB.nui = {
    openInputDialog = function(fields, title)
        sentFields = fields
        sentTitle = title
        local p = promise.new()
        p:resolve(nextResult)
        return p
    end,
}

dofile(repoRoot .. "compat/shared.lua")
dofile(repoRoot .. "compat/client/qb-input.lua")

-- Mirrors what a real cross-resource exports['qb-input']:Fn() call does
-- under the hood: fire the __cfx_export_ event with a setCB stub and capture
-- what gets passed to it.
local function getExport(providedResource, exportName)
    local handlers = net.eventHandlers[("__cfx_export_%s_%s"):format(providedResource, exportName)]
    harness.assertTrue(handlers ~= nil and handlers[1] ~= nil, exportName .. " should be registered")

    local captured
    handlers[1](function(fn) captured = fn end)
    return captured
end

local ShowInput = getExport("qb-input", "ShowInput")

local function fieldById(id)
    for _, field in ipairs(sentFields) do
        if field.id == id then return field end
    end
    return nil
end

harness.test("ShowInput forwards the header as title and maps name/text/isRequired", function()
    nextResult = { cancelled = true }
    ShowInput({
        header = "Withdraw",
        inputs = { { name = "amount", text = "Amount", type = "number", isRequired = true, default = 5, min = 1, max = 100 } },
    })

    harness.assertEqual(sentTitle, "Withdraw", "header should map to title")
    local field = fieldById("amount")
    harness.assertTrue(field ~= nil, "field id should equal the legacy input's name")
    harness.assertEqual(field.label, "Amount", "text should map to label")
    harness.assertEqual(field.type, "number", "number should pass through as-is")
    harness.assertTrue(field.required, "isRequired should map to required")
    harness.assertEqual(field.default, 5, "default should pass through")
    harness.assertEqual(field.min, 1, "min should pass through for number")
    harness.assertEqual(field.max, 100, "max should pass through for number")
end)

harness.test("text/password/textarea pass through unchanged", function()
    nextResult = { cancelled = true }
    ShowInput({ inputs = {
        { name = "a", type = "text" },
        { name = "b", type = "password" },
        { name = "c", type = "textarea" },
    } })

    harness.assertEqual(fieldById("a").type, "text")
    harness.assertEqual(fieldById("b").type, "password")
    harness.assertEqual(fieldById("c").type, "textarea")
end)

harness.test("checkbox honours 'checked' over 'default' when both are set", function()
    nextResult = { cancelled = true }
    ShowInput({ inputs = { { name = "flag", type = "checkbox", default = false, checked = true } } })

    harness.assertEqual(fieldById("flag").type, "checkbox")
    harness.assertTrue(fieldById("flag").default, "checked should win over default")
end)

-- Real qb-input's "checkbox" type is a GROUP of checkboxes, each carrying
-- its own `options[]` entry, and the submitted result is keyed by EACH
-- OPTION'S value -- not by the input's own `name` at all (see
-- qbcore-framework/qb-input's html/script.js renderCheckboxInput). This must
-- expand into one InputField per option, keyed by that option's value, so a
-- script written against the real resource gets the same result shape back.
harness.test("a checkbox WITH options expands into one field per option, keyed by option value", function()
    nextResult = { cancelled = true }
    ShowInput({ inputs = { {
        name = "perms",
        text = "Permissions",
        type = "checkbox",
        options = {
            { value = "canOpen", text = "Can Open", checked = true },
            { value = "canClose", text = "Can Close", checked = false },
        },
    } } })

    harness.assertTrue(fieldById("perms") == nil, "the group's own name should not become a field id")

    local canOpen = fieldById("canOpen")
    harness.assertTrue(canOpen ~= nil, "each option's value should become its own field id")
    harness.assertEqual(canOpen.type, "checkbox")
    harness.assertTrue(canOpen.default, "the option's own 'checked' should seed the field default")
    harness.assertEqual(canOpen.label, "Permissions: Can Open", "the group text should prefix each option's label")

    local canClose = fieldById("canClose")
    harness.assertTrue(canClose ~= nil)
    harness.assertFalse(canClose.default)
end)

harness.test("submitting a checkbox group returns each option's value as its own key, matching upstream", function()
    nextResult = { values = { canOpen = true, canClose = false } }
    local result = ShowInput({ inputs = { {
        name = "perms",
        type = "checkbox",
        options = { { value = "canOpen" }, { value = "canClose" } },
    } } })

    harness.assertTrue(result.canOpen, "the legacy result[option.value] lookup should work, not result[name]")
    harness.assertFalse(result.canClose)
end)

-- A checkbox with no `options` at all (some simplified qb-input forks use a
-- single scalar boolean instead of a group) must keep working exactly as
-- before -- this is the case the pre-existing "checked' over 'default'" test
-- above already covers; this one just pins down that it stays keyed by name.
harness.test("a checkbox with no options stays a single field keyed by name", function()
    nextResult = { cancelled = true }
    ShowInput({ inputs = { { name = "flag", type = "checkbox", default = true } } })

    harness.assertEqual(#sentFields, 1, "a plain checkbox should not expand")
    harness.assertEqual(sentFields[1].id, "flag")
end)

harness.test("radio and select both collapse onto 'select' with translated options", function()
    nextResult = { cancelled = true }
    ShowInput({ inputs = {
        { name = "r", type = "radio", options = { { value = "a", text = "Option A" } } },
        { name = "s", type = "select", options = { { value = 1, label = "One" } } },
    } })

    harness.assertEqual(fieldById("r").type, "select", "radio should collapse onto select")
    harness.assertEqual(fieldById("r").options[1].value, "a")
    harness.assertEqual(fieldById("r").options[1].label, "Option A", "text should map to label")

    harness.assertEqual(fieldById("s").type, "select")
    harness.assertEqual(fieldById("s").options[1].value, "1", "option values should be stringified")
    harness.assertEqual(fieldById("s").options[1].label, "One", "label wins when text is absent")
end)

harness.test("slider maps onto range with min/max/step", function()
    nextResult = { cancelled = true }
    ShowInput({ inputs = { { name = "vol", type = "slider", min = 0, max = 10, step = 2 } } })

    local field = fieldById("vol")
    harness.assertEqual(field.type, "range")
    harness.assertEqual(field.min, 0)
    harness.assertEqual(field.max, 10)
    harness.assertEqual(field.step, 2)
end)

harness.test("an unrecognized type falls back to text instead of erroring", function()
    nextResult = { cancelled = true }
    ShowInput({ inputs = { { name = "weird", type = "date-of-birth" } } })

    harness.assertEqual(fieldById("weird").type, "text", "unknown types should fall back to text")
end)

harness.test("submitting returns the values table keyed by name, unreshaped", function()
    nextResult = { values = { amount = 42 } }
    local result = ShowInput({ inputs = { { name = "amount", type = "number" } } })

    harness.assertEqual(result.amount, 42, "the legacy result[name] lookup should keep working")
end)

harness.test("cancelling returns false, not nil or {cancelled = true}", function()
    nextResult = { cancelled = true }
    local result = ShowInput({ inputs = { { name = "amount", type = "number" } } })

    harness.assertEqual(result, false, "cancel should return exactly false, matching real qb-input")
end)

harness.test("a timeout/error (nil result) also returns false", function()
    nextResult = nil
    local result = ShowInput({ inputs = { { name = "amount", type = "number" } } })

    harness.assertEqual(result, false, "a nil NUI result should still surface as false, never nil")
end)

harness.test("ShowInput mirrors upstream's nil response for malformed or concurrent requests", function()
    harness.assertEqual(ShowInput("nope"), nil, "a non-table request should return nil")
    harness.assertEqual(ShowInput({}), nil, "a request with no inputs should return nil")
end)

harness.test("a field with no name is rejected", function()
    harness.assertThrows(function()
        ShowInput({ inputs = { { type = "text" } } })
    end, "an input with no name should be rejected")
end)

-- QB.nui.openInputDialog returns an already-awaited result while the
-- compatibility export is handling a call from another resource. Awaiting
-- that table a second time would silently turn it into nil in real CfxLua.
harness.test("the export path consumes QB.nui.openInputDialog's plain result directly", function()
    _G.GetInvokingResource = function() return "consumer-resource" end
    QB.nui.openInputDialog = function()
        return { values = { amount = 42 } }
    end

    local result = ShowInput({ inputs = { { name = "amount", type = "number" } } })

    harness.assertEqual(result.amount, 42, "the legacy values table should survive the export path")
    _G.GetInvokingResource = function() return nil end
end)

harness.report("compat_qb_input")
