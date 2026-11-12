---
title: "Interact"
sidebar_position: 12
---


# Interact

Shows a small game-input-driven option selector for nearby activities. It can create static circle and box zones or register live targets on entity handles and models. The selector is click-through and does not take NUI focus; the browser receives option labels while Lua keeps actions, events, and access checks.

Namespace: `Kora.interact` · Source: `modules/interact/client.lua`

## Interaction option fields

Each option requires a label and can run a local function or trigger an event. Use the same shape in selector and target APIs. A `?` after a name means the option is optional.

### One option definition

| Option | Type | Description |
| --- | --- | --- |
| `label` | string | Required non-empty text shown to the player. |
| `action?` | function | Function called when selected. For live targets, it receives the selected entity. |
| `event?` | string | Event name to trigger when selected. Local by default; use type = server for a server event. |
| `type?` | 'client' \| 'server' | Event destination. Use server only for a request that the server will validate. Defaults to local/client behavior. |
| `args?` | any | Value forwarded to the event. Treat client-supplied arguments as untrusted on the server. |
| `canInteract?` | function | Predicate checked before showing the option. It should return true only when this player can currently use it. |
| `job / gang?` | string \| string[] \| table | Optional job or gang restriction. A keyed map can require a minimum grade, for example &#123; police = 2 &#125;. |
| `citizenid?` | string \| string[] \| table | Optional allowed character ID or IDs. A keyed map may map IDs to true. |
| `item?` | string \| table | Optional required inventory item. The option stays hidden when the requirement is not met or its optional inventory dependency is unavailable. |
| `distance?` | number | For a live target option, optional positive finite maximum distance. |

## Static zones and live targets

addCircleZone, addBoxZone, addTargetEntity, and addTargetModel create static zones at the position observed during registration. addEntity and addModel register live aim targets that follow entities. Use the static form for fixed places and the live form for moving peds or vehicles.

## Input and UI behavior

While open, Up/Down or the mouse wheel changes the selected option; E or left-click confirms it; Escape, Backspace, or Pause closes the selector. The selector does not take NUI focus. Its controls use a Kora.controls lease that is released when the selector closes.

## Server events still need checks

An option displayed on the client is not proof of permission or proximity. If it triggers a server event, the receiving server handler must recheck the player, distance, permission, cooldown, inventory, and current game state before changing persistent data.

## Functions

Open and close a selector, create named zones, or register options against a moving entity or model.

### `Kora.interact.open(options)`

Opens the selector with the options that pass their restrictions. The module closes a selector already owned by the resource before opening another.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `options` | table[] | Non-empty array of interaction option definitions. See the option fields above. |

**Returns**

- **opened** — true when a selector opened; false when the feature is disabled or no option passes its restrictions.

**Example**

```lua
local opened = Kora.interact.open({
    { label = 'Check stock', action = function() print('Stock checked') end },
    { label = 'Close', event = 'myshop:client:close' },
})
if not opened then print('No available options') end
```

**Representative console output**

```text
The selector shows only options the player can currently use.
```

### `Kora.interact.close()`

Closes the active selector without choosing an option.

**Parameters**



**Returns**

- **closed** — true when a selector was closed; otherwise false.

**Example**

```lua
if Kora.interact.isActive() then Kora.interact.close() end
```

**Representative console output**

```text
The selector hides without calling an option.
```

### `Kora.interact.isActive()`

Checks whether an interaction selector is currently open.

**Parameters**



**Returns**

- **active** — boolean.

**Example**

```lua
if Kora.interact.isActive() then print('Interaction menu is open') end
```

**Representative console output**

```text
Prints while the selector is visible.
```

### `Kora.interact.addCircleZone(name, coords, radius?, targetOptions, debug?)`

Creates a named circular interaction zone at a fixed world position. The returned handle can be passed to Kora.zones APIs that accept zone handles.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Non-empty unique zone name. A duplicate created by the same resource replaces its earlier zone; another resource’s name is refused. |
| `coords` | vector3 | Finite center position. |
| `radius?` | number | Positive finite radius. Defaults to 5.0 only when omitted. |
| `targetOptions` | table | &#123; options = &#123; ... &#125; &#125; or a direct array of option definitions. |
| `debug?` | boolean | Optional zone debug drawing setting. |

**Returns**

- **zone** — zone handle, or nil if the interaction feature is disabled or creation is refused.

**Example**

```lua
local zone = Kora.interact.addCircleZone(
    'shop-locker', vector3(100.0, 200.0, 30.0), 2.0,
    { options = { { label = 'Open locker', event = 'myshop:client:openLocker' } } },
    false
)
```

**Representative console output**

```text
Creates a two-metre circle whose visible option triggers the local event when selected.
```

### `Kora.interact.addBoxZone(name, coords, size, targetOptions, debug?)`

Creates a named box-shaped interaction zone at a fixed position. It does not follow an entity that moves afterward.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Non-empty unique zone name. |
| `coords` | vector3 | Finite center position. |
| `size` | vector3 | Positive finite width, length, and height dimensions. |
| `targetOptions` | table | &#123; options = &#123; ... &#125; &#125; or a direct option array. |
| `debug?` | boolean | Optional zone debug drawing setting. |

**Returns**

- **zone** — zone handle, or nil when disabled or refused.

**Example**

```lua
Kora.interact.addBoxZone(
    'repair-bench', vector3(110.0, 205.0, 30.0), vector3(2.0, 1.0, 1.5),
    { options = { { label = 'Repair', event = 'garage:client:repair' } } },
    false
)
```

**Representative console output**

```text
Creates a fixed box around the repair bench.
```

### `Kora.interact.removeZone(name)`

Removes a named zone only when the calling resource owns it.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Name used when creating the zone. |

**Returns**

- **removed** — true when the owned zone was removed; false if it did not exist or belongs to another resource.

**Example**

```lua
if Kora.interact.removeZone('repair-bench') then print('Repair zone removed') end
```

**Representative console output**

```text
Prints only if this resource owned and removed that zone.
```

### `Kora.interact.addTargetModel(models, size, targetOptions, debug?)`

Creates static zones around objects whose model matches. These zones use the matched objects’ current positions; they do not follow later movement. Use addModel for live aim-target behavior.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `models` | string \| integer \| array | One model name/hash or a list of model names/hashes. |
| `size` | vector3 | Positive finite dimensions for each generated zone. |
| `targetOptions` | table | Option definitions, or &#123; options = &#123; ... &#125; &#125;. |
| `debug?` | boolean | Optional zone debug drawing setting. |

**Returns**

- **zones** — array of created zone handles; empty when disabled.

**Example**

```lua
local zones = Kora.interact.addTargetModel(
    'prop_atm_01', vector3(1.5, 1.5, 2.0),
    { options = { { label = 'Use ATM', event = 'banking:client:open' } } },
    false
)
```

**Representative console output**

```text
Creates a static interaction zone around each matching ATM model.
```

### `Kora.interact.addTargetEntity(entity, size, targetOptions, debug?)`

Creates a static interaction zone around one entity at its current position. It does not move with the entity after creation.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `entity` | integer | Existing entity handle. |
| `size` | vector3 | Positive finite zone dimensions. |
| `targetOptions` | table | Option definitions, or &#123; options = &#123; ... &#125; &#125;. |
| `debug?` | boolean | Optional zone debug drawing setting. |

**Returns**

- **zone** — created zone handle, or nil when unavailable.

**Example**

```lua
local zone = Kora.interact.addTargetEntity(
    registerPed, vector3(1.2, 1.2, 2.0),
    { options = { { label = 'Talk', event = 'mission:client:talk' } } },
    false
)
```

**Representative console output**

```text
Creates a static zone around the entity’s current location.
```

### `Kora.interact.addEntity(entity, options, distance?)`

Registers a live aim target on an entity. Unlike a static zone, this target follows the entity. Its options are filtered and dispatched by kora_target.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `entity` | integer | Existing entity handle. |
| `options` | table[] | Non-empty array of option definitions. |
| `distance?` | number | Optional positive finite interaction distance. |

**Returns**

- **id** — registration ID used for later removal.

**Example**

```lua
local targetId = Kora.interact.addEntity(registerPed, {
    { label = 'Talk', action = function(entity) print('Talking to', entity) end },
}, 2.0)
```

**Representative console output**

```text
The target follows registerPed and offers Talk within two metres.
```

### `Kora.interact.removeEntity(entity, id?)`

Removes this resource’s aim-target registration for an entity. Omitting id removes all matching registrations owned by this resource.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `entity` | integer | Entity handle used during registration. |
| `id?` | integer | Optional registration ID returned by addEntity. |

**Returns**

- **removed** — boolean.

**Example**

```lua
Kora.interact.removeEntity(registerPed, targetId)
```

**Representative console output**

```text
The selected registration is removed and will no longer appear while aiming at the entity.
```

### `Kora.interact.addModel(model, options, distance?)`

Registers live aim-target options for all entities of a model. This is the moving-target alternative to addTargetModel.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `model` | string \| integer | Model name or hash. |
| `options` | table[] | Non-empty array of option definitions. |
| `distance?` | number | Optional positive finite target distance. |

**Returns**

- **id** — registration ID used for later removal.

**Example**

```lua
local targetId = Kora.interact.addModel('prop_atm_01', {
    { label = 'Use ATM', event = 'banking:client:open' },
}, 2.0)
```

**Representative console output**

```text
Matching ATM entities offer the option while the player aims within range.
```

### `Kora.interact.removeModel(model, id?)`

Removes this resource’s target registration for a model. Omitting id removes every registration for that model owned by this resource.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `model` | string \| integer | Model name or hash used during registration. |
| `id?` | integer | Optional registration ID returned by addModel. |

**Returns**

- **removed** — boolean.

**Example**

```lua
Kora.interact.removeModel('prop_atm_01', targetId)
```

**Representative console output**

```text
The registered ATM target option is removed.
```

## Limits and related APIs

Optional job, gang, character, and item filters depend on their corresponding framework or inventory data. Restrictions remain hidden if an optional dependency is unavailable. A resource can remove only its own zone and target registrations.

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/interact/docs.md` or `local/interact/docs.md`) that the reference above does not state.

`Kora.interact` provides a compact, game-input-driven option selector for kora_lib zones. It is entirely client-side, remains click-through, and never grants NUI focus.

### Zone API

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

### Options

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

### Aim targets

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

### UI contract

The module sends `openInteract` with `{ { label = "..." } }`, `scroll` with `-1` or `1`, `select`, and `hideInteract`. The NUI POSTs the selected one-based number to `selectOption`; `closeInteract` simply hides it. No option actions, events, restrictions, or raw target data are sent to the browser.
