-- Parity harness smoke test (tools/parity). Always self-tests the extractor and
-- diff on a tiny fixture. If OX_LIB_SHIM_PATH points at an ox_lib-shaped tree
-- (the shim or an upstream checkout), also diffs it against the committed
-- 3.39.0 golden; if OX_INVENTORY_PATH is set, diffs ox_inventory's API usage.
local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = table.concat({ testDir .. "?.lua", repoRoot .. "tools/parity/?.lua", package.path }, ";")

local harness = require("harness")
local common = require("common")
local surface = require("extract_ox_surface")
local uses = require("extract_ox_uses")
local diff = require("diff")

local goldenDir = repoRoot .. "tools/parity/golden/"

local function has(list, value)
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

local function isDir(path)
    return path and path ~= "" and os.execute(("test -d '%s'"):format(path)) == true
end

local function loadGolden(name)
    return common.decode(assert(common.readFile(goldenDir .. name), "missing golden " .. name))
end

harness.test("extractor reads the fixture surface", function()
    local s = surface.extract(testDir .. "fixtures/ox_surface")
    harness.assertEqual(s.meta.version, "1.2.3", "version")
    harness.assertEqual(table.concat(s.lib.imports, ","), "bar,foo", "imports")
    harness.assertTrue(has(s.lib.resource, "onCache") and has(s.lib.resource, "setThing"), "resource lib keys")
    harness.assertFalse(has(s.lib.resource, "commented"), "comments are ignored")
    harness.assertTrue(has(s.exports.client, "notify") and has(s.exports.client, "barExport"), "client exports")
    harness.assertTrue(has(s.exports.server, "versionCheck") and has(s.exports.server, "extraExport"), "server exports")
    harness.assertTrue(has(s.exports.shared, "hasLoaded"), "shared export")
    harness.assertFalse(has(s.exports.client, "onCache"), "init.lua keys are not auto-exported")
    harness.assertEqual(s.exports.dynamic[1], "registerHook:%s", "dynamic export family")
    harness.assertTrue(has(s.events, "ox_lib:notify") and has(s.events, "__ox_cb_%s"), "events")
    harness.assertTrue(has(s.convars, "ox:primaryColor"), "convars")
    harness.assertTrue(has(s.nui.actions, "notify") and has(s.nui.callbacks, "uiDone"), "nui")
    harness.assertTrue(has(s.manifest.oxLib, "locale") and has(s.manifest.oxLib, "math"), "ox_lib metadata values")
    harness.assertTrue(has(s.lib.subkeys.foo, "foo:baz") and has(s.lib.subkeys.foo, "foo.qux"), "sub-keys")
    harness.assertEqual(s.summary.exportsTotal, 6, "export total")
    harness.assertEqual(s.locales[1], "en", "locales")
end)

harness.test("uses extractor reads the fixture consumer", function()
    local u = uses.extract(testDir .. "fixtures/ox_uses")
    harness.assertEqual(u.lib["callback.await"], 1, "lib.callback.await")
    harness.assertEqual(u.lib["notify"], 1, "lib.notify")
    harness.assertEqual(u.cache.ped, 1, "cache.ped")
    harness.assertEqual(u.cache.vehicle, nil, "other.cache.* is not cache.*")
    harness.assertEqual(u.mysql["MySQL.query.await"], 1, "MySQL form")
    harness.assertEqual(u.oxTarget.addModel, 1, "exports.ox_target")
    harness.assertEqual(u.summary.requireCalls, 1, "require count")
    harness.assertEqual(u.lib["commented.out"], nil, "comments are ignored")
end)

harness.test("JSON round-trips", function()
    local s = surface.extract(testDir .. "fixtures/ox_surface")
    local again = common.decode(common.encode(s))
    local r = diff.compare(s, again, { failOn = "both" })
    harness.assertFalse(r.failed, "round trip differs: " .. diff.format(r))
    harness.assertEqual(common.encode(again), common.encode(s), "stable encoding")
end)

harness.test("diff reports missing and extra and honours fail-on and soft", function()
    local golden = { lib = { resource = { "a", "b" } }, nui = { actions = { "x" } }, uses = { ["f.g"] = 2 } }
    local actual = { lib = { resource = { "a", "c" } }, nui = { actions = {} }, uses = { ["f.g"] = 5, ["f.h"] = 1 } }
    local r = diff.compare(golden, actual, { failOn = "missing" })
    harness.assertEqual(table.concat(r.missing, ","), "lib.resource:b,nui.actions:x", "missing")
    harness.assertEqual(table.concat(r.extra, ","), "lib.resource:c,uses:f.h", "extra")
    harness.assertTrue(r.failed, "missing fails")
    local soft = diff.compare(golden, actual, { failOn = "missing", soft = { "nui.", "lib.resource:b" } })
    harness.assertFalse(soft.failed, "soft entries do not fail")
    harness.assertEqual(#soft.softMissing, 2, "soft missing is still reported")
    harness.assertFalse(diff.compare(golden, golden, { failOn = "both" }).failed, "identical is clean")
    local extraOnly = diff.compare({ k = { "a" } }, { k = { "a", "b" } }, { failOn = "missing" })
    harness.assertFalse(extraOnly.failed, "extra alone passes under fail-on missing")
    harness.assertTrue(diff.compare({ k = { "a" } }, { k = { "a", "b" } }, { failOn = "extra" }).failed, "extra fails under fail-on extra")
end)

harness.test("committed goldens decode and keep their headline numbers", function()
    local lib = loadGolden("ox_lib-3.39.0.json")
    harness.assertEqual(lib.meta.version, "3.39.0", "golden version")
    harness.assertEqual(lib.summary.exportsTotal, 52, "static exports")
    harness.assertEqual(lib.summary.locales, 33, "locales")
    harness.assertEqual(lib.summary.nuiCallbacks, 18, "nui callbacks")
    harness.assertEqual(lib.summary.nuiActions, 19, "nui actions")
    local inv = loadGolden("ox_inventory-2.48.1-uses.json")
    harness.assertTrue(inv.lib["callback.register"] ~= nil, "ox_inventory uses lib.callback.register")
    harness.assertTrue(inv.mysql["MySQL.query.await"] ~= nil, "ox_inventory uses MySQL.query.await")
end)

-- The shim is headless: its UI is forwarded to kora_lib, so the NUI contract,
-- the NUI-only convars and the web manifest keys are reported, not enforced.
local SHIM_SOFT = { "nui.", "manifest.keys:", "convars:ox:primary" }

harness.test("target ox_lib tree has no regressions against the 3.39.0 golden", function()
    local target = os.getenv("OX_LIB_SHIM_PATH")
    if not isDir(target) then
        print("ok - skipped (set OX_LIB_SHIM_PATH to an ox_lib-shaped tree to run the surface diff)")
        return
    end
    local result = diff.compare(loadGolden("ox_lib-3.39.0.json"), surface.extract(target), { failOn = "missing", soft = SHIM_SOFT })
    if result.failed then error("surface regression:\n" .. diff.format(result), 0) end
end)

harness.test("ox_inventory usage matches its golden (no unreviewed APIs)", function()
    local target = os.getenv("OX_INVENTORY_PATH")
    if not isDir(target) then
        print("ok - skipped (set OX_INVENTORY_PATH to an ox_inventory checkout to run the usage diff)")
        return
    end
    local result = diff.compare(loadGolden("ox_inventory-2.48.1-uses.json"), uses.extract(target), { failOn = "extra" })
    if result.failed then error("new ox_inventory API usage:\n" .. diff.format(result), 0) end
end)

harness.report("ox surface")
