---
title: Bridge
sidebar_position: 52
---

# Bridge

`Kora.bridge` contains the functions provided by the configured bridge modules. See the [module guide](../../modules/bridge/docs.md) for provider layout and adapter guidance.

Namespace: `Kora.bridge` · Source: `modules/bridge/bridge_init.lua`

## Provider configuration

`Config.Bridge` maps each bridge area to a provider folder. `bridge_init.lua` uses the area key and provider value to load that provider's optional `shared.lua` and current realm file from `modules/bridge/modules/<area>/<provider>/`.

```lua
Config.Bridge = {
    banking = 'kora_banking',
    bossmenu = 'kora_bossmenu',
    clothing = 'kora_clothing',
    dispatch = 'kora_dispatch',
    doorlock = 'kora_doorlock',
    fuel = 'kora_fuel',
    helptext = 'kora_lib',
    notify = 'kora_lib',
    vehiclekeys = 'kora_vehiclekeys',
}
```

The provider folder defines the public functions directly with `function Kora.bridge.<method>(...)`. Each function is registered as an export named `bridge_<method>` from the same provider file.

## Functions

The loaded provider defines the available functions for its area and realm. Current Kora providers include:

- Banking, server: `addSocietyMoney`, `removeSocietyMoney`, `getSocietyAccountBalance`, `executeSocietyTransaction`, `createSocietyBankStatement`
- Boss menu, client/server: menu and business account functions
- Clothing, client/server: wardrobe, appearance, and admin session functions
- Dispatch, server: call and alert functions
- Doorlock, client/server: door lookup and state functions
- Fuel, client: fuel and electric vehicle functions
- Help text, client: `showHelpText`, `updateHelpText`, `hideHelpText`
- Notify, client: `sendNotification`
- Vehicle keys, server: `giveKeys`, `removeKeys`, `hasKeys`

The provider functions' return values and errors pass through directly. If a provider file is absent for the current realm, its functions are not available in that realm.
