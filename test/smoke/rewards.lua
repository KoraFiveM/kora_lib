local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

mocks.install()

dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "modules/rewards/shared.lua")
dofile(repoRoot .. "modules/util/shared.lua")

harness.test("rejects an empty item pool", function()
    harness.assertThrows(function()
        Kora.rewards.generate({})
    end, "an empty items array should raise")
end)

harness.test("weighted mode always returns exactly one reward per roll", function()
    local items = {
        { name = "always", chance = 100 },
        { name = "never", chance = 0.0001 },
    }

    local rewards = Kora.rewards.generate(items, { rolls = 5 })
    harness.assertEqual(#rewards, 5, "5 rolls should produce 5 rewards")
end)

harness.test("weighted mode heavily favours a dominant weight", function()
    local items = {
        { name = "common", chance = 1000000 },
        { name = "rare", chance = 1 },
    }

    local rewards = Kora.rewards.generate(items, { rolls = 20 })

    local commonCount = 0
    for _, reward in ipairs(rewards) do
        if reward.name == "common" then commonCount = commonCount + 1 end
    end

    harness.assertTrue(commonCount >= 19, "an overwhelmingly higher weight should win almost every roll")
end)

harness.test("items without a chance default to an equal weight", function()
    local items = {
        { name = "a" },
        { name = "b" },
    }

    local seen = {}
    for _ = 1, 50 do
        local rewards = Kora.rewards.generate(items)
        seen[rewards[1].name] = true
    end

    harness.assertTrue(seen.a and seen.b, "both equally-weighted items should be reachable")
end)

harness.test("percent mode can return every item in one roll", function()
    local items = {
        { name = "a", chance = 100 },
        { name = "b", chance = 100 },
    }

    local rewards = Kora.rewards.generate(items, { mode = "percent" })
    harness.assertEqual(#rewards, 2, "two guaranteed-hit items should both be returned")
end)

harness.test("percent mode never returns an item below a 0 percent chance", function()
    local items = {
        { name = "a", chance = 100 },
        { name = "b", chance = 0.0001 },
    }

    for _ = 1, 20 do
        local rewards = Kora.rewards.generate(items, { mode = "percent", allowNone = true })
        for _, reward in ipairs(rewards) do
            harness.assertFalse(reward.name == "b", "a near-zero percent chance should not realistically hit")
        end
    end
end)

harness.test("percent mode defaults an unspecified item's chance to an equal split of 100", function()
    local items = {
        { name = "a" },
        { name = "b" },
        { name = "c" },
        { name = "d" },
    }

    local hits, checks = 0, 0
    for _ = 1, 100 do
        local rewards = Kora.rewards.generate(items, { mode = "percent", allowNone = true })
        checks = checks + 4
        hits = hits + #rewards
    end

    harness.assertTrue(hits > 0, "a 25% chance should hit at least sometimes across 400 checks")
    harness.assertTrue(hits < checks, "a 25% chance should also miss at least sometimes across 400 checks")
end)

harness.test("rolls multiplies the number of independent percent-mode passes", function()
    local items = { { name = "a", chance = 100 } }

    local rewards = Kora.rewards.generate(items, { mode = "percent", rolls = 4 })
    harness.assertEqual(#rewards, 4, "a guaranteed-hit item rolled 4 times should appear 4 times")
end)

harness.test("guarantees at least one reward by default even on an all-miss percent roll", function()
    local items = {
        { name = "a", chance = 0.0001 },
        { name = "b", chance = 0.0001 },
    }

    for _ = 1, 20 do
        local rewards = Kora.rewards.generate(items, { mode = "percent" })
        harness.assertTrue(#rewards >= 1, "the default guarantee should never allow an empty result")
    end
end)

harness.test("allowNone permits a genuinely empty result", function()
    local items = {
        { name = "a", chance = 0.0001 },
        { name = "b", chance = 0.0001 },
    }

    local sawEmpty = false
    for _ = 1, 200 do
        local rewards = Kora.rewards.generate(items, { mode = "percent", allowNone = true })
        if #rewards == 0 then
            sawEmpty = true
            break
        end
    end

    harness.assertTrue(sawEmpty, "allowNone should let an all-miss roll come back empty")
end)

harness.test("resolves a flat amount", function()
    local items = { { name = "a", chance = 100, amount = 5 } }
    local rewards = Kora.rewards.generate(items)
    harness.assertEqual(rewards[1].amount, 5, "a flat amount should pass through unchanged")
end)

harness.test("resolves an amount range within bounds", function()
    local items = { { name = "a", chance = 100, amount = { min = 3, max = 3 } } }
    local rewards = Kora.rewards.generate(items)
    harness.assertEqual(rewards[1].amount, 3, "a min==max range should resolve to that value")
end)

harness.test("defaults amount to 1 when omitted", function()
    local items = { { name = "a", chance = 100 } }
    local rewards = Kora.rewards.generate(items)
    harness.assertEqual(rewards[1].amount, 1, "an omitted amount should default to 1")
end)

harness.test("passes through arbitrary item fields and strips chance", function()
    local items = { { name = "a", label = "A Label", chance = 100, custom = true } }
    local rewards = Kora.rewards.generate(items)

    harness.assertEqual(rewards[1].label, "A Label", "unrelated fields should pass through")
    harness.assertEqual(rewards[1].custom, true, "unrelated fields should pass through")
    harness.assertEqual(rewards[1].chance, nil, "chance is selection-only and should not appear on the reward")
end)

harness.test("rejects an invalid mode", function()
    harness.assertThrows(function()
        Kora.rewards.generate({ { name = "a" } }, { mode = "bogus" })
    end, "an unknown mode should raise")
    harness.assertThrows(function()
        Kora.rewards.generate({ { name = "a" } }, { mode = false })
    end, "a false mode should not silently default")
end)

harness.test("rejects a percent chance above 100", function()
    harness.assertThrows(function()
        Kora.rewards.generate({ { name = "a", chance = 150 } }, { mode = "percent" })
    end, "a percent chance over 100 should raise")
end)

harness.test("rejects a non-positive chance", function()
    harness.assertThrows(function()
        Kora.rewards.generate({ { name = "a", chance = 0 } })
    end, "a zero chance should raise")
end)

harness.test("rejects non-finite chances and amounts", function()
    harness.assertThrows(function()
        Kora.rewards.generate({ { name = "a", chance = math.huge } })
    end, "an infinite weighted chance should raise")
    harness.assertThrows(function()
        Kora.rewards.generate({ { name = "a", amount = math.huge } })
    end, "an infinite flat amount should raise")
    harness.assertThrows(function()
        Kora.rewards.generate({ { name = "a", amount = { min = 1, max = math.huge } } })
    end, "an infinite range amount should raise")
end)

harness.test("rejects invalid range bounds and option shapes before rolling", function()
    harness.assertThrows(function()
        Kora.rewards.generate({ { name = "a", amount = { min = 1.5, max = 2 } } })
    end, "fractional range bounds should fail before math.random")
    harness.assertThrows(function()
        Kora.rewards.generate({ { name = "a" } }, "weighted")
    end, "options must be a table")
    harness.assertThrows(function()
        Kora.rewards.generate({ { name = "a" } }, { allowNone = "yes" })
    end, "allowNone must be a boolean")
    harness.assertThrows(function()
        Kora.rewards.generate({ "not-an-item" })
    end, "every reward entry must be a table")
    harness.assertThrows(function()
        Kora.rewards.generate({ { name = "a" }, [3] = { name = "b" } })
    end, "sparse reward pools must not silently omit entries")
end)

harness.test("rejects a non-integer rolls value", function()
    harness.assertThrows(function()
        Kora.rewards.generate({ { name = "a" } }, { rolls = 1.5 })
    end, "a fractional rolls value should raise")
    harness.assertThrows(function()
        Kora.rewards.generate({ { name = "a" } }, { rolls = false })
    end, "a false rolls value should not silently default")
    harness.assertThrows(function()
        Kora.rewards.generate({ { name = "a" } }, { rolls = math.huge })
    end, "an infinite rolls value should raise")
    harness.assertThrows(function()
        Kora.rewards.generate({ { name = "a" } }, { rolls = 10001 })
    end, 'weighted rolls must not allocate an unbounded result table')
    harness.assertThrows(function()
        Kora.rewards.generate({ { name = "a" }, { name = "b" } }, { mode = 'percent', rolls = 5001 })
    end, 'percent rolls must bound every potential hit')
end)

harness.report("rewards")
