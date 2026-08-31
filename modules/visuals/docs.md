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
effects. Long-lived sprint effects use generations so an older effect ending
cannot cancel a newer overlapping multiplier.
