---
title: "Rewards module"
sidebar_position: 44
---

# Rewards module

## Overview
The rewards module rolls one or more items out of a reward pool — loot tables, quest/job payouts, gambling outcomes, anything shaped like "give the player something from this list." It supports two selection modes, per-item chance with a sensible equal-chance default, multiple rolls in one call, and a guarantee against an empty result unless the caller opts out of it.

## API

### `Kora.rewards.generate(items, opts)`
Generates rewards from a pool of possible items.

#### Parameters
- `items: KoraRewardItem[]` — Reward pool. Must be a non-empty dense array. Each entry may carry:
  - `chance?: number` — A finite positive number. Weighted mode: a relative weight. Percent mode: a probability in `(0, 100]`. Omitted entirely, an item shares an equal chance with every other item that also omitted it (see [Default chance](#default-chance) below).
  - `amount?: number | { min: integer, max: integer }` — A finite flat amount, or integer range to roll. Defaults to `1`.
  - Any other fields (`name`, `label`, ...) are your own data and pass straight through to the result untouched.
- `opts?: table`
  - `mode?: "weighted" | "percent"` — Defaults to `"weighted"` when omitted.
  - `rolls?: finite integer` — How many times to roll, from `1` to `10,000`.
    Defaults to `1` when omitted. In percent mode, `rolls × item count` must
    also be at most `10,000`.
  - `allowNone?: boolean` — Defaults to `false`. When `false`, an all-miss result is topped up with one extra pick so `generate` never hands back an empty table. Pass `true` to allow a genuinely empty result.

Every item must be a table at a consecutive integer index; `opts` must be a table when supplied. Invalid
amount ranges, options, and chance values fail before any random roll occurs.
The result ceiling keeps one generated loot table from allocating an unbounded
number of reward entries; batch larger jobs deliberately.

#### Returns
- `table[]` — A shallow copy of each winning item, with `amount` resolved to a concrete number. Nested custom tables remain shared with the source item. Guaranteed non-empty unless `opts.allowNone` is `true`.

#### Modes
| Mode | Behavior per roll |
|---|---|
| `"weighted"` (default) | Picks exactly **one** item. `chance` is a relative weight against the others — weights don't need to sum to any particular total. |
| `"percent"` | Rolls **every** item independently against its own `chance` out of 100. A single roll can return any number of items — all of them, some, or none. |

#### Default chance
Items that don't specify `chance` split an equal share among themselves — other items' explicit chances don't affect this:
- Weighted mode: each unspecified item gets a weight of `1`.
- Percent mode: unspecified items split `100` evenly, e.g. two unspecified items each get `50`.

#### Multiple rolls
`opts.rolls` repeats the roll that many times, accumulating every hit into the returned array. In weighted mode this is how you get more than one reward out of a single call — each roll independently picks one item (with replacement, so the same item can come up more than once). In percent mode it multiplies the number of independent passes over the whole pool.

#### Example
```lua
-- Weighted: one item per roll, three rolls
local items = {
    { name = "bread", label = "Bread", chance = 60, amount = { min = 1, max = 2 } },
    { name = "gold_watch", label = "Gold Watch", chance = 5 },
    { name = "water_bottle", label = "Water" }, -- no chance: weight 1
}

local rewards = Kora.rewards.generate(items, { rolls = 3 })
-- e.g. { { name = "bread", label = "Bread", amount = 2 }, { name = "water_bottle", ... }, { name = "bread", ... } }
```

```lua
-- Percent: every item rolled independently, can return 0-N items per pass
local items = {
    { name = "bandage", chance = 80 },
    { name = "rare_gem", chance = 2 },
}

local rewards = Kora.rewards.generate(items, { mode = "percent" })
-- guaranteed non-empty: if both misses, one is force-picked as a fallback
```

```lua
-- Explicitly allow an empty result
local rewards = Kora.rewards.generate(items, { mode = "percent", allowNone = true })
-- rewards may be {}
```

## Notes
- Weighted-mode selection is built on `Kora.util.weightedChoice`, so weights follow the same "relative to each other, don't need to sum to anything" rules documented there.
- `amount` ranges are rolled with `math.random(min, max)` and expect integers.
- The empty-result guarantee (`allowNone = false`) reuses the same weighted pool as a fallback pick, even in percent mode, so a higher `chance` still makes an item more likely to be the fallback.
