---
title: "Vehicle"
sidebar_position: 34
---


# Vehicle

## Shared

Provides a shared vehicle-plate normalizer. It trims and uppercases a plate, applies a whitespace policy, validates characters, and enforces a maximum length. Garage ownership and persistent vehicle rules belong to the resource that owns them.

Namespace: `Kora.vehicle` · Source: `modules/vehicle/shared.lua`

### normalizePlate options

All settings are optional and apply only when supplied. A `?` after a name means the option is optional.

| Option | Type | Description |
| --- | --- | --- |
| `maxLength?` | integer | Positive maximum output length. Defaults to 8. |
| `whitespace?` | 'collapse' \| 'remove' \| 'preserve' | Collapse runs to one internal space (default), remove all whitespace, or preserve internal whitespace. |
| `characters?` | 'alphanumeric' \| 'any' | Restrict to A–Z, digits, and spaces (default), or permit any characters. |

### Functions

Normalize an external plate string before using it as a lookup key.

#### `Kora.vehicle.normalizePlate(value, options?)`

Returns a canonical plate string or a stable reason when the input cannot be normalized.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | any | Candidate plate value; non-strings return an invalid_type reason. |
| `options?` | table | Optional maxLength, whitespace, and characters rules. |

**Returns**

- **plate** — uppercase normalized string on success.
- **nil, reason** — invalid_type, empty, too_long, or invalid_characters.

**Example**

```lua
local plate, reason = Kora.vehicle.normalizePlate('  ab 123  ')
if not plate then return print(reason) end
print(plate)
```

**Representative console output**

```text
Prints AB 123 using the default collapse-whitespace and alphanumeric rules.
```

## Client

Provides client helpers for vehicle identity, property snapshots, property application, and network control. Property changes to an existing networked vehicle require control. These helpers do not implement a garage, ownership, impound, or payment policy.

Namespace: `Kora.vehicle` · Source: `modules/vehicle/client.lua`

### Vehicle property fields

setProperties accepts a partial table. Only provided fields are changed. All numeric values must be finite and boolean state fields must be actual booleans. A `?` after a name means the option is optional.

#### Common scalar and color fields

| Option | Type | Description |
| --- | --- | --- |
| `plate / plateIndex?` | string / number | Plate text and plate style index. |
| `bodyHealth / engineHealth / tankHealth?` | number | Vehicle body, engine, and fuel-tank health. |
| `fuelLevel / dirtLevel / oilLevel?` | number | Fuel, dirt, and oil levels. |
| `color1 / color2?` | number \| RGB table | Primary and secondary palette index or custom RGB value. |
| `pearlescentColor / dashboardColor / wheelColor / interiorColor?` | number | Vehicle trim and interior color indices. |
| `wheels / wheelSize / wheelWidth / windowTint?` | number | Wheel type, size, width, and window tint. |
| `neonColor / tyreSmokeColor / xenonColor?` | RGB table \| number | Light/smoke color. RGB tables accept r/g/b, numeric arrays, or JSON numeric keys. |

#### Indexed state tables

| Option | Type | Description |
| --- | --- | --- |
| `extras?` | table&lt;boolean> | Extra IDs 0–20 mapped to enabled booleans. |
| `tireHealth / tireBurstState / tireBurstCompletely?` | table | Tyre IDs 0–5 with finite health or strict boolean burst state. |
| `windowStatus?` | table&lt;boolean> | Window indices 0–7 mapped to intact booleans. |
| `doorStatus?` | table&lt;boolean> | Door indices 0–5 mapped to damaged booleans. |
| `neonEnabled?` | table&lt;boolean> | Neon slots 1–4 mapped to enabled booleans. |

#### Mods and toggles

| Option | Type | Description |
| --- | --- | --- |
| `modSpoilers … modKit49?` | integer | Standard numeric mod slots, including engine, brakes, transmission, suspension, armor, bumpers, trim, and other supported mod categories. |
| `modTurbo / modSmokeEnabled / modXenon?` | boolean | Toggle mods enabled or disabled. |
| `modFrontWheels / modBackWheels?` | integer | Front and rear wheel mod indices. |
| `modCustomTiresF / modCustomTiresR?` | boolean | Whether front/rear wheel mods use custom tire variations. |
| `modLivery / liveryRoof?` | number | Vehicle and roof livery indices. |

### Property snapshots

getProperties returns a JSON-stable snapshot. Custom RGB colors are objects with r, g, and b fields. setProperties also accepts numeric arrays and decoded JSON objects with string keys "1", "2", and "3".

### Control and authorization

setProperties and delete need network control but do not authorize the gameplay action. The server/resource that owns a garage or vehicle must verify ownership and state before allowing a change.

### Functions

Inspect a vehicle, request control, delete it safely, or read/apply a QBCore-compatible properties table.

#### `Kora.vehicle.requestControl(entity, timeout?)`

Requests network control of an existing entity through Kora.entities.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `entity` | integer | Positive network entity handle. |
| `timeout?` | integer | Maximum wait in milliseconds; defaults to the entity-control helper’s configured/default timeout. |

**Returns**

- **controlled** — boolean.
- **reason** — error string when control was not obtained.

**Example**

```lua
local controlled, err = Kora.vehicle.requestControl(vehicle, 1500)
if not controlled then print(err) end
```

**Representative console output**

```text
Prints a reason if control could not be obtained in 1.5 seconds.
```

#### `Kora.vehicle.delete(vehicle, options?)`

Obtains control, marks the vehicle as a mission entity, and deletes it.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `vehicle` | integer | Positive vehicle handle that exists and is a vehicle. |
| `options?` | table | Optional timeout for control acquisition. |

**Returns**

- **deleted** — boolean.
- **reason** — failure detail when the vehicle is invalid, control fails, or deletion fails.

**Example**

```lua
local deleted, err = Kora.vehicle.delete(vehicle, { timeout = 1500 })
if not deleted then print(err) end
```

**Representative console output**

```text
Deletes the vehicle after control is acquired or prints a reason.
```

#### `Kora.vehicle.isDriver(vehicle)`

Checks whether the local player occupies the driver seat of a valid vehicle.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `vehicle` | integer | Vehicle entity handle. |

**Returns**

- **isDriver** — boolean; false for invalid handles.

**Example**

```lua
if Kora.vehicle.isDriver(vehicle) then print('You are driving') end
```

**Representative console output**

```text
Prints only when the local player is in the driver seat.
```

#### `Kora.vehicle.model(vehicle)`

Returns the model hash for a valid vehicle.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `vehicle` | integer | Vehicle entity handle. |

**Returns**

- **modelHash** — integer, or false for an invalid vehicle.

**Example**

```lua
local model = Kora.vehicle.model(vehicle)
```

**Representative console output**

```text
Returns the vehicle model hash or false.
```

#### `Kora.vehicle.plate(vehicle)`

Returns the trimmed number-plate text.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `vehicle` | integer | Vehicle entity handle. |

**Returns**

- **plate** — string, or false for invalid vehicle/data.

**Example**

```lua
print(Kora.vehicle.plate(vehicle))
```

**Representative console output**

```text
Prints the vehicle’s plate without surrounding whitespace.
```

#### `Kora.vehicle.label(vehicle)`

Returns the localized display label, falling back to the model display name when localization is unavailable.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `vehicle` | integer | Vehicle entity handle. |

**Returns**

- **label** — string, or false for invalid vehicle.

**Example**

```lua
print(Kora.vehicle.label(vehicle))
```

**Representative console output**

```text
Prints a localized vehicle name when available.
```

#### `Kora.vehicle.getProperties(vehicle)`

Reads a QBCore-compatible snapshot including health, fuel, colors, wheels, damage, lights, extras, mods, and liveries.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `vehicle` | integer | Valid vehicle handle. |

**Returns**

- **properties** — table snapshot.
- **false, error** — when the handle is invalid or not a vehicle.

**Example**

```lua
local props, err = Kora.vehicle.getProperties(vehicle)
if not props then return print(err) end
print(props.plate, props.engineHealth, props.fuelLevel)
```

**Representative console output**

```text
Prints plate, engine health, and fuel from the snapshot.
```

#### `Kora.vehicle.setProperties(vehicle, props, opts?)`

Validates a property table, obtains network control, then applies the supplied fields. Unspecified fields are left alone; explicit false and 0 are preserved.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `vehicle` | integer | Valid vehicle handle. |
| `props` | table | Partial QBCore-compatible vehicle properties. See groups above. |
| `opts?` | table | Optional timeout for network control; defaults to 1000 ms. |

**Returns**

- **success** — true when applied.
- **false, error** — when vehicle validation or control acquisition fails.

**Example**

```lua
local ok, err = Kora.vehicle.setProperties(vehicle, { fuelLevel = 75.0, engineHealth = 900.0 }, { timeout = 1500 })
if not ok then print(err) end
```

**Representative console output**

```text
Sets fuel and engine health after obtaining network control.
```

### Limits and related APIs

Vehicle handles must be positive finite integers. Inspection functions return false for invalid handles; delete validates and rejects. Indexed tables only accept documented ranges, and malformed values are rejected before control or native calls.

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/vehicle/docs.md` or `local/vehicle/docs.md`) that the reference above does not state.

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

### `Kora.vehicle.getProperties(vehicle)`

Returns a QBCore-compatible property snapshot, or `false, error` for an invalid
vehicle. It includes health/fuel, numeric or custom colors, wheel configuration,
tyre/window/door damage, neon/xenon/smoke settings, extras `0–20`, all standard
mod slots, toggle mods, and livery fields.

### `Kora.vehicle.setProperties(vehicle, properties, opts?)`

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
