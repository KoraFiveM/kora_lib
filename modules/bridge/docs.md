# Bridge

`Kora.bridge` exposes provider functions that are assigned directly by the selected module. Provider-specific export calls stay in the provider file, so consumers call one stable Kora function.

`Config.Bridge` in `config.lua` maps each bridge area to a provider folder. For example, `banking = 'kora_banking'` loads `modules/bridge/modules/banking/kora_banking/`. `bridge_init.lua` uses each key as the area folder and each value as the provider folder, then loads the optional `shared.lua` and current realm file. The functions those files declare on `Kora.bridge` become the public API directly.

```lua
Config.Bridge = {
    vehiclekeys = 'kora_vehiclekeys',
    banking = 'kora_banking',
}

-- Server
local ok = Kora.bridge.giveKeys(source, plate)
local balance = Kora.bridge.getSocietyAccountBalance('police')

-- Client
local promptId = Kora.bridge.drawText('Open the door', { key = 'E' })
Kora.bridge.updateText(promptId, 'Close the door', { key = 'E' })
Kora.bridge.hideText(promptId)
```

## Provider areas and contracts

Provider functions are called directly, so their return values and errors pass through unchanged. Each provider owns argument validation and any fallback behavior it needs. A provider file may define the methods needed for that resource.

| Area | Realm | Public functions |
| --- | --- | --- | --- |
| `banking` | server | `addSocietyMoney(name, amount, reason?)`, `removeSocietyMoney(name, amount, reason?)`, `getSocietyAccountBalance(name)`, `executeSocietyTransaction(key, request)`, `executeBankTransaction(key, request)`, `createSocietyBankStatement(playerId, account, amount, reason, kind, accountType?)` |
| `bossmenu` | client/server | `openBossMenu(roleType?)`, `openApplication(jobName, roleType?)`, `addBossMenuItem(data, id?)`, `removeBossMenuItem(id)`, `addGangMenuItem(data, id?)`, `removeGangMenuItem(id)`, `addBusinessMoney(jobName, amount, reason?)`, `removeBusinessMoney(jobName, amount, reason?)`, `getBusinessBalance(jobName)`, `bossmenuAddMoney(jobName, amount)`, `bossmenuRemoveMoney(jobName, amount)`, `addGangMoney(gangName, amount)`, `removeGangMoney(gangName, amount)`, `getGangBalance(gangName)` |
| `clothing` | client/server | `openWardrobe()`, `openClothingRoom(options?)`, `applyAppearanceToPed(ped, model, skin)`, `applyStarterAppearance()`, `reloadSkin()`, `openAdminSession(targetSrc, service)` |
| `dispatch` | server | `createCall(payload)`, `updateCall(id, patch)`, `closeCall(id, reason?)`, `getCalls(filter?)`, `registerPlayerAlert(key, definition)`, `createPlayerCall(src, key)` |
| `doorlock` | client/server | `getClosestDoor()`, `getDoorState(id)`, `pickClosestDoor()`, `setDoorState(id, state)`, `createDoor(raw)`, `registerDoorPolicy(id, callback)` |
| `fuel` | client | `getFuel(vehicle)`, `setFuel(vehicle, level)`, `isElectricVehicle(vehicle)` |
| `helptext` | client | `drawText(text, options?, owner?)`, `updateText(id, text, options?)`, `hideText(id)` |
| `notify` | client | `sendNotification(payload)` |
| `vehiclekeys` | server | `giveKeys(src, plate, allowWhenDisabled?)`, `removeKeys(src, plate)`, `hasKeys(src, plate)` |

The current vehicle key resource exposes server exports only, so this version does not add client key functions. `sendNotification` delegates to `Kora.notify.send`, retaining `Config.third_party_notify` behavior. Non-Kora helptext providers preserve prompt handles and stack bridge-owned prompts, so each resource can update or hide only its own prompt.

The clothing area includes both `kora_clothing` and `illenium-appearance` providers. Set `Config.Bridge.clothing = 'illenium-appearance'` to select iLLenium. Its appearance application expects iLLenium-format appearance data; `applyStarterAppearance` and `reloadSkin` both request iLLenium's saved-skin reload. `openClothingRoom` accepts an iLLenium customization config table or a supported service name (`clothing`, `barber`, `tattoo`, `surgeon`, `creation`, or `wardrobe`).

The `bossmenuAddMoney` and `bossmenuRemoveMoney` names keep legacy boss-menu operations distinct from the society banking methods.

## Selecting providers

`Config.Bridge` maps an area key to the provider folder inside `modules/bridge/modules/`. For example, `banking = 'kora_banking'` loads `modules/bridge/modules/banking/kora_banking/`. `bridge_init.lua` loads that folder's optional `shared.lua` and the current realm file. A value must match the folder name exactly.

## Writing a bridge adapter

Create `modules/bridge/modules/<area>/<provider_name>/` and add the needed `shared.lua`, `client.lua`, and `server.lua` files. Each provider file declares its functions directly on `Kora.bridge` and registers a matching `bridge_<method>` export. Verify the third-party export name, arguments, and return values from that resource's source or official documentation; do not infer them from a familiar resource name.

The following vehicle-key adapter is a **template only**. The export name is a placeholder and must be replaced with a verified call before submission; it is not shipped as a real provider.

```lua
-- modules/bridge/modules/vehiclekeys/example_resource/server.lua

function Kora.bridge.giveKeys(src, plate, allowWhenDisabled)
    -- Replace with the verified server export for this resource.
    return exports.example_resource:GiveKeys(src, plate, allowWhenDisabled)
end
exports("bridge_giveKeys", Kora.bridge.giveKeys)

function Kora.bridge.removeKeys(src, plate)
    -- Replace with the verified server export for this resource.
    return exports.example_resource:RemoveKeys(src, plate)
end
exports("bridge_removeKeys", Kora.bridge.removeKeys)

function Kora.bridge.hasKeys(src, plate)
    -- Replace with the verified server export for this resource.
    return exports.example_resource:HasKeys(src, plate)
end
exports("bridge_hasKeys", Kora.bridge.hasKeys)
```

### Provider adapter PR checklist

- Confirm each adapter method against the provider's source or official docs and preserve its actual argument and return behavior.
- Put functions in the matching realm file and register each one as `bridge_<method>`.
- Add a smoke test for provider selection and the adapter mapping where practical.
- Add the provider folder and set its exact name as the matching `Config.Bridge` value.
- Keep exports in the matching realm file; do not add runtime export hijacks or consumer edits.
- Document any provider API divergence.

## Failure behavior

Only configured provider folders are loaded. A missing file contributes no functions to `Kora.bridge`; function errors pass through directly to the caller.

The bridge does not migrate consumer resources. When migrating, replace their direct provider export calls with the corresponding `Kora.bridge` method in a separate change.
