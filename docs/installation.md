---
title: "Installation"
sidebar_position: 2
---


# Installation

Follow these steps in order. Kora Lib needs Kora Theme to run, and every resource that uses Kora Lib has to be connected to it once.

## Install Kora Lib

1. **Add both folders to your server** — Copy the `kora_theme` and `kora_lib` folders into your server’s `resources` folder, the folder your server loads all of its scripts from. Keep both folder names exactly as they are. 
   
    If you downloaded from GitHub, remove any `-main` or `-master` from the end, so `kora_lib-main` becomes `kora_lib`.

2. **Start them in server.cfg** — Open `server.cfg` and add these two lines. Order matters: `kora_theme` has to be above `kora_lib`, because Kora Lib needs Kora Theme loaded first. If one is missing or misnamed, FiveM will say so in the console when the server starts.

   ```bash title="server.cfg"
   ensure kora_theme
   ensure kora_lib
   ```

3. **Connect your resource to Kora Lib** — Open the `fxmanifest.lua` file inside the resource you want to use Kora Lib in, and add this line

   ```lua title="fxmanifest.lua"
   shared_script '@kora_lib/init.lua'
   ```

   The first line makes FiveM start Kora Lib before your resource. The second makes the `Kora` tools available in your resource’s Lua files. Never edited a manifest? Open the walkthrough below.

## Step-by-step example

### Walkthrough: add Kora Lib to a downloaded resource

Say you downloaded a resource called `crushinboulders` from GitHub and want it to use Kora Lib. Here is exactly what to do.

1. **Open the resource folder** — Go to your server’s `resources` folder and open `crushinboulders`. If the folder is called `crushinboulders-main`, rename it to `crushinboulders` first.

2. **Find fxmanifest.lua** — It sits at the top of the folder, next to the resource’s other files. Open it in any text editor, such as VS Code or Notepad++. This is what it looks like before you change anything:

   ```text title="fxmanifest.lua (before)"
   fx_version 'cerulean'
   game 'gta5'
   lua54 'yes'

   author 'SomeAuthor'
   description 'Crush boulders and sell the gravel'
   version '1.0.0'

   shared_script 'config.lua'
   client_script 'client.lua'
   server_script 'server.lua'
   ```

3. **Add the two lines** — Add `dependency 'kora_lib'` and `shared_script '@kora_lib/init.lua'` as shown. Keep the `@kora_lib/init.lua` line above the resource’s own scripts, so Kora Lib is ready when they load.

   ```text title="fxmanifest.lua (after)" {9,11}
   fx_version 'cerulean'
   game 'gta5'
   lua54 'yes'

   author 'SomeAuthor'
   description 'Crush boulders and sell the gravel'
   version '1.0.0'

   dependency 'kora_lib'

   shared_script '@kora_lib/init.lua'
   shared_script 'config.lua'
   client_script 'client.lua'
   server_script 'server.lua'
   ```

4. **Save and restart the resource** — Save the file, then run `restart crushinboulders` in the server console. The resource can now use everything in Kora Lib.

## If it does not start

- Check the folders are named exactly `kora_theme` and `kora_lib`. Folders downloaded from GitHub often end in `-main` or `-master`, like `kora_lib-main`. Remove that part so it reads `kora_lib`.
- Check both folders are inside your server’s `resources` folder (or a folder inside it, such as `[kora]`).
- Check `ensure kora_theme` is on a line above `ensure kora_lib` in `server.cfg`.
- Check your resource’s `fxmanifest.lua` has both Kora Lib lines, then restart that resource.

## Start order and manifest dependency

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


## Choose the native API

New code should call kora_lib directly; the optional wrappers exist only for an
unchanged legacy contract.

| Need | Native API |
| --- | --- |
| Menus, forms, alerts, or radial selections | [`Kora.nui`](./api/nui.md) — `openMenu`, `openContextMenu`, `openInputDialog`, `openAlert`, or `openRadialMenu` |
| Prompts, notifications, or progress | [`Kora.textui`](./api/textui.md), [`Kora.notify`](./api/notify.md), and [`Kora.progressbar`](./api/progressbar.md) |
| A static area trigger | [`Kora.zones`](./api/zones.md) — `box`, `sphere`, `circle`, or `poly` |
| Client/server request-response | [`Kora.callback`](./api/callback.md) |
| A valuable server-side action | [`Kora.actions`](./api/actions.md) or a server-validated callback |

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
and [actions reference](./api/actions.md) cover longer
flows with progress bars and proof-producing minigames.


## Editor types

The shipped `types.lua` is annotation-only. kora_lib does not execute it at runtime; `init.lua` points Lua language servers to its declarations. For the best completion and diagnostics, use a Lua language server configured for the CfxLua runtime and make sure the installed resource files are part of its workspace.


## Updating

Update `kora_theme` and `kora_lib` together when a release notes a shared interface or token change. Keep server-specific configuration in `config.local.lua`; kora_lib deliberately leaves that file untracked so updates do not overwrite local values. Review the [configuration reference](./api/config.md) before moving settings out of authored resource files.

Next: [Using the API](./using-the-api.md).
