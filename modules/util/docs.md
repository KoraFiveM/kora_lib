# Utility module

Small shared, dependency-free helpers:

- `QB.util.deepClone(value)` recursively copies plain tables.
- `QB.util.clamp(value, min, max)` bounds a number.
- `QB.util.round(value, decimals?)` rounds to decimal places.
- `QB.util.randomFloat(min, max)` returns a uniform float in the range.
- `QB.util.weightedChoice(list)` selects from `{ value, positiveWeight }`
  pairs; weights are relative and need not sum to 1 or 100.
- `QB.util.tableContains(table, value)` scans values for equality.
