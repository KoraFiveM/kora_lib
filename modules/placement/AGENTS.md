# placement module guide

## Purpose

This client-only module is a temporary transform capture tool. It validates a
model, creates one local preview, lets the player position it with a scripted
freecam, returns/copies its transform, and deletes the preview on every exit.

## Invariants

- Never leave the preview alive after confirm, cancel, error, owner stop, or
  qblib stop. `releaseStateResources` is the shared teardown path.
- Never create a networked entity. Spawn through `QB.entities.create` and keep
  its normal owner tracking intact until `QB.entities.remove` is called.
- Capture `GetInvokingResource()` before raycasting or streaming yields.
- Keep heading separate from Euler yaw: capture both from their native getters
  with entity rotation order `2`.
- HUD messages are capped by `Config.placement.hudUpdateInterval`; native
  movement remains per-frame and frame-time-scaled.
- The placement and zone creators are mutually exclusive. Keep both guards and
  `QB.placement.isActive()` in sync if lifecycle states change.
- The summary's Copy & Finish action must not settle on clipboard failure.
- Every teardown sends `placement:closeConfirm`; without that response an
  owner stop during the summary could leave NUI focus held until timeout.

## Tests

`test/smoke/placement.lua` mocks entity, camera, keybind, lifecycle, and NUI
behavior. Update it with every control or result-shape change. Rebuild `web/`
after changing the placement HUD, dialog, or message payloads.
