# Anim module

`QB.anim.play` streams and tracks a normal animation, while `QB.anim.stop` and
`QB.anim.stopHandle` safely end it. `QB.anim.isPlaying(entity)` reads its live
native state. `QB.anim.attachProp`/`QB.anim.detachProp` manage local attached
props and resource-stop cleanup.

For native scenario/task flows, use:

- `QB.anim.playScenario(entity, scenario, enterVehicle?)`
- `QB.anim.clear(entity, immediate?)`

`clear` also stops a tracked qblib animation before clearing ped tasks.
