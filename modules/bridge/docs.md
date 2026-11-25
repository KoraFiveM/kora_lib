# Bridge

`Kora.bridge` is a provider registry for APIs that may be supplied by different resources. It keeps provider-specific export calls inside kora_lib so consumers can call one stable Kora function.

The registry is selected per area. `Config.bridge` in `config.lua` accepts `'auto'` or a provider module name for each area. `bridge_init.lua` selects a started module during initialization, then loads only its `shared.lua` and current realm file. If the configured provider starts later or the live setting changes, it loads the newly selected module on the next bridge call. Auto mode uses a started Kora provider first, then the first started catalog provider by name. A forced name loads only that adapter module. Provider state is cached and invalidated when the resource starts or stops.

```lua
Config.bridge = {
    vehiclekeys = 'auto',
    banking = 'kora_banking',
}

-- Server
local ok = Kora.bridge.giveKeys(source, plate)
local balance = Kora.bridge.getAccountBalance('police')

-- Client
local promptId = Kora.bridge.showHelpText('Open the door', { key = 'E' })
```

## Provider areas and contracts

All exported return values from a provider are passed back to the caller. If no provider is available or a provider call errors, the bridge logs a stable Kora logging event and returns the documented fallback. Invalid public arguments raise an assertion before provider dispatch.

| Area | Realm | Public functions | Unavailable fallback |
| --- | --- | --- | --- |
| `banking` | server | `addAccountMoney(name, amount, reason?)`, `removeAccountMoney(name, amount, reason?)`, `getAccountBalance(name)`, `executeBankTransaction(key, request)`, `createBankStatement(playerId, account, amount, reason, kind, accountType?)` | `false`, `0`, or `nil, 'unavailable'` by function |
| `bossmenu` | client/server | `openBossMenu(roleType?)`, `openApplication(jobName, roleType?)`, `addBossMenuItem(data, id?)`, `removeBossMenuItem(id)`, `addGangMenuItem(data, id?)`, `removeGangMenuItem(id)`, `addBusinessMoney(jobName, amount, reason?)`, `removeBusinessMoney(jobName, amount, reason?)`, `getBusinessBalance(jobName)`, `bossmenuAddMoney(jobName, amount)`, `bossmenuRemoveMoney(jobName, amount)`, `addGangMoney(gangName, amount)`, `removeGangMoney(gangName, amount)`, `getGangBalance(gangName)` | `nil`, `false`, `0`, or `nil, 'unavailable'` by function |
| `clothing` | client/server | `openWardrobe()`, `openClothingRoom(options?)`, `applyAppearanceToPed(ped, model, skin)`, `applyStarterAppearance()`, `reloadSkin()`, `openAdminSession(targetSrc, service)` | `nil`, `false`, or `false, 'unavailable'` by function |
| `dispatch` | server | `createCall(payload)`, `updateCall(id, patch)`, `closeCall(id, reason?)`, `getCalls(filter?)`, `registerPlayerAlert(key, definition)`, `createPlayerCall(src, key)` | `false, 'unavailable'` or `{}` for `getCalls` |
| `doorlock` | client/server | `getClosestDoor()`, `getDoorState(id)`, `pickClosestDoor()`, `setDoorState(id, state)`, `createDoor(raw)`, `registerDoorPolicy(id, callback)` | `nil` or `false` by function |
| `fuel` | client | `getFuel(vehicle)`, `setFuel(vehicle, level)`, `isElectricVehicle(vehicle)` | `0` or `false` by function |
| `helptext` | client | `showHelpText(text, options?)`, `updateHelpText(id, text, options?)`, `hideHelpText(id)` | `nil` or `false` by function |
| `notify` | client | `sendNotification(payload)` | `nil` |
| `vehiclekeys` | server | `giveKeys(src, plate, allowWhenDisabled?)`, `removeKeys(src, plate)`, `hasKeys(src, plate)` | `false` |

The current vehicle key resource exposes server exports only, so this version does not add client key functions. `sendNotification` delegates to `Kora.notify.send`, retaining `Config.third_party_notify` behavior. `helptext` delegates to `Kora.textui`.

The `bossmenuAddMoney` and `bossmenuRemoveMoney` names keep the legacy boss-menu account operations distinct from the banking `addAccountMoney` and `removeAccountMoney` methods.

## Registering and selecting providers

Provider modules live under `modules/bridge/modules/<area>/<provider_name>/`, with optional `shared.lua` and realm-specific `client.lua` and `server.lua` files. Each file returns a table of adapter functions. `bridge_init.lua` merges the shared table with the current realm table, validates the complete contract, and registers it. Adapter Lua is shipped in the resource but only the selected provider files are loaded. Add the provider module and its resource-name mapping to `providerCatalog` in `bridge_init.lua`; that catalog lets auto mode check which provider resources are started. `Kora.bridge.register(area, providerName, adapter)` checks that every required function for the current realm exists. `Kora.bridge.getProvider(area)` returns the selected started provider name or `nil`.

`'auto'` considers cataloged modules and registered runtime adapters whose resource state is `'started'`. It prefers names beginning with `kora_`, then sorts remaining provider names alphabetically. A forced provider name never falls back to another adapter. Start and stop events invalidate the cached resource state and area selection.

## Writing a bridge adapter

Create `modules/bridge/modules/<area>/<provider_name>/` and add the needed `shared.lua`, `client.lua`, and `server.lua` files. Each file returns a table containing the functions for its realm; the loader merges and validates the selected module. Verify the third-party export name, arguments, and return values from that resource's source or official documentation; do not infer them from a familiar resource name.

The following vehicle-key adapter is a **template only**. The export name is a placeholder and must be replaced with a verified call before submission; it is not shipped as a real provider.

```lua
-- modules/bridge/modules/vehiclekeys/example_resource/server.lua
return {
    giveKeys = function(src, plate, allowWhenDisabled)
        -- Replace with the verified server export for this resource.
        return exports.example_resource:GiveKeys(src, plate, allowWhenDisabled)
    end,
    removeKeys = function(src, plate)
        -- Replace with the verified server export for this resource.
        return exports.example_resource:RemoveKeys(src, plate)
    end,
    hasKeys = function(src, plate)
        -- Replace with the verified server export for this resource.
        return exports.example_resource:HasKeys(src, plate)
    end,
}
```

### Provider adapter PR checklist

- Confirm each adapter method against the provider's source or official docs and preserve its actual argument and return behavior.
- Register only in valid realms and provide every required contract function for that realm.
- Add a smoke test for provider selection and the adapter mapping where practical.
- Add the adapter folder and provider-to-resource mapping in `providerCatalog`; make the config value match the folder name.
- Keep exports in the matching realm file; do not add runtime export hijacks or consumer edits.
- Document any API divergence or safe fallback.

## Failure behavior

A provider that is stopped or missing is unavailable. Provider call errors are caught so they do not escape into the consumer. Failures are logged through `Kora.logging` as `bridge.provider_unavailable`, `bridge.provider_load_failed`, or `bridge.provider_call_failed`, with only area, provider name, and method metadata. No call arguments are logged.

The bridge does not migrate consumer resources. When migrating, replace their direct provider export calls with the corresponding `Kora.bridge` method in a separate change.