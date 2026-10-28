# drawing module guide

## Purpose
World-space visuals for client-side rendering, starting with 3D text. Added specifically because a crosshair-based targeting system needs to show an interaction prompt ("[E] Open") near whatever the player is aiming at, and nothing in kora_lib rendered anything in world space.

## Why a new module rather than folding this into an existing one
Nothing else in kora_lib draws to the screen. `modules/zones`' debug renderer (`drawDebugBox`/`drawDebugSphere`/`drawDebugPoly`) draws wireframes for its own zone shapes specifically and isn't a general-purpose primitive; text rendering is an unrelated concern (no shape, no containment, no ownership) that belongs on its own.

## Implementation notes
- `toVec3`/`withinDistance` are private copies of the same small helpers duplicated across `modules/raycast`, `modules/world`, and `modules/zones` -- per the top-level `AGENTS.md`, Lua `local`s don't cross files and this repo has no shared-utils convention, so every client-only module keeps its own copies. Squared-component culling avoids a square root in this per-frame path.
- The distance check runs against `GetEntityCoords(PlayerPedId())` computed fresh every call, before touching any `SetText*`/`AddTextComponentString`/`SetDrawOrigin` native -- culling has to happen first, not as an early-return after the natives already ran, or the whole point of `maxDistance` (skip the cost, not just the visual) is lost.
- Resolve and validate all text options before culling. A malformed call must fail before any drawing native runs, whether or not its position is currently visible.
- `SetTextCentre(true)` is always applied (not configurable) -- an interaction prompt anchored by `SetDrawOrigin` reads correctly centered on its anchor point; a left-aligned prompt would visually drift off whatever it's labeling.
- Nothing here is a persistent registration or gets tracked in a `QB.resources.registry` -- there's nothing to clean up, since a call that stops happening simply stops drawing on the next frame. This is a deliberate contract difference from `modules/zones`/`modules/entities`/`modules/blips`, which all own state until explicitly removed or their resource stops.
- Client-only, no `shared.lua`/`server.lua` -- drawing only makes sense against the calling client's own screen, same shape as `modules/raycast`/`modules/stream`/`modules/world`.

## Testing
`test/smoke/drawing.lua` mocks every text/draw-origin native as a recording spy (there's nothing to assert visually, only call sequence/args) plus `GetEntityCoords`/`PlayerPedId`. Covers: beyond `maxDistance` -> zero native calls recorded; within range -> the expected native sequence fires with the right text; per-call option overrides (`font`/`scale`/`color`/`outline`) reach the right native arguments; `Config.drawing.text3d` defaults are used when `options` is omitted or partial.
