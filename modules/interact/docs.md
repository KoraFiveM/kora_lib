# Interact module

`QB.interact` provides a compact, keyboard/gamepad-driven option selector for qblib zones. It is entirely client-side, remains click-through, and never grants NUI focus.

## Zone API

`addCircleZone` and `addBoxZone` accept qb-target-style option arguments and return the normal `QB.zones` handle. Zone names are unique within this module; adding a duplicate replaces the old zone.

```lua
QB.interact.addCircleZone("locker", vector3(100.0, 200.0, 30.0), 2.0, {
    debugPoly = false,
}, {
    options = {
        {
            label = "Open locker",
            event = "my-resource:client:openLocker",
            args = { "police" },
        },
    },
})
```

`addBoxZone(name, coords, length, width, zoneOptions, targetOptions)` accepts qb-target-compatible `heading`, `minZ`, `maxZ`, and `debugPoly` fields. `removeZone(name)` returns `true` only when a named zone existed.

`addTargetEntity(entity, targetOptions)` and `addTargetModel(models, targetOptions)` create static zones at currently streamed entities/objects. They do not track moving entities; recreate the target zone if the entity moves.

## Options

Each option needs a non-empty `label`. On selection it calls `action()`, or triggers `event` locally by default / on the server when `type = "server"`. `args` is forwarded to the action event.

`canInteract()`, `job`, `gang`, `citizenid`, and `item` are evaluated before the selector opens. Restricted options remain hidden if their optional qb-core or qb-inventory dependency is unavailable.

`QB.interact.open(options)` opens the same selector without a zone and returns `true` only if at least one option is currently available. `QB.interact.close()` hides it without selection.

While the selector is visible, E confirms the highlighted option. Space and Enter do not confirm it. Up/Down changes the highlighted option, and Escape/Backspace/Pause closes the selector.

## UI contract

The module sends `openInteract` with `{ { label = "..." } }`, `scroll` with `-1` or `1`, `select`, and `hideInteract`. The NUI POSTs the selected one-based number to `selectOption`; `closeInteract` simply hides it. No option actions, events, restrictions, or raw target data are sent to the browser.
