# Vehicle module

Client-side vehicle helpers. Persistent garage, ownership, impound, and payment
rules remain in qbcore or the resource that owns them.

`QB.vehicle.normalizePlate(value, options?)` is shared across client and server.
It trims and uppercases plates, collapses internal whitespace, validates
alphanumeric characters, and enforces an eight-character default maximum.
Use `whitespace = 'remove'`/`'preserve'`, `characters = 'any'`, or `maxLength`
only when an existing storage contract requires different behavior. Invalid
external values return `nil, reason`.

- `QB.vehicle.requestControl(entity, timeout?)` requests network control.
- `QB.vehicle.delete(vehicle, { timeout? })` obtains control and deletes it.
- `QB.vehicle.isDriver(vehicle)` checks the local driver seat.
- `QB.vehicle.model(vehicle)` returns its model hash or `false`.
- `QB.vehicle.plate(vehicle)` returns a whitespace-trimmed plate or `false`.
- `QB.vehicle.label(vehicle)` returns its localized label with display-name fallback.

## `QB.vehicle.getProperties(vehicle)`

Returns a QBCore-compatible property snapshot, or `false, error` for an invalid
vehicle. It includes health/fuel, numeric or custom colors, wheel configuration,
tyre/window/door damage, neon/xenon/smoke settings, extras `0–20`, all standard
mod slots, toggle mods, and livery fields.

## `QB.vehicle.setProperties(vehicle, properties, opts?)`

Obtains network control before applying any change (`opts.timeout`, default
1000ms), then applies the same QBCore-compatible schema. It returns
`true`, or `false, error` if the vehicle is invalid or control cannot be
obtained. Explicit `false` and `0` values are applied rather than mistaken for
missing fields.

RGB colors are returned as JSON-stable `{ r, g, b }` objects. The setter also
accepts numeric arrays and legacy JSON-decoded objects with `"1"`, `"2"`, and
`"3"` keys, so existing garage rows remain restorable.
