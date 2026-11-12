---
title: "Interact module"
sidebar_position: 12
---

# Interact module

`Kora.interact` provides a compact, game-input-driven option selector for kora_lib zones. It is entirely client-side, remains click-through, and never grants NUI focus.

## Zone API

The zone helpers return normal `Kora.zones` handles. Zone names are unique within
this module; the creating resource can replace its own duplicate, while another
resource's duplicate is refused.

```lua
Kora.interact.addCircleZone("locker", vector3(100.0, 200.0, 30.0), 2.0, {
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

- `Kora.interact.addCircleZone(name, coords, radius, targetOptions, debug?)`
- `Kora.interact.addBoxZone(name, coords, size, targetOptions, debug?)`
- `Kora.interact.addTargetEntity(entity, size, targetOptions, debug?)`
- `Kora.interact.addTargetModel(models, size, targetOptions, debug?)`

`size` is a vector-like `{x, y, z}` table. The target helpers create static
zones around the current entity/model positions. They do not follow moving
entities; use the aim-target facade below when movement tracking is required.
Zone `targetOptions` use qb-target's `{ options = { ... } }` shape; a direct
option array remains accepted for existing kora_lib callers.
Zone coordinates must be finite; circle radii and box dimensions must be
positive finite numbers. Invalid replacement geometry is rejected before an
existing zone of the same name is removed. `addCircleZone` defaults its radius
to `5.0` only when the argument is omitted; explicit invalid values reject.
`Kora.interact.removeZone(name)` returns `true` only when the calling resource
owns a named zone with that name. Named zones are also removed automatically
when their invoking resource stops.

`Kora.interact.open(options)` opens the selector without a zone.
`Kora.interact.close()` closes it, and `Kora.interact.isActive()` reports whether a
selector is currently open.

## Options

Each option needs a non-empty `label`. On selection it calls `action()`, or triggers `event` locally by default / on the server when `type = "server"`. `args` is forwarded to the action event.

`canInteract()`, `job`, `gang`, `citizenid`, and `item` are evaluated before the selector opens. Restricted options remain hidden if their optional qb-core or qb-inventory dependency is unavailable.
`job` and `gang` accept a name, name array, or keyed minimum-grade map such as
`{ police = 2 }`; `citizenid` also accepts a keyed boolean map such as
`{ ['CID-1'] = true }`. Unknown grades fail closed.
Within one selector opening, repeated `item` requirements share one inventory
check; live aim targets still check availability each time kora_target evaluates
them.

An option with `type = "server"` only sends a client request. Treat its
arguments, the displayed option, and the player's apparent zone position as
untrusted on the server: validate permission, distance, cooldown, and current
state again in the event handler before making a persistent change.

## Aim targets

`Kora.interact.addEntity(entity, options, distance?)` and
`Kora.interact.addModel(model, options, distance?)` are kora_lib's facade over
kora_target. They use the same `label`, `action`, `event`, `args`, and restriction
fields as zones, follow moving entities, and clean up automatically when the
invoking resource stops. Use `Kora.interact.removeEntity(entity, id?)` or
`Kora.interact.removeModel(model, id?)` for early teardown; they remove only
registrations owned by the calling resource. Manual teardown also clears the
ownership record so resource-stop cleanup never removes it twice.
When supplied, `distance` must be a positive finite number.
An individual aim-target option may also set `distance`; it follows the same
positive finite constraint.

While the selector is visible, E or left-click confirms the highlighted option. Space and Enter do not confirm it. Up/Down or the mouse wheel changes the highlighted option, and Escape/Backspace/Pause closes the selector.

These inputs are held through one reference-counted `Kora.controls` lease for the selector's lifetime. Closing, replacing, selecting from, or losing the owning resource releases that lease without disturbing another kora_lib system that disabled the same control.

## UI contract

The module sends `openInteract` with `{ { label = "..." } }`, `scroll` with `-1` or `1`, `select`, and `hideInteract`. The NUI POSTs the selected one-based number to `selectOption`; `closeInteract` simply hides it. No option actions, events, restrictions, or raw target data are sent to the browser.
