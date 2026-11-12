---
title: "Random module"
sidebar_position: 50
---

# Random module

Small shared helpers for choosing random values from arrays.

## `Kora.random.pick(list, options?)`

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
