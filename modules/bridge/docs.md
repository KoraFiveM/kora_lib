# Bridge

`Kora.bridge` is a provider registry for APIs that may be supplied by different resources. It keeps provider-specific export calls inside kora_lib so consumers can call one stable Kora function.

The registry is selected per area. `Config.bridge` in `config.lua` accepts `'auto'` or a provider resource name for each area. Auto mode uses a started Kora provider first, then the first started registered provider by name. A forced name selects only that adapter. Provider state is cached and invalidated when the resource starts or stops.

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

Provider adapters are shared scripts under `modules/bridge/providers/<area>/<resource_name>.lua`. The manifest loads that folder, and each adapter registers its own resource name. Each realm registers only the functions that exist in that realm. `Kora.bridge.register(area, providerName, adapter)` checks that every required function for that area and realm exists. `Kora.bridge.getProvider(area)` returns the selected started provider name or `nil`.

`'auto'` considers only registered adapters whose resource state is `'started'`. It prefers names beginning with `kora_`, then sorts remaining provider names alphabetically. A forced provider name never falls back to another adapter. Start and stop events invalidate the cached resource state and area selection.

## Writing a bridge adapter

Create one adapter file at `modules/bridge/providers/<area>/<resource_name>.lua` and register an adapter table with every function required by that area and realm. Verify the third-party export name, arguments, and return values from that resource's source or official documentation; do not infer them from a familiar resource name.

The following vehicle-key adapter is a **template only**. The export name is a placeholder and must be replaced with a verified call before submission; it is not shipped as a real provider.

```lua
-- modules/bridge/providers/vehiclekeys/example_resource.lua
if IsDuplicityVersion() then
    Kora.bridge.register('vehiclekeys', 'example_resource', {
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
    })
end
```

### Provider adapter PR checklist

- Confirm each adapter method against the provider's source or official docs and preserve its actual argument and return behavior.
- Register only in valid realms and provide every required contract function for that realm.
- Add a smoke test for provider selection and the adapter mapping where practical.
- Include the provider's resource name as the adapter key; do not add runtime export hijacks or consumer edits.
- Document any API divergence or safe fallback.

## Failure behavior

A provider that is stopped or missing is unavailable. Provider call errors are caught so they do not escape into the consumer. Failures are logged through `Kora.logging` as `bridge.provider_unavailable` or `bridge.provider_call_failed`, with only area, provider name, and method metadata. No call arguments are logged.

The bridge does not migrate consumer resources. When migrating, replace their direct provider export calls with the corresponding `Kora.bridge` method in a separate change.