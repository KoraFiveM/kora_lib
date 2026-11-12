---
title: Installation
sidebar_position: 2
---

# Installation

kora_lib is a FiveM resource. It requires `kora_theme`, which owns the shared palette and must start first.

## Install the resources

Place both resources in your server's resources directory, then ensure them in order:

```cfg
ensure kora_theme
ensure kora_lib
```

kora_lib's manifest also declares `kora_theme` as a dependency, so FiveM will reject an invalid start order instead of leaving the interface partially configured.

## Optional legacy manifest imports

New kora_lib resources need neither `ox_lib` nor `PolyZone`; use the public
`Kora.nui` and `Kora.zones` APIs directly. `Kora.ox` is the private bridge behind
the optional `ox_lib` resource. Do not ensure either compatibility resource by
default.

| Consumer situation | Start |
| --- | --- |
| New resource using `Kora.*` | `kora_theme`, then `kora_lib` |
| Legacy resource with a normal `dependency 'qb-menu'`-style dependency | `kora_theme`, then `kora_lib`; its `provide` identity is enough |
| Legacy manifest imports `@ox_lib/...` | `kora_theme`, `kora_lib`, then the optional resource named `ox_lib` |
| Legacy manifest imports `@PolyZone/...` | `kora_theme`, `kora_lib`, then the optional resource named `PolyZone` |

An older resource can hard-code a file import such as
`@ox_lib/init.lua` or `@PolyZone/BoxZone.lua` in its manifest. `provide` cannot
satisfy that kind of import: FiveM needs a real, started resource with the exact
name. Only then install the matching kora_lib-backed wrapper and start it after
`kora_lib`, before that legacy consumer:

```cfg
ensure kora_theme
ensure kora_lib
ensure ox_lib   # only for @ox_lib/... imports

# Or, for @PolyZone/... imports:
# ensure PolyZone
```

Keep the wrapper folder name exactly `ox_lib` or `PolyZone`, matching the
consumer's manifest. Remove it again after the final legacy import is migrated.
The [legacy compatibility guide](./legacy-compat.md) lists the
provided surfaces and PolyZone import order. Do not substitute broad
`ensure [test]` or `ensure [compat]` group starts for these explicit lines:
either group can start optional wrappers alongside unrelated resources.

## Add kora_lib to a resource

Declare the dependency and load the proxy from the consuming resource's `fxmanifest.lua`:

```lua
fx_version 'cerulean'
game 'gta5'

dependency 'kora_lib'
shared_script '@kora_lib/init.lua'

client_script 'client.lua'
server_script 'server.lua'
```

Loading the proxy as a shared script makes `Kora` available to the consumer's shared, client, and server scripts. Individual functions are still limited to the realms stated on their reference pages.

## Choose the native API

New code should call kora_lib directly; the optional wrappers exist only for an
unchanged legacy contract.

| Need | Native API |
| --- | --- |
| Menus, forms, alerts, or radial selections | [`Kora.nui`](./reference/nui.md) — `openMenu`, `openContextMenu`, `openInputDialog`, `openAlert`, or `openRadialMenu` |
| Prompts, notifications, or progress | [`Kora.textui`](./reference/textui.md), [`Kora.notify`](./reference/notify.md), and [`Kora.progressbar`](./reference/progressbar.md) |
| A static area trigger | [`Kora.zones`](./reference/zones.md) — `box`, `sphere`, `circle`, or `poly` |
| Client/server request-response | [`Kora.callback`](./reference/callback.md) |
| A valuable server-side action | [`Kora.actions`](./reference/actions.md) or a server-validated callback |

`Kora.ox` is not a native UI API: it is the owner-aware internal provider used
only by the optional `ox_lib` compatibility resource.

## Verify the installation

Add a temporary client command to a consumer resource:

```lua
RegisterCommand('kora_lib_check', function()
    Kora.notify.send({
        title = 'kora_lib is ready',
        message = ('Player %s is connected.'):format(Kora.cache.serverId()),
        type = 'success',
    })
end, false)
```

Restart the consumer and run `/kora_lib_check`. A notification with your server ID confirms that the proxy, client exports, cache, theme, and NUI are available.

## Keep valuable actions server-authoritative

Use the client for presentation and the server for anything that changes
money, inventory, progression, or permissions. A progress bar, zone hit, or
client minigame result is never authorization by itself:

```lua
-- server.lua
Kora.callback.register('my-resource:server:claimReward', function(src, rewardId)
    if not isValidReward(rewardId) or not isPlayerAtReward(src, rewardId) then
        return false, 'Not available.'
    end

    giveReward(src, rewardId)
    return true
end, { rateLimit = { max = 3, window = 10000 } })

-- client.lua
local claimed, reason = Kora.callback.trigger('my-resource:server:claimReward', rewardId)
if not claimed then Kora.notify.send({ message = reason, type = 'error' }) end
```

Validate the player's identity, permission, distance, cooldown, and live
server state in that server handler. The [security boundary](./using-the-api.md#security-boundary)
and [actions reference](./reference/actions.md) cover longer
flows with progress bars and proof-producing minigames.

## Editor types

The shipped `types.lua` is annotation-only. kora_lib does not execute it at runtime; `init.lua` points Lua language servers to its declarations. For the best completion and diagnostics, use a Lua language server configured for the CfxLua runtime and make sure the installed resource files are part of its workspace.

## Updating

Update `kora_theme` and `kora_lib` together when a release notes a shared interface or token change. Keep server-specific configuration in `config.local.lua`; kora_lib deliberately leaves that file untracked so updates do not overwrite local values. Review the [configuration reference](./reference/config.md) before moving settings out of authored resource files.

Next: [Using the API](./using-the-api.md).
