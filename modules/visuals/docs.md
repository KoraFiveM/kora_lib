# Visual effects module

Client-side screen/drug-effect conveniences.

- `QB.visuals.fade(duration?, fn?)` fades out, runs `fn` while black, and
  always fades back in. The legacy `fade(coords, duration?)` move remains.
- `QB.visuals.trevor(duration?)`
- `QB.visuals.meth(duration?)`
- `QB.visuals.ecstacy(duration?)`
- `QB.visuals.alien(duration?)`
- `QB.visuals.crack(duration?)`
- `QB.visuals.coke(duration?)`

The named helpers reproduce their established GTA screen/stamina/ragdoll
effects. Long-lived sprint effects are stacked by start order: the newest live
effect owns the multiplier, and ending it restores the previous effect (or the
native default when none remain).
