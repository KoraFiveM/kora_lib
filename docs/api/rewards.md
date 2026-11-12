---
title: "Rewards"
sidebar_position: 44
---


# Rewards

Builds reward results from a list of possible items. Use weighted mode when one item should win according to relative weights, or percent mode when every item should roll independently. The module resolves amount ranges and normally guarantees at least one result.

Namespace: `Kora.rewards` · Source: `modules/rewards/shared.lua`

## Reward definition and roll settings

Item fields describe each possible reward. The options table controls how the full pool is rolled. A `?` after a name means the option is optional.

### Each item in items[]

| Option | Type | Description |
| --- | --- | --- |
| `chance?` | number | Finite positive chance value. In weighted mode it is relative weight; in percent mode it is a probability from greater than 0 through 100. If omitted, it shares equally with other entries that also omit chance. |
| `amount?` | number \| &#123; min, max &#125; | Fixed finite amount or inclusive integer range with min &lt;= max. Defaults to 1. |
| `custom fields?` | any | Other fields such as name, label, or metadata pass through unchanged. chance is used for selection and is not included in the result. |

### opts table

| Option | Type | Description |
| --- | --- | --- |
| `mode?` | 'weighted' \| 'percent' | weighted (default) selects one item per roll using relative weights. percent independently rolls every item using its chance. |
| `rolls?` | integer | Number of passes through the pool, from 1 to 10,000. Defaults to 1. In percent mode, rolls multiplied by the item count must also be at most 10,000. |
| `allowNone?` | boolean | Defaults false. When false, an all-miss result gets one fallback pick. Set true only when an empty result is a valid outcome. |

## Weighted mode

Each pass selects exactly one item. chance is a relative weight, so values do not need to add up to 100. An item with no chance gets weight 1, shared equally with other items that also omit chance. Multiple rolls select independently with replacement, so an item can appear more than once.

## Percent mode

Every item is checked independently on every pass. chance is a percentage from greater than 0 to 100. Items without chance split 100 evenly among themselves. A pass may select none, one, or several items; unless allowNone is true, the module adds a fallback pick if all passes miss.

## What the returned copy means

The returned item is a shallow copy. Its amount is always a concrete number; nested custom tables remain shared references. Use the result to decide what to grant, and perform the actual inventory or money changes in your server-side game logic.

## Functions

generate accepts a dense reward pool and optional roll settings. It returns copies of winning entries with their amount resolved to a number.

### `Kora.rewards.generate(items, opts?)`

Rolls a reward pool and returns the winning item entries. Custom fields such as name, label, or metadata are copied through so the caller can decide how to grant them.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `items` | table[] | Non-empty dense array of reward definitions. Each entry is a table; see the item fields above. |
| `opts?` | table | Optional mode, rolls, and allowNone settings described above. |

**Returns**

- **rewards** — array of shallow copies of winning entries with amount set to a concrete number. By default this array is never empty.

**Example**

```lua
local pool = {
    { name = 'bread', chance = 60, amount = { min = 1, max = 2 } },
    { name = 'watch', chance = 5 },
    { name = 'water' },
}
local rewards = Kora.rewards.generate(pool, { rolls = 2 })
for _, reward in ipairs(rewards) do
    print(reward.name, reward.amount)
end
```

**Representative console output**

```text
Prints each selected reward name and its resolved amount.
```

## Limits and related APIs

Invalid arrays, chances, amount ranges, options, and roll limits are rejected before random selection begins. This function selects rewards; it does not grant inventory items or authorize the caller.

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/rewards/docs.md` or `local/rewards/docs.md`) that the reference above does not state.

### API

#### `Kora.rewards.generate(items, opts)`
Generates rewards from a pool of possible items.

##### Parameters
- `items: KoraRewardItem[]` — Reward pool. Must be a non-empty dense array. Each entry may carry:
  - `chance?: number` — A finite positive number. Weighted mode: a relative weight. Percent mode: a probability in `(0, 100]`. Omitted entirely, an item shares an equal chance with every other item that also omitted it (items without `chance` split an equal share).
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

##### Example
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
