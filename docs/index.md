---
layout: default
title: qblib
---

Shared helper library for the qbcore2 resource set. Populates a single global
`QB` table over dynamically-generated
exports (`QB.<module>.<function>` → `exports.qblib:<module>_<function>`), and
covers the ground every FiveM resource needs: a headless NUI framework (menus,
context menus, radial menus, input dialogs, alerts) with matching theme
tokens, notifications, progress bars, box/sphere/poly zones with an in-world
creator, keyboard-driven world-object interaction, a per-tick local-player
cache, reference-counted control leases, streaming/anim/fx/raycast/world helpers,
vehicle properties, keybinds, state-bag subscriptions, text UI, status effects,
commands, permissions, hash-to-name lookup catalogs, and logging. Also ships drop-in compat for the deprecated
`qb-menu`, `qb-input`, and `qb-radialmenu` standalone resources.

## Requirements

`qbtheme` must start before qblib; the manifest declares it as a dependency.

## Installation

`server.cfg`:
```
ensure qbtheme
ensure qblib
```

See [ox_lib parity](ox_lib-parity.md) before migrating an ox_lib consumer. The
libraries overlap substantially, but their globals, signatures, result shapes,
and several runtime semantics are intentionally not drop-in compatible.

Any consumer resource pulls the `QB` proxy into its own script scope with:
```lua
shared_script '@qblib/init.lua'
```
That's what makes `QB.notify.send(...)`, `QB.cache.ped()`, etc. resolve —
under the hood each call compiles down to `exports.qblib:<module>_<function>(...)`.

`types.lua` describes the complete public API for Lua language servers. It is
annotation-only and is deliberately not loaded by consumer resources at runtime;
the `QB` proxy in `init.lua` points editors at those definitions.

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

### World interaction zone
```lua
-- client
QB.interact.addCircleZone("locker", vector3(100.0, 200.0, 30.0), 2.0, {
    options = {
        { label = "Open locker", event = "my-resource:client:openLocker", args = { "police" } },
    },
}, false)
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
Dynamic telemetry refreshes every `Config.cache.tickInterval` (200ms default);
session-stable player ids are resolved once, and a cached seat is only fully
rescanned after its current slot becomes invalid. Built-in keys cannot be
overwritten via `set`.

### Hash lookup (`QB.lookup`)
```lua
local vehicle = QB.lookup.model(GetEntityModel(entity), 'vehicle')
local weapon = QB.lookup.weapon('0x1B06D571')

QB.lookup.preload({ 'vehicle', 'weapon' })
QB.lookup.ready()  QB.lookup.awaitReady(10000)
```
Shared client/server lookup for `vehicle`, `ped`, `object`, `weapon`,
`weapon_component`, and `pickup`. Inputs may be signed/unsigned hashes,
decimal/hexadecimal strings, or canonical names. Base namespaces load lazily;
the startup-scanned custom-resource overlay is synchronized to clients in
bounded atomic batches. See [`modules/lookup/docs.md`](../modules/lookup/docs.md)
for return reasons, record fields, custom overrides, and regeneration.

### NUI (`QB.nui`)
```lua
QB.nui.send(action, data)  QB.nui.request(action, data, timeout)
QB.nui.setFocus(mouse, keyboard)  QB.nui.withFocus(mouse, keyboard, fn)
QB.nui.registerCallback(name, handler)  QB.nui.copyToClipboard(text)
QB.nui.openMenu(items, title)  QB.nui.openContextMenu(items, x, y)
QB.nui.openRadialMenu(items, opts)  QB.nui.openInputDialog(fields, title, description)
QB.nui.registerApp(definition)  QB.nui.openApp(id, opts)
QB.nui.updateApp(id, update)  QB.nui.closeApp(id)  QB.nui.unregisterApp(id)
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

### Entity placement (`QB.placement`)
```lua
local result = QB.placement.start('prop_bin_08') -- or /qb_place prop_bin_08
QB.placement.isActive()
QB.placement.generateSnippet(result)
```
Temporary local preview with a free camera, arrow/Page-key movement,
pitch/roll/yaw rotation, and a copyable transform summary. The preview is
always deleted when the session finishes.

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
QB.zones.isCreatorActive()  QB.zones.edit(handle, opts)  QB.zones.setDebug(id, enabled)
QB.zones.generateSnippet(zoneType, opts)
```
Each handle: `{ id, type, resource, data, remove(), contains(coords), isInside() }`.

### Interact (`QB.interact`)
```lua
QB.interact.addCircleZone(name, coords, radius, targetOptions, debug)
QB.interact.addBoxZone(name, coords, size, targetOptions, debug)
QB.interact.addTargetEntity(entity, size, targetOptions, debug)
QB.interact.addTargetModel(models, size, targetOptions, debug)
QB.interact.removeZone(name)
QB.interact.open(options)  QB.interact.close()  QB.interact.isActive()
```

### Keybinds / text UI (`QB.keybind`, `QB.textui`)
```lua
local bind = QB.keybind.add({
    name = 'my_resource_menu',
    description = 'Open menu',
    defaultKey = 'HOME',
    secondaryKey = 'F6',
    onPressed = function(handle) print(handle.getCurrentBinding()) end,
    onReleased = function(handle) print(handle.isPressed()) end,
})
bind.disable(true)  bind.isDisabled()  bind.remove()

local prompt = QB.textui.show('Open the vehicle', {
    key = 'E', icon = 'Key', position = 'right-center',
})
QB.textui.update(prompt, 'Enter the vehicle', { key = 'E' })
QB.textui.isOpen(prompt)  QB.textui.isVisible(prompt)  QB.textui.hide(prompt)
```
Keybind callbacks are protected and registrations are owned by the invoking
resource. Text UI entries form a stack: only the newest live handle is visible.

### Theme (`QB.theme`)
```lua
QB.theme.accentColor()          -- shared, forwards qbtheme's configured primary colour
QB.theme.tokens(overrides)      -- shared, complete qbtheme CSS-variable map
QB.theme.push()                 -- client, refresh qblib's frame from qbtheme
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
QB.world.isSpawnClear(coords, radius, options)                    -- client + server
QB.world.getGroundCoords(coords, options)  QB.world.getStreetNames(coords)
QB.world.getZoneName(coords)  QB.world.getCardinalDirection(heading, options)
QB.world.getWaypointCoords()
QB.entities.create(model, coords, options)  QB.entities.remove(entity)
QB.closest.player(coords, distance)  QB.closest.vehicle(coords, distance)
QB.closest.ped(coords, distance)  QB.closest.object(coords, distance)   -- client + server (server takes src)
QB.distance.player(coords, distance)  QB.distance.coords(coords1, coords2, distance)
QB.distance.entity(entity, distance)  QB.distance.x/y/xy(point, distance)
```

### Blips / drawing / visuals
```lua
QB.blips.create(coords, options)  QB.blips.remove(blip)
QB.blips.getCategoryIds()  -- shared fixed name -> native id catalogue
QB.blips.getCategories()  QB.blips.getRegistered()
QB.blips.hideCategory(category)  QB.blips.showCategory(category)
QB.blips.hide(blip)  QB.blips.show(blip)
QB.drawing.text3d(coords, text, options)
QB.visuals.fade(duration, fn)  -- legacy visuals.fade(coords, duration) remains supported
QB.teleport.player(coords, opts)  QB.teleport.entity(entity, coords, opts)
QB.teleport.toWaypoint(opts)
QB.vehicle.plate(vehicle)  QB.vehicle.label(vehicle)
QB.vehicle.getProperties(vehicle)  QB.vehicle.setProperties(vehicle, properties, opts)
```

Players can run `/blips` to open the client-local category visibility settings.
The screen updates immediately and persists each player's choices; resource
ownership metadata is shown only to server-confirmed admins.

### State bags (`QB.state`)
```lua
local listener = QB.state.onChange('locked', nil, function(change)
    print(change.entity, change.bagName, change.key, change.value)
end)
QB.state.offChange(listener)
```
Filters may be `nil` wildcards. The context also includes `reserved` and
`replicated`; non-entity bags resolve `entity` to `0`.

### Minigames
```lua
QB.minigames.play(gameType, opts, authorization)                         -- client
QB.minigames.authorizeProof(src, gameType, trustedOpts)                   -- server
QB.minigames.consumeProof(src, proof, gameType, authorization)            -- server
```
Only a session started with a server-issued authorization can return a
proof. Authorizations and proofs are opaque, single-use, player/game/resource
bound, and short-lived; see `modules/minigames/docs.md` for the complete flow.

### Commands / permissions / logging (server)
```lua
QB.commands.add(name, help, args, argsRequired, handler, opts)
QB.commands.remove(name)  QB.commands.refresh(src)  QB.commands.list()
QB.permissions.getLevel(src, levels, prefixOrOptions)
QB.permissions.hasLevel(src, required, levels, prefixOrOptions)
QB.permissions.hasPermission(src, permission, prefixOrOptions)
QB.logging.event(category, src, data)  QB.logging.getStats()
```
`opts.keybind` can define `description`, primary mapper/key, and secondary
mapper/key. qblib synchronizes a client mapping, but every press still executes
the registered server command through its normal permissions and argument path.

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
QB.random.pick(list, options)  -- one value, or an array when options.count > 1
QB.util.clamp(value, min, max)  QB.util.round(value, decimals)  QB.util.randomFloat(min, max)
QB.util.weightedChoice(list)  QB.util.tableContains(t, value)  QB.util.deepClone(value)
QB.util.lerp(a, b, t)
QB.util.vecAdd/vecSub/vecScale/vecLength/vecNormalize(...)
QB.util.vecDistance(a, b)  QB.util.vecDistance2d(a, b)   -- 2d ignores z; the right "how far is that call"
QB.util.headingToDirection(heading)  QB.util.directionToHeading(v)  QB.util.bearing(origin, target)
QB.util.worldToScreen(coords)  QB.util.worldToScreenPixels(coords)   -- client
QB.print.debug/info/warn/error/success(...)
QB.loops.controlled(call, tries, timeout, backoff)
QB.lang(key, ...)
```

### Timers (`QB.timers`, shared)
```lua
QB.timers.setInterval(fn, ms)   QB.timers.clearInterval(id)
QB.timers.setTimeout(fn, ms)    QB.timers.clearTimeout(id)
QB.timers.debounce(fn, wait)    -- trailing edge; .cancel() / .isPending()
QB.timers.throttle(fn, interval)-- leading edge, drops (never queues); .reset() / .remaining()
```
Every timer is owned by the resource that created it and cancelled when that
resource stops. `QB.loops.controlled` is the sibling for "poll until true, then
stop"; this module is for "run every N ms until I say stop".

### Sound (`QB.sound`, client)
```lua
QB.sound.playFrontend(name, set, options)          -- returns a stoppable sound id
QB.sound.playFromCoords(coords, name, set, options)
QB.sound.playFromEntity(entity, name, set, options)
QB.sound.stop(soundId)  QB.sound.isLive(soundId)
```
Sound ids are a small finite pool, so every id allocated here is auto-released
(`Config.sound.defaultReleaseAfter`), released early by `stop`, and swept when
the owning resource stops.

### Callbacks / events (`QB.callback`, `QB.events`)
```lua
QB.callback.register(name, handler, { rateLimit = { max = 5, window = 1000 } })
QB.callback.unregister(name)
QB.callback.trigger(name, ...)                    -- client
QB.callback.trigger(target, name, ...)            -- server
QB.events.register(name, handler, { rateLimit = { max = 10, window = 1000 } })
QB.events.unregister(name)  QB.events.push(target, name, ...)   -- server
QB.events.onPush(name, handler)  QB.events.offPush(name)  QB.events.trigger(name, ...)             -- client
```
Server registration limits are optional, per-player and per-name sliding
windows. Limited events are dropped; limited callbacks immediately reject with
their retry delay.

### Configuration (`QB.config`)
```lua
Config = QB.config.define({
    localRange = QB.config.number(20.0, { min = 1, max = 100 }),
})
```
Resources can register typed Lua configuration without giving up their normal
`Config` table. qblib writes only changed, server-specific values to
`config.local.lua`; the community-authored `config.lua` remains ordered,
commented, and update-friendly. Fields are restart-required unless explicitly
safe to apply live. `shared`, `client`, and `server` scopes control client
synchronization, and qbadmin provides the owner-only editor and audit trail.
See [the configuration guide](../modules/config/docs.md) for schemas,
handlers, migration, persistence, and security boundaries.

## Legacy compat

`compat/client/qb-menu.lua`, `qb-input.lua`, and `qb-radialmenu.lua` keep
`exports['qb-menu']:openMenu/closeMenu`, `exports['qb-input']:ShowInput`, and
`exports['qb-radialmenu']:AddOption/RemoveOption` working unmodified for
resources still written against the standalone `qb-menu`/`qb-input`/
`qb-radialmenu` resources — qblib `provide`s all three identities so
`dependency` checks pass without those resources actually being installed.
Everything routes onto the `QB.nui.open*` calls above.

## Config highlights (`config.lua`)

`qbtheme/config.lua` owns the shared palette and brand colour. qblib's
`QB.theme` functions remain compatibility forwards to that resource.
`Config.notify.defaultDuration/maxDuration/defaultType/defaultPosition`,
`Config.progressbar.maxDuration/maxProps/cancelControls`, `Config.minigames.authorizationTTL/proofTTL/inputLimits/callbackRateLimits`, `Config.cache.tickInterval`,
`Config.zones.gridSize/tickFar/tickNear/tickInside/creator.enabled`,
`Config.third_party_notify` (route notifications through an event instead of
qblib's own NUI toast). qblib uses the same `QB.config` platform internally;
server-specific overrides belong in its ignored `config.local.lua`, while
`Config.discord` is server-only.

## Related resources

Part of the [qbcore2](https://github.com/qbcore2) resource set:

- [qbsql](https://qbcore2.github.io/qbsql/) — database driver
- [qbcore](https://qbcore2.github.io/qbcore/) — framework core
- [qbinventory](https://qbcore2.github.io/qbinventory/) — headless inventory
- [qbtarget](https://qbcore2.github.io/qbtarget/) — targeting/interaction
- [qbclothing](https://qbcore2.github.io/qbclothing/) — clothing/wardrobe
- [qbadmin](https://qbcore2.github.io/qbadmin/) — admin menu
- [full resource list ↗](https://github.com/orgs/qbcore2/repositories)
