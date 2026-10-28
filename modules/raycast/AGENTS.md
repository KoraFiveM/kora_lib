# raycast module guide

## Purpose
This module fires world-geometry raycasts and reports what they hit -- coordinates, struck entity, and surface normal -- either between two explicit points or from the gameplay camera outward.

## Public API
- `QB.raycast.fromCoords(startCoords, endCoords, flags, ignoreEntity)`
  - Starts an asynchronous `StartShapeTestRay`, waits for `GetShapeTestResult` to report completion, then returns the settled result.
  - Returns `hit, coords, entityHit, surfaceNormal`.
- `QB.raycast.fromCamera(maxDistance, flags, ignoreEntity)`
  - Builds a ray from `GetGameplayCamCoord`/`GetGameplayCamRot(2)` out to `maxDistance`, then delegates to `fromCoords`.
  - Same return shape as `fromCoords`.
- `QB.raycast.fromCam(cam, maxDistance, flags, ignoreEntity)`
  - Builds a ray from a given scripted camera handle's `GetCamCoord`/`GetCamRot(cam, 2)` out to `maxDistance`, then delegates to `fromCoords`.
  - Same return shape as `fromCoords`.
- `QB.raycast.getCoords(data?)`
  - Runs an interactive gameplay-camera coordinate picker. No options draws an
    orb; `{ type = "object", object = model }` creates a heading-only preview.
  - Returns rounded `{ coords, object }` data on E or `nil` on Backspace, and
    always removes its temporary UI, controls lease, and preview.
- `QB.raycast.start(startCoords, endCoords, flags, ignoreEntity)` / `QB.raycast.startFromCamera(maxDistance, flags, ignoreEntity)`
  - Fire the shape test and return its raw handle immediately, without settling it.
- `QB.raycast.await(rayHandle)`
  - Settles a started handle, yielding a frame at a time under the same one-second bound `fromCoords` uses. Returns immediately for a handle that has already settled.
- `QB.raycast.poll(rayHandle)`
  - Non-blocking read. Returns `settled, hit, coords, entityHit, surfaceNormal`; nothing after `settled` is meaningful until it is true.

## Implementation notes
- `flags` defaults to `-1` (test against everything) and `ignoreEntity` defaults to `PlayerPedId()` -- these were the zone creator's original hardcoded values, kept as defaults rather than required params so existing callers don't need to change, while still letting a caller (e.g. a targeting resource that wants to ignore vehicles) override either.
- `GetShapeTestResult` always returns `surfaceNormal`/`entityHit` regardless of flags; the previous zones-only version discarded both. They're now returned because the whole reason to promote this out of zones is that a target resource needs to know *what entity* the ray struck, not just where it landed.
- `fromCoords`/`fromCamera` are literally `start` + `await`, and `fromCam` is `start` + `await` off a scripted camera. The split exists because the engine settles shape tests **once per frame**: a caller that needs several rays describing the same instant (kora_target fires a broad `511` world mask and a narrow `26` entity mask every resolver tick) must start them all before awaiting any, or it pays one extra frame of latency AND one extra thread wake-up per ray for information the first frame already had. `poll` covers the other shape of that problem -- a caller with its own tick loop that would rather consume last tick's ray than park a frame inside kora_lib at all.
- `GetShapeTestResult` status `1` is pending. Its hit/entity output slots are not consumed until status `2`; doing so can leak an invalid entity handle into consumers such as kora_target. Polling is bounded to one second and yields once per pending frame.
- `entityHit` comes back as `0` (not `nil`) on a hit against bare world geometry -- only `hit` itself distinguishes a miss.
- `fromCam` shares `rotationToDirection`/`toVec3` with `fromCamera`; the only difference is it reads position/rotation from a caller-supplied scripted camera handle (`GetCamCoord`/`GetCamRot`) instead of the gameplay camera (`GetGameplayCamCoord`/`GetGameplayCamRot`).
- `toVec3`/`rotationToDirection` are private copies of the same helpers in `modules/zones/client.lua`. They're duplicated rather than shared because Lua `local`s don't cross files and this repo has no shared-utils convention (see top-level `AGENTS.md`) -- every other client-only module (`stream`, `zones`) duplicates its own small helpers the same way.
- Client-only: raycasting is inherently local to the calling client's own camera/world view, so there's no `shared.lua`/`server.lua` here, same shape as `modules/stream`.

## Best practices
- Check `entity ~= 0` before treating a returned `entityHit` as a real entity handle.
- Pass an explicit `ignoreEntity` when raycasting from something other than the local player (e.g. a vehicle) so the ray doesn't hit its own source.
- Prefer `fromCoords` over `fromCamera` for anything that isn't literally "what is the player looking at."
