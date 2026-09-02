# cache module guide

## Purpose
A cheap, always-fresh cache of frequently-needed local-player state (`playerId`, `serverId`, `ped`, `coords`, `vehicle`, `seat`, `enteringVehicle`, `enteringSeat`, `weapon`, `health`, `isDead`, `armour`, `stamina`) so callers don't hit natives like `PlayerPedId()`/`GetVehiclePedIsIn()` repeatedly, plus a general `get`/`set`/`onChange` key-value store other modules or resources can piggyback on for their own local state.

## Public API
- `QB.cache.get(key)` — Returns the cached value for `key`, or `nil` if never set.
- `QB.cache.set(key, value)` — Sets a value directly, firing `onChange` handlers for `key` if it actually changed. Not just for the built-in keys — any resource can cache its own local state through this. Rejects (logs and ignores) writes to any reserved built-in key.
- `QB.cache.onChange(key, handler)` — `handler(newValue, oldValue)` runs whenever `key`'s value changes. Multiple handlers per key are fine. Swept automatically when the registering resource stops.
- `QB.cache.offChange(key)` — Removes every handler the *calling resource* registered for `key` (per-resource, not per-function — handler identity doesn't survive the exports boundary).
- `QB.cache.playerId()` / `QB.cache.serverId()` — `PlayerId()` / `GetPlayerServerId(PlayerId())`.
- `QB.cache.ped()` — `PlayerPedId()`, refreshed every tick (survives death/respawn without a stale read).
- `QB.cache.coords()` — Local-player coordinates from the same shared tick. Use it for interval/event work; use a live native read for frame-critical movement or aiming.
- `QB.cache.vehicle()` — Current vehicle, or `false` if on foot.
- `QB.cache.seat()` — Current seat (`-1` driver, `0+` passenger), or `false` if not in a vehicle.
- `QB.cache.enteringVehicle()` / `QB.cache.enteringSeat()` — Vehicle/seat currently being entered, or `false`; enables edge-triggered legacy vehicle lifecycle bridging without a separate poll.
- `QB.cache.weapon()` — Currently selected weapon hash. Always a hash — `GetSelectedPedWeapon` reports `WEAPON_UNARMED`'s hash when holding nothing, never a false/nil sentinel.
- `QB.cache.health()` — `GetEntityHealth(ped)`. Note GTA's death floor is commonly 100, not 0.
- `QB.cache.isDead()` — `IsPedFatallyInjured(ped)`. Subscribe to `onChange('isDead', ...)` for the alive-to-dead edge; do not infer death from health.
- `QB.cache.armour()` — `GetPedArmour(ped)`. `0` when unequipped.

## Implementation notes
- **File layout**: client-only, same reasoning as `modules/zones`/`modules/stream`/`modules/nui` — this is 100% local-player state, nothing to share with the server.
- **`get`/`set`/`onChange` are the real primitive; the named getters are thin wrappers over `get`**. `set` is exported through the same `QB.<module>.<fn>` -> `exports.qblib:cache_set` path as everything else, and is deliberately not restricted to the built-in keys — any module or consumer resource can store its own value there and get change notifications for free, rather than needing its own cache/event machinery.
- **Change detection is a plain `==` check** (`setValue`, a local not exposed as `QB.cache.*`) — `cache[key]` is only overwritten, and `onChange` handlers only run, when the new value actually differs from the old one. This is what keeps a 0ms per-tick refresh loop from spamming handlers every single frame just because `vehicle`/`weapon`/etc. happened to get re-read with the same value.
- **`playerId`/`serverId` are session constants**: resolve them outside `refresh()` so the shared tick does not repeatedly call their natives. If an early resource start returns server id `-1`, a short-lived startup worker replaces it once networking supplies a valid id. `health`/`isDead`/`armour`/`coords` are read from the same `ped` local `refresh()` already fetches for the `ped` key, so no extra ped lookup is needed to obtain them.
- **`QB.cache.set` hard-rejects the thirteen built-in keys** (`RESERVED_KEYS`, top of the file) rather than merely letting the next refresh tick overwrite a bogus value back — a resource must never observe even a transient poisoned value. A rejected write is logged and otherwise silently ignored; it does not raise a Lua error, since a misbehaving caller shouldn't be able to interrupt its own script just by touching a reserved key.
- **`onChange` handlers are owner-tracked and swept via `QB.resources.registry`** (`local/resources`) rather than a hand-rolled sweep. A cache listener isn't a single owned handle like an entity/zone/blip — one key can have several listeners from several resources — so each `onChange` registration gets its own synthetic incrementing id to track, with a `listenersById[id] -> {key, entry}` side table letting the registry's `onDispose(id)` (and `offChange`) find and remove exactly one listener entry without scanning every key. `offChange(key)` removes by calling-resource+key rather than by handler reference, because function identity doesn't survive the exports boundary.
- **No native answers "what seat am I in"**: `computeSeat` first validates the cached seat with one `GetPedInVehicleSeat` call. Only when that slot no longer contains the ped does it scan every seat index (`-1` through `GetVehicleMaxNumberOfPassengers(vehicle) - 1`), rather than assuming a fixed seat count.
- **Refresh runs unconditionally from module load** (`Config.cache.tickInterval`, 200ms by default), unlike `modules/zones`' lazily-started threads — zones' zone-tick thread is opt-in (most resources never create a zone), but `playerId`/`ped`/`vehicle` etc. are baseline state practically every consumer resource wants immediately, so there's no "only start when needed" case worth optimizing for here.
- **An erroring `onChange` handler is logged and skipped**, same `pcall`-and-continue pattern as `modules/zones`' zone callbacks — one resource's buggy handler can't break refresh for anyone else's.

## Best practices
- Prefer `QB.cache.ped()`/`vehicle()`/etc. over calling `PlayerPedId()`/`GetVehiclePedIsIn()` yourself in any per-tick/per-frame code — that's the whole point of this module.
- Keep `onChange` handlers cheap; they run inline (synchronously) from the per-tick refresh thread for ped/vehicle/seat/enteringVehicle/weapon/health/isDead/armour/stamina. `stamina` in particular fires on most ticks during a sprint.
- Namespace custom `QB.cache.set` keys (e.g. `"myresource:something"`) to avoid colliding with another resource's own cached values or a future built-in key.
- Don't try to write `playerId`/`serverId`/`ped`/`vehicle`/`seat`/`enteringVehicle`/`enteringSeat`/`weapon`/`health`/`isDead`/`armour`/`stamina` via `QB.cache.set` — it's rejected. Read-only for everyone except this module's own `refresh()`.
