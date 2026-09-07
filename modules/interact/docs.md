# Interact module

`QB.interact` provides a compact, game-input-driven option selector for qblib zones. It is entirely client-side, remains click-through, and never grants NUI focus.

## Zone API

The zone helpers return normal `QB.zones` handles. Zone names are unique within
this module; adding a duplicate replaces the old zone.

```lua
QB.interact.addCircleZone("locker", vector3(100.0, 200.0, 30.0), 2.0, {
    options = {
        {
            label = "Open locker",
            event = "my-resource:client:openLocker",
            args = { "police" },
        },
    },
}, false)
```

The current signatures are:

- `QB.interact.addCircleZone(name, coords, radius, targetOptions, debug?)`
- `QB.interact.addBoxZone(name, coords, size, targetOptions, debug?)`
- `QB.interact.addTargetEntity(entity, size, targetOptions, debug?)`
- `QB.interact.addTargetModel(models, size, targetOptions, debug?)`

`size` is a vector-like `{x, y, z}` table. The target helpers create static
zones around the current entity/model positions. They do not follow moving
entities; use the aim-target facade below when movement tracking is required.
`QB.interact.removeZone(name)` returns `true` only when a named zone existed.

`QB.interact.open(options)` opens the selector without a zone.
`QB.interact.close()` closes it, and `QB.interact.isActive()` reports whether a
selector is currently open.

## Options

Each option needs a non-empty `label`. On selection it calls `action()`, or triggers `event` locally by default / on the server when `type = "server"`. `args` is forwarded to the action event.

`canInteract()`, `job`, `gang`, `citizenid`, and `item` are evaluated before the selector opens. Restricted options remain hidden if their optional qb-core or qb-inventory dependency is unavailable.

`QB.interact.open(options)` opens the same selector without a zone and returns `true` only if at least one option is currently available. `QB.interact.close()` hides it without selection.

## Aim targets

`QB.interact.addEntity(entity, options, distance?)` and
`QB.interact.addModel(model, options, distance?)` are qblib's facade over
qbtarget. They use the same `label`, `action`, `event`, `args`, and restriction
fields as zones, follow moving entities, and clean up automatically when the
invoking resource stops. Use `QB.interact.removeEntity(entity, id?)` or
`QB.interact.removeModel(model, id?)` for early teardown.

While the selector is visible, E or left-click confirms the highlighted option. Space and Enter do not confirm it. Up/Down or the mouse wheel changes the highlighted option, and Escape/Backspace/Pause closes the selector.

These inputs are held through one reference-counted `QB.controls` lease for the selector's lifetime. Closing, replacing, selecting from, or losing the owning resource releases that lease without disturbing another qblib system that disabled the same control.

## UI contract

The module sends `openInteract` with `{ { label = "..." } }`, `scroll` with `-1` or `1`, `select`, and `hideInteract`. The NUI POSTs the selected one-based number to `selectOption`; `closeInteract` simply hides it. No option actions, events, restrictions, or raw target data are sent to the browser.
