---
title: "Vehicle module"
sidebar_position: 34
---

# Vehicle module

Client-side vehicle helpers. Persistent garage, ownership, impound, and payment
rules remain in kora_core or the resource that owns them.

`Kora.vehicle.normalizePlate(value, options?)` is shared across client and server.
It trims and uppercases plates, collapses internal whitespace, validates
alphanumeric characters, and enforces an eight-character default maximum.
Use `whitespace = 'remove'`/`'preserve'`, `characters = 'any'`, or `maxLength`
only when an existing storage contract requires different behavior. Invalid
external values return `nil, reason`.

Every optional vehicle options argument must be a table when supplied. Invalid
options are rejected before kora_lib requests entity control or calls a vehicle
native. Vehicle handles must be positive finite integers; inspection helpers
return `false` for an invalid handle, while `delete` rejects one.

- `Kora.vehicle.requestControl(entity, timeout?)` requests network control.
- `Kora.vehicle.delete(vehicle, { timeout? })` obtains control and deletes it.
- `Kora.vehicle.isDriver(vehicle)` checks the local driver seat.
- `Kora.vehicle.model(vehicle)` returns its model hash or `false`.
- `Kora.vehicle.plate(vehicle)` returns a whitespace-trimmed plate or `false`.
- `Kora.vehicle.label(vehicle)` returns its localized label with display-name fallback.

## `Kora.vehicle.getProperties(vehicle)`

Returns a QBCore-compatible property snapshot, or `false, error` for an invalid
vehicle. It includes health/fuel, numeric or custom colors, wheel configuration,
tyre/window/door damage, neon/xenon/smoke settings, extras `0–20`, all standard
mod slots, toggle mods, and livery fields.

## `Kora.vehicle.setProperties(vehicle, properties, opts?)`

Obtains network control before applying any change (`opts.timeout`, default
1000ms), then applies the same QBCore-compatible schema. It returns
`true`, or `false, error` if the vehicle is invalid or control cannot be
obtained. Explicit `false` and `0` values are applied rather than mistaken for
missing fields.

RGB colors are returned as JSON-stable `{ r, g, b }` objects. The setter also
accepts numeric arrays and legacy JSON-decoded objects with `"1"`, `"2"`, and
`"3"` keys, so existing garage rows remain restorable.

All numeric values supplied to the setter, including RGB channels, interior
colour, and tyre health, must be finite. `plate`, when supplied, must be a
string. Invalid values are rejected before control is requested or a vehicle
native is called.

State fields are strict booleans: extras, tyre-burst state, window/door state,
neon lights, toggle mods, and custom-tire flags do not use Lua truthiness.
Malformed state values are rejected before control is requested.

Tyre-health, window-status, and door-status tables accept numeric or JSON
string indices only: tyres `0–5`, windows `0–7`, and doors `0–5`.
