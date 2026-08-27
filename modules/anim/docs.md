# Anim module

`QB.anim.play` streams and tracks a normal animation, while `stop` and
`stopHandle` safely end it. `attachProp`/`detachProp` manage local attached
props and resource-stop cleanup.

For native scenario/task flows, use:

- `QB.anim.playScenario(entity, scenario, enterVehicle?)`
- `QB.anim.clear(entity, immediate?)`

`clear` also stops a tracked qblib animation before clearing ped tasks.
