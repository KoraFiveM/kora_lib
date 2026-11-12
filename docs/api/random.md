---
title: "Random"
sidebar_position: 50
---


# Random

Chooses one or more values uniformly from a dense Lua array. Use it for a simple unweighted pool, such as selecting a random pedestrian model or a random line of dialogue. For weighted chances, reward ranges, or probability rules, use Kora.rewards instead.

Namespace: `Kora.random` · Source: `modules/random/shared.lua`

## pick options

Pass an options table as the second argument. Each option defaults only when omitted. A `?` after a name means the option is optional.

| Option | Type | Description |
| --- | --- | --- |
| `count?` | integer | Number of independent selections. Defaults to 1; allowed range is 1–10,000. More than one returns an array. |
| `maxIndex?` | integer | Last eligible array index. Defaults to #list and must be between 1 and the array length. |

## With replacement

Each selection is independent. The module does not remove a selected value from the list, so requesting several picks can return duplicates. If you need a no-duplicate draw, build that behavior explicitly or shuffle a copy of the list.

## Choosing the right helper

Random.pick treats every eligible list entry as equally likely. Use Kora.rewards.generate when a choice needs configured weights, chance percentages, or amount ranges.

## Functions

pick returns one value by default or a list when count is greater than one.

### `Kora.random.pick(list, options?)`

Selects one or more random values from a non-empty dense array. By default it returns one value; set count to receive an array. Picks are made with replacement, so duplicates are possible.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `list` | table | Non-empty dense array with indexes beginning at 1 and no gaps. |
| `options?` | table | Optional count and maxIndex settings; see the options table above. |

**Returns**

- **value** — chosen item when count is omitted or 1.
- **values** — array of chosen items when count is greater than 1.

**Example**

```lua
local peds = { 'common_a', 'common_b', 'uncommon_a', 'rare_a' }
local commonPed = Kora.random.pick(peds, { maxIndex = 2 })
local twoPeds = Kora.random.pick(peds, { count = 2 })
print(commonPed)
for _, model in ipairs(twoPeds) do print(model) end
```

**Representative console output**

```text
Prints one common model, then two independently selected models. The two may match.
```

## Limits and related APIs

The list must be a non-empty dense array. The count cap of 10,000 prevents one call from allocating an unbounded result table.

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/random/docs.md` or `local/random/docs.md`) that the reference above does not state.

Small shared helpers for choosing random values from arrays.

### `Kora.random.pick(list, options?)`

Picks from a non-empty array. With the default `count = 1`, it returns the
selected value directly:

```lua
local ped = Kora.random.pick(Config.Peds)
```

Options:

- `count?: finite integer` — number of independent picks from `1` to `10,000`;
  defaults to `1`. A count greater than one returns an array of values. Picks
  are made with replacement, so a value can appear more than once.
- `maxIndex?: finite integer` — highest eligible index; defaults to `#list`. This is
  useful when only the first part of an array should be considered.

```lua
local commonPed = Kora.random.pick(Config.Peds, { maxIndex = 5 })
local threePeds = Kora.random.pick(Config.Peds, { count = 3 })
```

This also suits an unweighted reward pool. Use `Kora.rewards.generate` instead
when rewards have relative weights, percentage chances, or amount ranges.

The list must be a non-empty dense array. `count` and `maxIndex` default only when omitted;
otherwise `count` must be a finite integer from `1` to `10,000` and `maxIndex`
must be an integer between `1` and `#list`. The count ceiling prevents one
request from allocating an unbounded result table; batch larger jobs yourself.
