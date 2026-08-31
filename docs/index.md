---
layout: default
title: qblib
---

Shared helper library for the qbcore2 resource set — no direct dependencies of
its own. Populates a single global `QB` table over dynamically-generated
exports (`QB.<module>.<function>` → `exports.qblib:<module>_<function>`), and
covers the ground every FiveM resource needs: a headless NUI framework (menus,
context menus, radial menus, input dialogs, alerts) with matching theme
tokens, notifications, progress bars, box/sphere/poly zones with an in-world
creator, keyboard-driven world-object interaction, a per-tick local-player
cache, reference-counted control leases, streaming/anim/fx/raycast/world helpers, status effects, commands,
permissions, and logging. Also ships drop-in compat for the deprecated
`qb-menu`, `qb-input`, and `qb-radialmenu` standalone resources.

## Requirements

None.

## Installation

`server.cfg`:
```
ensure qblib
```

Any consumer resource pulls the `QB` proxy into its own script scope with:
```lua
shared_script '@qblib/init.lua'
```
That's what makes `QB.notify.send(...)`, `QB.cache.ped()`, etc. resolve —
under the hood each call compiles down to `exports.qblib:<module>_<function>(...)`.

## Usage examples

### A consumer resource's fxmanifest
```lua
fx_version 'cerulean'
game 'gta5'

dependency 'qblib'
shared_script '@qblib/init.lua'

client_script 'client.lua'
```

### Notify a player
```lua
-- client
QB.notify.send({ title = "Saved", message = "Your changes were saved.", duration = 4000 })
```
```lua
-- server
QB.notify.send(source, { title = "Payment failed", message = "Not enough cash.", type = "error" })
```

### Progress bar with an animation
```lua
-- client
local completed = QB.progressbar.start({
    label = "Picking lock...",
    duration = 8000,
    canCancel = true,
    disable = { move = true, combat = true, car = true },
    anim = { dict = "anim@amb@clubhouse@tutorial@bkr_tut_ig3@", clip = "machinic_loop_mechandplayer" },
    props = { { model = "prop_tool_screwdvr01", bone = 60309 } },
})

if completed then
    print("Lock picked.")
end
```

### Read the local-player cache
```lua
-- client
CreateThread(function()
    while true do
        if QB.cache.vehicle() and QB.cache.seat() == -1 then
            -- driving
        end
        Wait(500)
    end
end)
```

### A sphere zone with enter/exit callbacks
```lua
-- client
local zone = QB.zones.sphere({
    coords = vector3(100.0, 200.0, 30.0),
    radius = 3.0,
    onEnter = function(zone) print('entered zone', zone.id) end,
    onExit = function(zone) print('left zone', zone.id) end,
})
```

### A headless menu
```lua
-- client, inside a coroutine (e.g. a command handler)
local result = QB.nui.openMenu({
    { id = "repair", label = "Repair vehicle" },
    { id = "impound", label = "Impound vehicle" },
}, "Mechanic")

if result and not result.cancelled then
    print("selected:", result.selectedId)
end
```

### World interaction zone (qb-target-style options)
```lua
-- client
QB.interact.addCircleZone("locker", vector3(100.0, 200.0, 30.0), 2.0, {}, {
    options = {
        { label = "Open locker", event = "my-resource:client:openLocker", args = { "police" } },
    },
})
```

## API reference

All client-side unless noted.

### Cache (`QB.cache`)
```lua
QB.cache.get(key)  QB.cache.set(key, value)
QB.cache.onChange(key, handler)  QB.cache.offChange(key)
QB.cache.playerId()  QB.cache.serverId()
QB.cache.ped()  QB.cache.vehicle()  QB.cache.seat()
QB.cache.enteringVehicle()  QB.cache.enteringSeat()
QB.cache.weapon()  QB.cache.health()  QB.cache.isDead()  QB.cache.armour()  QB.cache.stamina()
```
Refreshes every `Config.cache.tickInterval` (200ms default); the built-in keys
cannot be overwritten via `set`.

### NUI (`QB.nui`)
```lua
QB.nui.send(action, data)  QB.nui.request(action, data, timeout)
QB.nui.setFocus(mouse, keyboard)  QB.nui.withFocus(mouse, keyboard, fn)
QB.nui.registerCallback(name, handler)  QB.nui.copyToClipboard(text)
QB.nui.openMenu(items, title)  QB.nui.openContextMenu(items, x, y)
QB.nui.openRadialMenu(items, opts)  QB.nui.openInputDialog(fields, title, description)
```
Every module that shows something in-browser goes through this rather than
`SendNUIMessage`/`RegisterNUICallback` directly. Headless: no focus/visibility
until an explicit call, released the instant the interaction ends.

### Notify (`QB.notify`)
```lua
QB.notify.send(payload)             -- client
QB.notify.send(src, payload)        -- server, src = -1 for everyone
QB.notify.sendToAll(payload)        -- server
QB.notify.assert(payload)  QB.notify.withDefaults(payload)   -- shared
```

### Progress bar (`QB.progressbar`)
```lua
QB.progressbar.start(payload)   -- returns completed, error
QB.progressbar.cancel()  QB.progressbar.isActive()
```

### Controls (`QB.controls`)
```lua
local lease = QB.controls.acquire({ 24, 25 }, { inputGroup = 0, disablePlayerFiring = true })
QB.controls.release(lease)
```

### Zones (`QB.zones`)
```lua
QB.zones.box(opts)  QB.zones.sphere(opts)  QB.zones.poly(opts)  QB.zones.point(opts)
QB.zones.getInside(resource)
QB.zones.startCreator(zoneType, existingOpts)   -- in-world creator, /qb_zonecreator
QB.zones.generateSnippet(zoneType, opts)
```
Each handle: `{ id, type, resource, data, remove(), contains(coords), isInside() }`.

### Interact (`QB.interact`)
```lua
QB.interact.addCircleZone(name, coords, radius, zoneOptions, targetOptions)
QB.interact.addBoxZone(name, coords, length, width, zoneOptions, targetOptions)
QB.interact.addTargetEntity(entity, targetOptions)
QB.interact.addTargetModel(models, targetOptions)
QB.interact.removeZone(name)
QB.interact.open(options)  QB.interact.close()  QB.interact.isActive()
```

### Theme (`QB.theme`)
```lua
QB.theme.accentColor()          -- shared, Config.ui.accentColor validated, falls back to #DC143C
QB.theme.tokens(accentColor)    -- shared, HSL token table for a consuming resource's own NUI
QB.theme.push()                 -- client
```

### Status effects (`QB.status`)
```lua
QB.status.registerEffect(name, def)          -- shared
QB.status.apply(target, name, opts)  QB.status.remove(target, name)
QB.status.isActive(target, name)  QB.status.getActive(target)
QB.status.onChange(handler)  QB.status.offChange(listenerId)   -- client
```

### Streaming (`QB.stream`)
```lua
QB.stream.loadModel(model, cb)  QB.stream.loadAnimDict(animDict, cb)  QB.stream.loadAnimSet(animSet, cb)
QB.stream.loadClipSet(clipSet, cb)  QB.stream.loadIpl(iplName, cb)  QB.stream.loadPtfx(fxName, cb)
QB.stream.loadScaleformMovie(scaleformName, cb)  QB.stream.loadTextureDict(textureDict, cb, isAdditionalTextures)
QB.stream.loadAudioBank(audioBank, cb)  QB.stream.loadCollision(coords, cb, entity)
QB.stream.loadWeaponAsset(weapon, cb, weaponResourceFlags, extraWeaponComponentFlags)
```

### Animation (`QB.anim`)
```lua
QB.anim.play(entity, dict, clip, opts)  QB.anim.stop(entity, blendOutSpeed)  QB.anim.stopHandle(handle, blendOutSpeed)
QB.anim.isPlaying(entity)  QB.anim.attachProp(entity, model, bone, offset, rotation, opts)  QB.anim.detachProp(prop)
```

### Effects (`QB.fx`)
```lua
QB.fx.playPtfx(def)  QB.fx.stop(handle)
QB.fx.screenEffect(name, duration, looped)  QB.fx.stopScreenEffect(handle)
```

### Raycast (`QB.raycast`)
```lua
QB.raycast.fromCoords(startCoords, endCoords, flags, ignoreEntity)
QB.raycast.fromCamera(maxDistance, flags, ignoreEntity)
QB.raycast.fromCam(cam, maxDistance, flags, ignoreEntity)
```

### World / entities / closest / distance
```lua
QB.world.getNearbyEntities(entityType, coords, radius, options)   -- client + server
QB.world.getClosestEntity(entityType, coords, options)            -- client + server
QB.entities.create(model, coords, options)  QB.entities.remove(entity)
QB.closest.player(coords, distance)  QB.closest.vehicle(coords, distance)
QB.closest.ped(coords, distance)  QB.closest.object(coords, distance)   -- client + server (server takes src)
QB.distance.player(coords, distance)  QB.distance.coords(coords1, coords2, distance)
QB.distance.entity(entity, distance)  QB.distance.x/y/xy(point, distance)
```

### Blips / drawing / visuals
```lua
QB.blips.create(coords, options)  QB.blips.remove(blip)
QB.drawing.text3d(coords, text, options)
QB.visuals.fade(duration, fn)  -- legacy visuals.fade(coords, duration) remains supported
QB.teleport.player(coords, opts)  QB.teleport.entity(entity, coords, opts)
```

### Minigames
```lua
QB.minigames.play(gameType, opts)              -- client
QB.minigames.consumeProof(src, token, gameType) -- server
```

### Commands / permissions / logging (server)
```lua
QB.commands.add(name, help, args, argsRequired, handler, opts)
QB.commands.remove(name)  QB.commands.refresh(src)  QB.commands.list()
QB.permissions.getLevel(src, levels, prefix)  QB.permissions.hasPermission(src, permission, prefix)
QB.logging.event(category, src, data)  QB.logging.getStats()
```

### Discord (server)
```lua
QB.discord.createEmbed(options)  QB.discord.sendWebhook(url, payload, callback)
QB.discord.botEnabled()  QB.discord.botRequest(method, route, payload, callback, auditReason)
QB.discord.getGuild(guildId, callback)  QB.discord.getMember(guildId, userId, callback)
QB.discord.fetchGuildRoles(guildId, callback)
QB.discord.setMemberRoles(guildId, userId, roleIds, callback, auditReason)
QB.discord.addMemberRole(guildId, userId, roleId, callback, auditReason)
QB.discord.removeMemberRole(guildId, userId, roleId, callback, auditReason)
QB.discord.createRole(guildId, role, callback, auditReason)
QB.discord.updateRole(guildId, roleId, role, callback, auditReason)
QB.discord.deleteRole(guildId, roleId, callback, auditReason)
QB.discord.getChannels(guildId, callback)  QB.discord.getChannel(channelId, callback)
QB.discord.createChannel(guildId, channel, callback, auditReason)
QB.discord.updateChannel(channelId, attributes, callback, auditReason)
QB.discord.deleteChannel(channelId, callback, auditReason)
QB.discord.sendMessage(channelId, payload, callback)
QB.discord.editMessage(channelId, messageId, payload, callback)
QB.discord.deleteMessage(channelId, messageId, callback, auditReason)
QB.discord.syncRoles(callback)  QB.discord.refreshMember(id, callback)
QB.discord.getGuildRoles(guildId)  QB.discord.getRole(role, guildId)
QB.discord.getRoles(id)  QB.discord.hasRole(id, role)  QB.discord.hasRoles(id, roles, requireAll)
QB.discord.hasAnyRole(id, roles)  QB.discord.hasAllRoles(id, roles)
QB.discord.giveRole(id, role, callback, auditReason)
QB.discord.removeRole(id, role, callback, auditReason)
```
The bot helpers make no HTTP request unless `qblib_discord_bot_token` is set.
`qblib_discord_guild_id` and `qblib_discord_webhook` provide optional defaults;
the console-only `qblib_discord_sync` command plus a five-minute heartbeat keep
online-player roles cached and (when qbsql is running) persisted. See
[`modules/discord/docs.md`](../modules/discord/docs.md) for setup, permissions,
payloads, cache behavior, and callbacks.

### Utilities (shared)
```lua
QB.util.clamp(value, min, max)  QB.util.round(value, decimals)  QB.util.randomFloat(min, max)
QB.util.weightedChoice(list)  QB.util.tableContains(t, value)  QB.util.deepClone(value)
QB.print.debug/info/warn/error/success(...)
QB.loops.controlled(call, tries, timeout, backoff)
QB.lang(key, ...)
```

### Callbacks / events (`QB.callback`, `QB.events`)
```lua
QB.callback.register(name, handler)  QB.callback.unregister(name)
QB.callback.trigger(name, ...)                    -- client
QB.callback.trigger(target, name, ...)            -- server
QB.events.register(name, handler)  QB.events.unregister(name)  QB.events.push(target, name, ...)   -- server
QB.events.onPush(name, handler)  QB.events.offPush(name)  QB.events.trigger(name, ...)             -- client
```

## Legacy compat

`compat/client/qb-menu.lua`, `qb-input.lua`, and `qb-radialmenu.lua` keep
`exports['qb-menu']:openMenu/closeMenu`, `exports['qb-input']:ShowInput`, and
`exports['qb-radialmenu']:AddOption/RemoveOption` working unmodified for
resources still written against the standalone `qb-menu`/`qb-input`/
`qb-radialmenu` resources — qblib `provide`s all three identities so
`dependency` checks pass without those resources actually being installed.
Everything routes onto the `QB.nui.open*` calls above.

## Config highlights (`config.lua`)

`Config.ui.accentColor` (brand colour driving `QB.theme.tokens()`),
`Config.notify.defaultDuration/maxDuration/defaultType/defaultPosition`,
`Config.progressbar.maxDuration/maxProps/cancelControl`, `Config.cache.tickInterval`,
`Config.zones.gridSize/tickFar/tickNear/tickInside/creator.enabled`,
`Config.third_party_notify` (route notifications through an event instead of
qblib's own NUI toast).

## Related resources

Part of the [qbcore2](https://github.com/qbcore2) resource set:

- [qbsql](https://qbcore2.github.io/qbsql/) — database driver
- [qbcore](https://qbcore2.github.io/qbcore/) — framework core
- [qbinventory](https://qbcore2.github.io/qbinventory/) — headless inventory
- [qbtarget](https://qbcore2.github.io/qbtarget/) — targeting/interaction
- [qbclothing](https://qbcore2.github.io/qbclothing/) — clothing/wardrobe
- [qbadmin](https://qbcore2.github.io/qbadmin/) — admin menu
- [full resource list ↗](https://github.com/orgs/qbcore2/repositories)
