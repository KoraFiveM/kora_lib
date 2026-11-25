# Bridge

`Kora.bridge` exposes provider functions that are assigned directly by the selected module. Provider-specific export calls stay in the provider file, so consumers call one stable Kora function.

`Config.bridge` in `config.lua` selects a provider folder per area with `'auto'` or a provider name. `bridge_init.lua` chooses a started provider and loads only its optional `shared.lua` plus the current realm file. The functions those files assign to `Kora.bridge` become the public API directly. If a provider starts or stops later, the loader refreshes that area's functions. Auto mode prefers started Kora providers, then sorts other providers by name. A forced name loads only that provider.

```lua
Config.bridge = {
    vehiclekeys = 'auto',
    banking = 'kora_banking',
}

-- Server
local ok = Kora.bridge.giveKeys(source, plate)
local balance = Kora.bridge.getSocietyAccountBalance('police')

-- Client
local promptId = Kora.bridge.showHelpText('Open the door', { key = 'E' })
```

## Provider areas and contracts

Provider functions are called directly, so their return values and errors pass through unchanged. Each provider owns argument validation and any fallback behavior it needs. A provider must supply every function listed for its area and realm.

| Area | Realm | Public functions |
| --- | --- | --- | --- |
| `banking` | server | `addSocietyMoney(name, amount, reason?)`, `removeSocietyMoney(name, amount, reason?)`, `getSocietyAccountBalance(name)`, `executeSocietyTransaction(key, request)`, `createSocietyBankStatement(playerId, account, amount, reason, kind, accountType?)` |
| `bossmenu` | client/server | `openBossMenu(roleType?)`, `openApplication(jobName, roleType?)`, `addBossMenuItem(data, id?)`, `removeBossMenuItem(id)`, `addGangMenuItem(data, id?)`, `removeGangMenuItem(id)`, `addBusinessMoney(jobName, amount, reason?)`, `removeBusinessMoney(jobName, amount, reason?)`, `getBusinessBalance(jobName)`, `bossmenuAddMoney(jobName, amount)`, `bossmenuRemoveMoney(jobName, amount)`, `addGangMoney(gangName, amount)`, `removeGangMoney(gangName, amount)`, `getGangBalance(gangName)` |
| `clothing` | client/server | `openWardrobe()`, `openClothingRoom(options?)`, `applyAppearanceToPed(ped, model, skin)`, `applyStarterAppearance()`, `reloadSkin()`, `openAdminSession(targetSrc, service)` |
| `dispatch` | server | `createCall(payload)`, `updateCall(id, patch)`, `closeCall(id, reason?)`, `getCalls(filter?)`, `registerPlayerAlert(key, definition)`, `createPlayerCall(src, key)` |
| `doorlock` | client/server | `getClosestDoor()`, `getDoorState(id)`, `pickClosestDoor()`, `setDoorState(id, state)`, `createDoor(raw)`, `registerDoorPolicy(id, callback)` |
| `fuel` | client | `getFuel(vehicle)`, `setFuel(vehicle, level)`, `isElectricVehicle(vehicle)` |
| `helptext` | client | `showHelpText(text, options?)`, `updateHelpText(id, text, options?)`, `hideHelpText(id)` |
| `notify` | client | `sendNotification(payload)` |
| `vehiclekeys` | server | `giveKeys(src, plate, allowWhenDisabled?)`, `removeKeys(src, plate)`, `hasKeys(src, plate)` |

The current vehicle key resource exposes server exports only, so this version does not add client key functions. `sendNotification` delegates to `Kora.notify.send`, retaining `Config.third_party_notify` behavior. `helptext` delegates to `Kora.textui`.

The `bossmenuAddMoney` and `bossmenuRemoveMoney` names keep legacy boss-menu operations distinct from the society banking methods.

## Registering and selecting providers

Provider modules live under `modules/bridge/modules/<area>/<provider_name>/`, with optional `shared.lua` and realm-specific `client.lua` and `server.lua` files. Each file assigns methods directly to `Kora.bridge`; the loader validates the required current-realm methods before publishing the assignments. Adapter Lua is shipped with the resource, while `bridge_init.lua` executes only the selected provider files. Add a provider-to-resource mapping to `providerCatalog` in `bridge_init.lua`; this catalog tells auto mode which resources to check. `Kora.bridge.getProvider(area)` returns the selected provider folder name or `nil`.

`'auto'` considers cataloged modules whose resource state is `'started'`. It prefers names beginning with `kora_`, then sorts remaining provider names alphabetically. A forced provider name never falls back to another adapter. Start and stop events invalidate the cached resource state and area selection.

## Writing a bridge adapter

Create `modules/bridge/modules/<area>/<provider_name>/` and add the needed `shared.lua`, `client.lua`, and `server.lua` files. Each file assigns its functions directly to `Kora.bridge` (for example, `function Kora.bridge.giveKeys(...) ... end`); the loader stages those assignments, merges shared and realm functions, validates the required methods, then publishes them on `Kora.bridge`. Verify the third-party export name, arguments, and return values from that resource's source or official documentation; do not infer them from a familiar resource name.

The following vehicle-key adapter is a **template only**. The export name is a placeholder and must be replaced with a verified call before submission; it is not shipped as a real provider.

```lua
-- modules/bridge/modules/vehiclekeys/example_resource/server.lua

function Kora.bridge.giveKeys(src, plate, allowWhenDisabled)
    -- Replace with the verified server export for this resource.
    return exports.example_resource:GiveKeys(src, plate, allowWhenDisabled)
end

function Kora.bridge.removeKeys(src, plate)
    -- Replace with the verified server export for this resource.
    return exports.example_resource:RemoveKeys(src, plate)
end

function Kora.bridge.hasKeys(src, plate)
    -- Replace with the verified server export for this resource.
    return exports.example_resource:HasKeys(src, plate)
end
```

### Provider adapter PR checklist

- Confirm each adapter method against the provider's source or official docs and preserve its actual argument and return behavior.
- Put methods in the matching realm file and provide every required function for that area and realm.
- Add a smoke test for provider selection and the adapter mapping where practical.
- Add the adapter folder and provider-to-resource mapping in `providerCatalog`; make the config value match the folder name.
- Keep exports in the matching realm file; do not add runtime export hijacks or consumer edits.
- Document any provider API divergence.

## Failure behavior

If a provider is missing or fails validation, its functions are not loaded. Provider function errors pass through directly to the caller. Start the configured provider resource before kora_lib, or let the resource start event trigger a reload.

The bridge does not migrate consumer resources. When migrating, replace their direct provider export calls with the corresponding `Kora.bridge` method in a separate change.
