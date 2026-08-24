# rewards module guide

## Purpose
This module rolls one or more items out of a reward pool (loot tables, job/quest payouts, gambling outcomes), so call sites don't hand-roll weighted-random or percent-chance selection logic themselves.

## Public API
- `QB.rewards.generate(items, opts)`
  - Rolls rewards out of `items` per `opts.mode` (`"weighted"` default, or `"percent"`), `opts.rolls` times.
  - Returns copies of the winning items with `amount` resolved to a number. Non-empty unless `opts.allowNone` is `true`.

## Implementation notes
- Weighted-mode picks are delegated to `QB.util.weightedChoice` rather than reimplementing cumulative-weight selection — don't duplicate that logic here if it grows.
- `chance` is deliberately mode-overloaded (relative weight vs. 0-100 percent) rather than split into two fields, to keep one `items` table reusable if a caller ever needs to build both a weighted and a percent variant from the same source data.
- Items missing `chance` default to an equal share *among themselves* (weight `1` each, or an even split of `100`), independent of what other items explicitly specified — this matches "equal chance" rather than "whatever's left over."
- The empty-result guarantee re-rolls via the same weighted pool used for normal picks (even in percent mode), so it stays consistent with each item's relative likelihood instead of falling back to a uniform pick or always `items[1]`.
- `toReward` strips `chance` from the output (it's selection-time-only) but passes every other field through untouched, so callers can pass arbitrary item data (name, label, custom flags) without this module needing to know its shape.

## Best practices
- Use `"weighted"` mode for "give exactly one of these" (a single loot drop, a gacha pull). Use `"percent"` mode for "each of these independently might drop" (e.g. bonus chance for extra items).
- Set `opts.rolls` rather than calling `generate` in a loop — a single call reuses one resolved chance table across all rolls instead of recomputing it each time.
- Only pass `allowNone = true` when an empty result is a meaningful, expected outcome for the caller (e.g. "you found nothing this time") — otherwise leave the default guarantee in place.

## Testing
- `test/smoke/rewards.lua` covers both modes, the default-chance split, `rolls`, and the `allowNone` guarantee.
