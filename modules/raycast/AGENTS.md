# raycast module guide

## Purpose
This module fires world-geometry raycasts and reports what they hit -- coordinates, struck entity, and surface normal -- either between two explicit points or from the gameplay camera outward.

## Public API
- `QB.raycast.fromCoords(startCoords, endCoords, flags, ignoreEntity)`
  - Thin wrapper around `StartShapeTestRay`/`GetShapeTestResult`.
  - Returns `hit, coords, entityHit, surfaceNormal`.
- `QB.raycast.fromCamera(maxDistance, flags, ignoreEntity)`
  - Builds a ray from `GetGameplayCamCoord`/`GetGameplayCamRot(2)` out to `maxDistance`, then delegates to `fromCoords`.
  - Same return shape as `fromCoords`.

## Implementation notes
- `flags` defaults to `-1` (test against everything) and `ignoreEntity` defaults to `PlayerPedId()` -- these were the zone creator's original hardcoded values, kept as defaults rather than required params so existing callers don't need to change, while still letting a caller (e.g. a targeting resource that wants to ignore vehicles) override either.
- `GetShapeTestResult` always returns `surfaceNormal`/`entityHit` regardless of flags; the previous zones-only version discarded both. They're now returned because the whole reason to promote this out of zones is that a target resource needs to know *what entity* the ray struck, not just where it landed.
- `entityHit` comes back as `0` (not `nil`) on a hit against bare world geometry -- only `hit` itself distinguishes a miss.
- `toVec3`/`rotationToDirection` are private copies of the same helpers in `modules/zones/client.lua`. They're duplicated rather than shared because Lua `local`s don't cross files and this repo has no shared-utils convention (see top-level `AGENTS.md`) -- every other client-only module (`stream`, `zones`) duplicates its own small helpers the same way.
- Client-only: raycasting is inherently local to the calling client's own camera/world view, so there's no `shared.lua`/`server.lua` here, same shape as `modules/stream`.

## Best practices
- Check `entity ~= 0` before treating a returned `entityHit` as a real entity handle.
- Pass an explicit `ignoreEntity` when raycasting from something other than the local player (e.g. a vehicle) so the ray doesn't hit its own source.
- Prefer `fromCoords` over `fromCamera` for anything that isn't literally "what is the player looking at."
