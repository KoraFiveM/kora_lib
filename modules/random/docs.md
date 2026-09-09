# Random module

Small shared helpers for choosing random values from arrays.

## `QB.random.pick(list, options?)`

Picks from a non-empty array. With the default `count = 1`, it returns the
selected value directly:

```lua
local ped = QB.random.pick(Config.Peds)
```

Options:

- `count?: integer` — number of independent picks; defaults to `1`. A count
  greater than one returns an array of values. Picks are made with replacement,
  so a value can appear more than once.
- `maxIndex?: integer` — highest eligible index; defaults to `#list`. This is
  useful when only the first part of an array should be considered.

```lua
local commonPed = QB.random.pick(Config.Peds, { maxIndex = 5 })
local threePeds = QB.random.pick(Config.Peds, { count = 3 })
```

This also suits an unweighted reward pool. Use `QB.rewards.generate` instead
when rewards have relative weights, percentage chances, or amount ranges.

The list must be non-empty. `count` must be a positive integer and `maxIndex`
must be an integer between `1` and `#list`.
