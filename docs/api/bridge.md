---
title: Bridge
sidebar_position: 52
---

# Bridge

`Kora.bridge` forwards calls to a started provider for each replaceable resource area. See the [module guide](../../modules/bridge/docs.md) for provider selection, safe fallbacks, and the adapter PR checklist.

Namespace: `Kora.bridge` · Source: `modules/bridge/bridge_init.lua`, `modules/bridge/client.lua`, `modules/bridge/server.lua`

## Provider registry

### `Kora.bridge.register(area, providerName, adapter)`

Registers one provider adapter in the current realm. It asserts that the area and provider module name are valid and that every required function in the area contract is callable. Returns `true` after registration.

### `Kora.bridge.getProvider(area) -> string?`

Returns the selected started provider module name. It returns `nil` when the configured provider is not registered or not started, or when auto selection finds no available provider.

Configure one provider per area in kora_lib's `config.lua`:

```lua
Config.bridge = {
    vehiclekeys = 'auto',
    banking = 'kora_banking',
}
```

`'auto'` prefers a started Kora provider and then sorts remaining started adapters by resource name. A named value forces that provider module. Start and stop events invalidate the cached choice.

## Client functions

- `Kora.bridge.openBossMenu(roleType?)` and `openApplication(jobName, roleType?)`
- `Kora.bridge.addBossMenuItem(data, id?)`, `removeBossMenuItem(id)`, `addGangMenuItem(data, id?)`, and `removeGangMenuItem(id)`
- `Kora.bridge.openWardrobe()`, `openClothingRoom(options?)`, `applyAppearanceToPed(ped, model, skin)`, `applyStarterAppearance()`, and `reloadSkin()`
- `Kora.bridge.getClosestDoor()`, `getDoorState(id)`, and `pickClosestDoor()`
- `Kora.bridge.getFuel(vehicle)`, `setFuel(vehicle, level)`, and `isElectricVehicle(vehicle)`
- `Kora.bridge.showHelpText(text, options?)`, `updateHelpText(id, text, options?)`, and `hideHelpText(id)`
- `Kora.bridge.sendNotification(payload)`

```lua
local prompt = Kora.bridge.showHelpText('Open the door', { key = 'E' })
if prompt then Kora.bridge.hideHelpText(prompt) end
```

## Server functions

- `Kora.bridge.addAccountMoney(name, amount, reason?)`, `removeAccountMoney(name, amount, reason?)`, and `getAccountBalance(name)`
- `Kora.bridge.executeBankTransaction(key, request)` and `createBankStatement(playerId, account, amount, reason, kind, accountType?)`
- `Kora.bridge.addBusinessMoney(jobName, amount, reason?)`, `removeBusinessMoney(jobName, amount, reason?)`, and `getBusinessBalance(jobName)`
- `Kora.bridge.bossmenuAddMoney(jobName, amount)` and `bossmenuRemoveMoney(jobName, amount)` for the boss-menu legacy aliases
- `Kora.bridge.addGangMoney(gangName, amount)`, `removeGangMoney(gangName, amount)`, and `getGangBalance(gangName)`
- `Kora.bridge.createCall(payload)`, `updateCall(id, patch)`, `closeCall(id, reason?)`, `getCalls(filter?)`, `registerPlayerAlert(key, definition)`, and `createPlayerCall(src, key)`
- `Kora.bridge.setDoorState(id, state)`, `createDoor(raw)`, and `registerDoorPolicy(id, callback)`
- `Kora.bridge.giveKeys(src, plate, allowWhenDisabled?)`, `removeKeys(src, plate)`, and `hasKeys(src, plate)`

```lua
if Kora.bridge.giveKeys(source, plate) then
    print('Vehicle key granted')
end
```

## Returns and failures

Successful calls preserve the selected provider's return values. When no provider is available, mutating calls return `false` (or `false, 'unavailable'` where the provider API returns an error value), balance reads return `0`, list reads return an empty table, and nullable reads return `nil`. A provider exception is caught, logged, and converted to the same safe fallback. Invalid public arguments raise an assertion before provider dispatch.

The current Kora adapters are verified against the neighboring Kora resources. No third-party provider implementation is included until its API can be confirmed. See the guide's **Writing a bridge adapter** section for the template and contribution checklist.