# distancecheck agent guide

## Purpose
`QB.distance.*` — small, allocation-light radius checks used all over gameplay
code (is the player near this prop / ped / coord?). Deliberately trivial and
deterministic, per the library's "keep utilities small and deterministic" rule.

## Realm split
Client and server both define `QB.distance.*` with DIFFERENT signatures:
- client measures from the local player via `QB.cache.get('coords')` (the cache
  refreshes `coords` every tick, so this is a plain table read, no native call);
- server takes `src` first and reads `GetEntityCoords(GetPlayerPed(src))`, which
  needs OneSync for a valid position.
`coords(a, b)` is the one function identical on both realms (pure point-to-point).

Because the same `QB.distance.<fn>` names exist in both realms, the smoke test
captures the client functions before dofile-ing the server file (the standard
same-name-across-realms workaround — see the top-level AGENTS.md).

## Notes
- Squared component distance avoids temporary vectors and square roots on this
  hot path while preserving Euclidean-radius results.
- Arguments are asserted early (missing, partial, or non-finite coords raise) — programmer-error
  contract, not a runtime `(value, err)` return, because a bad coord table is a
  caller bug, not a recoverable condition.
- No config: the only tunable is the per-call `distance`, defaulting to 5.0.
