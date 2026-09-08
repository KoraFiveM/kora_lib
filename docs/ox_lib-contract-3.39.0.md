---
layout: default
title: ox_lib 3.39.0 contract inventory
---

# ox_lib FiveM parity inventory

Baseline: official `overextended/ox_lib` `main` at
`b8f5a04351b1d427e0e112150d36094e9889ec7b` (manifest version `3.39.0`,
commit date 2026-09-04). Primary source: [pinned official ox_lib
tree](https://github.com/overextended/ox_lib/tree/b8f5a04351b1d427e0e112150d36094e9889ec7b).

Scope is FiveM. RedM branches are recorded only where they affect a shared
contract. This inventory describes runtime Lua contracts, not the separate
experimental TypeScript package under `package/`.

## 0. Architectural requirement (P0, blocking)

An actual resource named **`ox_lib`** is required. FiveM resolves
`shared_script '@ox_lib/init.lua'` by resource name and reads the file from that
resource; `provide 'ox_lib'` does not redirect an `@resource/file` import.

The consumer `init.lua` must execute in the consuming resource's environment.
It cannot be reduced to `exports.qblib:*`, because these contracts contain
consumer-local closures, function arguments, metatables, local registries, and
objects that cannot safely be transported through msgpack/export boundaries:

- `lib.callback`, `lib.addKeybind`, `lib.points`, `lib.zones`, `lib.timer`,
  `lib.cron`, `lib.hook`, `lib.registerHook`;
- `lib.class` and every class/collection/entity object;
- `lib.require`/`lib.load`, locale dictionaries, memoized `cache(...)` values;
- UI registrations that retain callbacks (`registerMenu`, `registerContext`,
  `registerRadial`).

Recommended parity baseline: vendor the upstream runtime at the pinned commit
inside the new `ox_lib` resource, including LGPL-3.0 license/notice and built
web assets. Substitute qblib adapters only after contract tests prove exact
argument, return, error, event, lifecycle, and ownership behavior.

### Manifest contract

The upstream manifest has `fx_version 'cerulean'`, `lua54 'yes'`, OAL enabled,
`games {'rdr3','gta5'}`, version `3.39.0`, `/server:7290` and `/onesync`
dependencies, `ui_page 'web/build/index.html'`, and exposes these files to
consumers:

- `init.lua`, `resource/settings.lua`;
- `imports/**/client.lua`, `imports/**/shared.lua`;
- `locales/*.json`, `modules/**/init.lua`;
- `web/build/index.html`, `web/build/**/*`.

It loads `resource/init.lua` shared, then all `resource/**/shared.lua`, realm
client/server resources, plus server-only callback/hook/registerHook/directory
imports. Preserve this order: `resource/init.lua` creates the exporting `lib`
metatable; later `resource/**` assignments are automatically registered as
exports based on their source path.

## 1. `@ox_lib/init.lua` globals and loader (P0)

Required startup behavior:

- hard-errors unless `_VERSION` contains `5.4`;
- returns immediately when executed by `ox_lib` itself;
- errors on duplicate load when an existing `lib.name == 'ox_lib'`;
- errors when `GetResourceState('ox_lib') ~= 'started'`;
- calls `exports.ox_lib:hasLoaded()` and errors with its returned message unless
  exactly `true`;
- calls `msgpack.setoption('ignore_invalid', true)`;
- installs `_ENV.lib`, `_ENV.cache`, `_ENV.require`, global `noop`, global
  `SetInterval`, and global `ClearInterval`;
- server additionally installs `GetActivePlayers()` and deprecated
  `lib.notify(playerId, data)`; client initializes `cache.playerId` and
  `cache.serverId`;
- reads repeated consumer manifest metadata `ox_lib '<module>'`, eagerly loads
  each listed import, and calls it once if its returned value is a function.

`lib` is a lazy callable table with fixed `name='ox_lib'` and
`context='client'|'server'`. First access loads and concatenates
`imports/<name>/shared.lua` then the current realm file, executes it in the
consumer environment, and caches its return or `noop`. If no import exists,
the member is an ox_lib export wrapper. `lib('name')` follows the same lookup.
Missing export wrappers use upstream's nil receiver convention.

`SetInterval(fn, interval=0, ...) -> numeric thread id`; calling
`SetInterval(existingId, newInterval)` changes its delay; a negative delay
stops it. Invalid callback/interval errors. `ClearInterval(id)` errors for a
non-number or unknown id and marks the interval to terminate after its current
wait.

Global `cache` is callable and indexable:

- fixed `game` (`fivem` client / `fxserver` server) and consumer `resource`;
- `cache(key, producer, timeout?)` memoizes even `false` and clears after an
  optional timeout;
- first read of an engine key registers `ox_lib:cache:<key>`, fetches
  `exports.ox_lib:cache(key)`, and stores `false` when export returns nil;
- `lib.onCache(key, cb)` registers `cb(new, old)`; callbacks run in fresh
  immediate threads **before** the consumer cache field is changed.

Client engine cache keys are `playerId`, `serverId`, `ped`, `vehicle`, `seat`,
`weapon`; `mount` exists on RedM. Missing vehicle/seat/weapon are `false`.
The resource polls every 100 ms. `cache.coords` is opportunistically updated by
points/zones (it is not part of the base cache poll).

qblib gap: `QB` proxy only; no `lib`, global callable/indexable `cache`,
`lib.onCache`, loader metadata, startup guards, interval globals, or ox cache
events. `QB.cache` has related but incompatible function getters, extra keys,
different update cadence, handler ordering/isolation, and write semantics.

## 2. Resource exports (P0)

The ox_lib resource must expose these exact direct names. Realm matters.

Shared:

`hasLoaded`, `setValidCallback`, `isCallbackValid`, `checkDependency`.

Client:

`cache`, `getLocaleKey`, `setLocale`, `setNuiFocus`, `resetNuiFocus`,
`alertDialog`, `closeAlertDialog`, `setClipboard`, `showContext`,
`registerContext`, `getOpenContextMenu`, `hideContext`, `inputDialog`,
`closeInputDialog`, `registerMenu`, `showMenu`, `hideMenu`, `setMenuOptions`,
`getOpenMenu`, `notify`, `defaultNotify`, `progressBar`, `progressCircle`,
`cancelProgress`, `progressActive`, `registerRadial`, `getCurrentRadialId`,
`hideRadial`, `addRadialItem`, `removeRadialItem`, `clearRadialItems`,
`disableRadial`, `showRadialMenu`, `skillCheck`, `cancelSkillCheck`,
`skillCheckActive`, `showTextUI`, `hideTextUI`, `isTextUIOpen`,
`getVehicleProperties`, `setVehicleProperties`.

Server:

`getLocaleKey`, `setVehicleProperties`, `versionCheck`, `addAce`, `removeAce`,
`addPrincipal`, `removePrincipal`.

Explicit/dynamic exports:

- `getLocale(key) -> string?` in each consumer that loads `lib.locale`;
- `registerHook:setPlayerState`, `removeHook:setPlayerState`,
  `registerHook:setEntityState`, `removeHook:setEntityState` in ox_lib;
- any resource constructing `lib.hook:new(event, filter)` dynamically exposes
  `registerHook:<event>` and `removeHook:<event>`.

qblib gap: no export names above under resource identity `ox_lib`; its flattened
exports are `<QBmodule>_<function>`, and several related functions have
incompatible arguments/returns.

## 3. Wire/runtime side effects (P0)

Preserve these names and payloads because third-party resources can use them
without the init import:

- callback validation/request/response: `ox_lib:validateCallback` and
  `__ox_cb_<callbackOrResource>`;
- notifications: client events `ox_lib:notify`, `ox_lib:defaultNotify`,
  `ox_lib:alertDialog`; server-side imported `lib.notify` targets the
  consumer-specific `__ox_notify_<consumerResource>` event;
- UI NUI callback names: `getConfig`, `init`, `closeAlert`, `openContext`,
  `clickContext`, `closeContext`, `inputData`, `confirmSelected`,
  `changeIndex`, `changeSelected`, `changeChecked`, `closeMenu`,
  `progressComplete`, `radialClick`, `radialBack`, `radialClose`,
  `radialTransition`, `skillCheckOver`;
- state/entity: `ox_lib:setStateBagValue`, `ox_lib:setVehicleProperties`,
  state keys `ox_lib:setVehicleProperties`, `ox_entity_setonground`;
- progress props: server event `ox_lib:progressProps`, player state key
  `lib:progressProps`, client cleanup event `onPlayerDropped`;
- locale: local event `ox_lib:setLocale`, global state `ox_lib:locales`;
- developer tool: restricted `/zone` command and `ox_lib:saveZone` server event
  appending to `created_zones.lua` after `command` ACE validation;
- commands/settings: `/cancelprogress` and keymap X, `/ox_lib` settings command,
  radial keymap Z, `chat:addSuggestion(s)` and `chat:removeSuggestion` flows;
- optional txAdmin event consumers gated by `ox:txAdminNotifications` and
  `txAdmin-hideDefault*` convars.

## 4. Callback contract (P0)

Client:

- `lib.callback(event, delay:number|false|nil, cb, ...)`;
- `lib.callback.await(event, delay, ...) -> ...`;
- `lib.callback.register(name, cb)`; callback receives request args.

Server:

- `lib.callback(event, playerId, cb, ...)`;
- `lib.callback.await(event, playerId, ...) -> ...`;
- `lib.callback.register(name, cb)`; callback receives `source` first.

Behavior: client delay throttles per event and silently returns nil while still
cooling down. Request keys are randomized; server validates target existence.
Default timeout is convar `ox:callbackTimeout` (300000 ms). Missing callback
rejects/errors with `callback '<name>' does not exist`; timeout rejects with
`callback event '<key>' timed out`. Handler runs under `pcall`; errors are
printed with stack trace and respond `false`. Multiple return values are
preserved. Callback names have one owning resource and are cleared on stop.

qblib gap: related promise/export system uses different event names,
signatures, timeout messages, ownership/overwrite rules, handshake token,
throttling behavior, and same-VM vs export return mode. Do not alias names
without an ox-protocol adapter.

## 5. UI exports and schemas (P0/P1)

All UI calls are singleton/registry state in the ox_lib resource. Exact NUI
message names and focus transitions are observable and require ox-compatible
web assets or a complete qblib renderer adapter.

### Alert

`alertDialog({header, content, centered?, size?:xs|sm|md|lg|xl, overflow?,
cancel?, labels?:{cancel?,confirm?}}, timeout?) -> 'cancel'|'confirm'|nil`.
Concurrent call returns nil. Timeout invokes close with reason `timeout`, which
rejects the awaiting promise. `closeAlertDialog(reason?)` does nothing if none;
reason rejects, absent reason resolves nil. `content` is markdown-capable.

### Input

`inputDialog(heading, rows, {allowCancel?,size?}?) -> positional array|nil`;
concurrent call returns nil. String rows normalize to input rows without
mutating caller data. `closeInputDialog()` resolves nil.

Row types and options:

- common: `type,label,description?,placeholder?,default?,icon?,iconColor?,
  disabled?,required?`;
- `input`: `password?, min?, max?` (length);
- `textarea`: `autosize?,min?,max?,minLength?,maxLength?`;
- `number`: `precision?,min?,max?,step?`;
- `checkbox`: `checked?` and returns boolean;
- `select|multi-select`: `options[{value,label?}]`, `clearable?`,
  `searchable?`, `maxSelectedValues?`; multi returns array;
- `slider`: `min?,max?,step?`, defaults value to default/min/0;
- `color`: `format=hex|hexa|rgb|rgba|hsl|hsla`, returns string;
- `date|date-range`: `format?,returnString?,clearable?,min?,max?`; default
  accepts ISO/date-like value or `true` for now; returns millisecond timestamp
  (or pair) unless `returnString`;
- `time`: `format='12'|'24'`, `clearable?`, returns millisecond timestamp.

### Context menu

`registerContext(context|context[])`; schema `{id,title,menu?,onExit?,onBack?,
canClose?,options}`. Options may be array or keyed map and support `{title,
menu?,icon?,iconColor?,image?,progress?,arrow?,description?,metadata?,disabled?,
readOnly?,event?,serverEvent?,args?,onSelect?}`. `showContext(id)` errors when
unknown, `getOpenContextMenu()->id?`, `hideContext(onExit?)`. Selection closes,
then invokes `onSelect(args)`, `TriggerEvent(event,args)`, and/or
`TriggerServerEvent(serverEvent,args)`. Back calls `onBack`; explicit close can
call `onExit`. The bridge renders this as `openMenu` with
`presentation='panel'`; when `menu` identifies a parent it also sends
`back=true`. Clicking the panel header control emits the authenticated live
event `back` instead of inserting a synthetic selectable row. Parent/child
navigation sends an authenticated `updateMenu` envelope with the complete next
panel payload, retaining the same mounted request and avoiding transition
flicker.

### List menu

`registerMenu({id,title,options,position?,disableInput?,canClose?,onClose?,
onSelected?,onSideScroll?,onCheck?}, cb?)`; option `{label,progress?,
colorScheme?,icon?,iconColor?,values?,checked?,description?,defaultIndex?,args?,
close?}`. `showMenu(id,startIndex?)` errors for unknown/empty. Callback indices
are 1-based. Confirm callback is `(selected,scrollIndex?,args?,checked?)`.
`setMenuOptions(id, option|options, index?)`, `hideMenu(onExit?)`,
`getOpenMenu()->id?`. Side-scroll/select/check callback shapes must match
upstream, including `args` table validation and mutation used for checked rows.
The bridge uses `presentation='panel'`, which is compact and non-modal and does
not filter options from hidden text input; qblib's default searchable dialog is
not changed.

### Radial

`registerRadial({id,items})`, `showRadialMenu(id)`, `getCurrentRadialId()`,
`hideRadial()`, `disableRadial(bool)`, `addRadialItem(item|items,parentId?)`,
`removeRadialItem(id,parentId?)`, `clearRadialItems()`.

Item requires `id` only for global items and supports `{icon,label,menu?,
onSelect?:function|stringExport,keepOpen?,iconWidth?,iconHeight?,...}`.
Submenus/history, replacement by id, current refresh, root/global distinction,
resource ownership, string export callback `(currentMenu,itemIndex)`, 1-based
selection, focus/control blocking, and cleanup of stopped-resource global
items are observable.

### Notify

`notify({id?,title?,description?,duration?,showDuration?,position?,type?,style?,
icon?,iconAnimation?,iconColor?,alignIcon?,sound?})`; positions are top,
top-right, top-left, bottom, bottom-right, bottom-left, center-right,
center-left; types info/warning/success/error; icon animations spin,
spinPulse,spinReverse,pulse,beat,fade,beatFade,bounce,shake. `id` replaces/dedups
the toast. Sound is stripped from NUI and played frontend, gated by user KVP.
`defaultNotify` maps `status` to `type` and `inform` to `info`.

### Progress

`progressBar(data)` and `progressCircle(data)` return `true` complete,
`false` cancelled/interrupted, or nil when disallowed at start. They serialize:
later calls wait while one is active. `cancelProgress()` errors if inactive;
`progressActive()` returns `true` while active and `nil` while inactive.

Data: `{duration(required),label?,position?:middle|bottom,useWhileDead?,
allowRagdoll?,allowCuffed?,allowFalling?,allowSwimming?,canCancel?,anim?,prop?,
disable?}`. Anim supports dict+clip fields or scenario. Prop is one or array of
`{model,bone?,pos,rot,rotOrder?}`. Disable supports move/sprint/car/combat/mouse.
It sets/restores `LocalPlayer.state.invBusy`, validates object model dimensions
and type, caps replicated remote props via `ox:progressPropLimit` (2), cleans
animation/props, and applies a 100 ms completion tolerance.

### Skill check, text UI, clipboard/focus

- `skillCheck(difficulty|difficulty[], inputs?) -> boolean?`; difficulty is
  easy/medium/hard or `{areaSize,speedMultiplier}`; concurrent call returns
  nil. `cancelSkillCheck()` errors inactive; `skillCheckActive()->boolean`.
- `showTextUI(text,{position?,icon?,iconColor?,style?,alignIcon?}?)`; same text
  is a no-op even if options changed. `hideTextUI()` always sends hide;
  `isTextUIOpen()->boolean,text?`.
- `setClipboard(string)` ignores non-string and sends NUI copy message.
- `setNuiFocus(allowInput?,disableCursor?)` means focus true with cursor unless
  disabled, optionally KeepInput; `resetNuiFocus()` clears focus/keep-input.

qblib gaps: it has related NUI functions but different one-shot vs registry
models, return shapes, singleton behavior, callback timing/indexing, schemas,
focus ownership, events/messages, error semantics, styling/icons/markdown,
date/time/color fields, progress circle and remote prop replication. Existing
qbinventory ox adapter is only a narrow consumer adapter, not parity.

## 6. Shared collections/classes (P1)

These must be consumer-local to preserve methods/metatables.

- `lib.class(name, super?)`: class table with `:new(...)`, `:isClass(class)`,
  `:instanceOf(class)`, constructor/super chaining, private fields guarded by
  call-stack class access; errors on bad name/super and non-hash tables.
- `lib.array:new(...)`, `array:from(iter)`, `:at`, `:merge`, `:every`, `:fill`,
  `:filter`, `:find`, `:findIndex`, `:indexOf`, `:forEach`, `:includes`, `:join`,
  `:map`, `:pop`, `:push`, `:reduce`, `:reverse`, `:shift`, `:slice`,
  `:toReversed`, `:unshift`, `array.isArray`. Non-numeric assignment errors;
  new-array methods return Array objects; indexing is 1-based and negative
  indexing follows the upstream formulas.
- insertion-ordered `lib.map:new(initial?)`: `set,get,has,delete,size,isEmpty,
  clear,entries/each,keys,values,toTable,toArray`; supports `#`, `pairs`,
  msgpack and JSON; nil keys/values error.
- insertion-ordered `lib.set:new(...)`: `add,remove,has,size,isEmpty,clear,each,
  toArray,union,intersection,difference,equals,isSubsetOf`; supports #,
  pairs/ipairs, msgpack/JSON; nil add is ignored.
- `lib.heap:new(comparator?)`: `push,pop,peek,size,isEmpty,clear,drain`, `#`;
  min-heap by default; push returns self; drain returns Array.
- `lib.lru:new(positiveIntegerCapacity)`: `get` promotes, `peek` does not,
  `set` returns evicted key/value when over capacity, `has,delete,size,capacity,
  clear,each`; `pairs` and `#`; iteration newest to oldest.
- `lib.ringbuffer:new(positiveIntegerCapacity)`: `push` returns overwritten
  value, `get` positive from oldest/negative from newest, `size,capacity,isFull,
  isEmpty,clear,each,toArray`; `pairs`/`#`; invalid non-integer index errors.
- `lib.selector:new(weightedSets)`: set is array of `{weight,value}` or keyed
  sets; validates nonnegative weights/nonempty arrays; methods `getRandom`,
  `getRandomWeighted`, `getRandomAmount`, `getRandomWeightedAmount`, `getSet`,
  `getAllSets`, `addSet`, `updateSet`, `removeSet`; returned tables deep-cloned.
- `lib.uuid.generate()->lowercase UUID v7`: first six bytes encode current Unix
  time in milliseconds, version nibble is 7, and the RFC variant high bit is
  set; `lib.uuid.validate(str)->boolean` validates the 36-character hex/hyphen
  form plus version and variant.
- `require 'modules.DataView'`: `DataView:new(length)` with blob, length,
  zero-based relative offsets and `cangrow`; getters/setters for Int/Uint
  8/16/32/64, Float32/64, LuaInt/UluaInt/LuaNum, null-terminated String;
  endian boolean; setters chain and error when forbidden growth occurs.

qblib gap: all are missing; `QB.util.weightedChoice` and deepClone are isolated
helpers, not substitute contracts.

## 7. Shared primitive/library extensions (P1)

- `lib.string` is the global string table extended with `random(pattern,
  length?)`, `capitalize`, `startsWith`, `endsWith`, `contains(plain default
  true)`, `isBlank`, `escapePattern`, `replace(plain default true)`.
- `lib.math` is the global math table extended with `toscalars`, `tovector`,
  `normaltorotation`, `torgba`, `hextorgb`, `tohex`, `groupdigits`, `clamp`,
  `interp`, `lerp`, `round`. `lerp` returns a per-frame iterator yielding
  `(value,factor)` from 0 to 1 and supports number/vector/table.
- `lib.table` is the global table library extended with `contains`, `matches`,
  `deepclone`, mutating recursive `merge` (adds duplicate numbers by default),
  mutating `shuffle`, `map`, `freeze`, `isfrozen`; import also overrides global
  `rawset` so frozen tables reject writes.
- `lib.print.{error,warn,info,verbose,debug}` obeys resource/global
  `ox:printlevel[:resource]`, formats tables as sorted indented JSON, and tracks
  convar changes when supported.
- `lib.waitFor(cb, errMessage?, timeout=1000)` returns first non-nil result,
  yields per frame, errors with elapsed time; `timeout=false` waits forever.
- `lib.timer(time,onEnd?,async?)` constructs and immediately starts OxTimer;
  methods `start,run,forceEnd(triggerOnEnd),pause,play,isPaused,restart,
  getTimeLeft(ms|s|m|h|nil)`; sync start blocks, async spawns; time values round
  to 2 decimals.
- `lib.require(name)`, global `require`, `lib.load(path,env?)`,
  `lib.loadJson(path)`: ox dotted module resolution/caching/circular detection,
  `@resource.module` access, relative requires derived from caller source,
  `.lua`/`init.lua` candidates, multi-return caching semantics and informative
  search errors must match upstream. qblib's require accepts a different
  `resource, paths` API and different path grammar/cache semantics.

## 8. Locale (P1)

Import defines global `locale(key,...)`, `lib.locale(key?)`, `lib.getLocales()`,
`lib.getLocale(resource,key)`, and consumer export `getLocale`. It reads
consumer metadata `locales_path` (default `locales`), always loads/merges
English first, recursively flattens nested keys to dot notation, resolves
`${other.key}` substitutions, and uses `string.format` for call arguments.
Missing translation returns the key itself. Cross-resource import warns on
overwrite/missing. `ox_lib:setLocale` reloads.

Resource-side client locale is user-KVP aware (`ox:userLocales`, `ox:locale`),
server key is convar `ox:locale`; ox_lib publishes the list of locale code/label
pairs to `GlobalState['ox_lib:locales']`. Settings KVPs include locale,
notification position and notification audio.

qblib locale differs in convar names, Lua-file support, lookup/interpolation,
language catalog, KVP/UI flow, flattening/substitution, and exported/global API.

## 9. Grid, points, zones (P1)

`lib.grid` public surface: `getCellPosition(point)->x,y`, `getCell(point)`,
`getNearbyEntries(point,filter?)`, `addEntry(entry)`, `removeEntry(entry)`.
Its fixed map bounds are X -3700..4500 split into 34 cells and Y -4400..8000
split into 50 cells. Entries require `coords` and either `radius` or
`length,width`; radius becomes diameter for both extents. Nearby returns an
Array, deduplicated across overlapping cells, and caches by cell bounds plus
filter function identity. These details and entry ordering are observable;
copy upstream unless tested equivalently.

`lib.points.new(data)` or legacy `(coords,distance,data?)` returns mutable point
with `id,coords,distance,radius,currentDistance?,isClosest?,inside?,remove()` and
arbitrary caller fields. Every 300 ms it updates membership/closest and calls
`onEnter(self)`, `onExit(self)`; `nearby(self)` runs every frame while nearby.
`getAllPoints`, `getNearbyPoints`, `getClosestPoint`, deprecated `closest`.
Coordinates normalize to vec3. Removal clears grid and closest. Registries are
consumer-local.

`lib.zones.poly/box/sphere(data)->CZone`; common callback fields `onEnter`,
`onExit`, `inside`, debug/debugColour and arbitrary data. Returned object has
`id,__type,coords,distance,radius,insideZone,remove,contains(coords,
updateDistance?),setDebug(enable?,colour?)`. Getters: `getAllZones`,
`getCurrentZones` (client; keyed by id), `getNearbyZones` (Array). Membership
polls at 300 ms, `inside` runs each frame, and enter/exit ordering sorts by
distance. Server constructs/geometrically tests zones but has no callbacks.

Geometry:

- poly copies/normalizes points, forces non-planar points to a modal/average Z,
  defaults thickness 4, centers thickness around polygon plane, and contains
  via `glm.polygon.contains(..., thickness/4)`; radius is max centroid distance;
- box defaults full size vec3(2), internally halves it, supports number/vector/
  quaternion-compatible rotation, centers vertical thickness;
- sphere defaults radius 2 and uses strict `< radius` (boundary excluded).

qblib zones differ: export-owned shared registry rather than consumer-local
registry; handles use `type` not `__type`, methods/fields/getter return shapes
differ; point is a sphere alias; polygon default vertical extrusion starts at
the lowest point instead of centered planar thickness; callback cadence/order,
arbitrary field preservation and GLM rotation/planarity differ.

## 10. Raycast/world helpers (P1)

`lib.raycast.fromCoords(coords,destination,flags=511,ignore=4)` and
`fromCamera(flags=511,ignore=4,distance=10)` / deprecated `cam` block until
shape test settles and return exactly `(hit, entityHit, endCoords,
surfaceNormal, materialHash)`. The fourth native argument is the shape-test
option/ignore mode; entity ignored is always `cache.ped` in the LOS probe.

qblib is incompatible: fromCamera order `(distance,flags,ignoreEntity)`, uses a
different native/default flags, treats ignore as entity, has a timeout, drops
material, and returns `(hit,coords,entity,normal)` with nils on miss.

Nearby/closest defaults use strict distance `< 2.0`:

- closest object/ped/vehicle -> `(handle,coords)`; peds exclude players;
  vehicle excludes `cache.vehicle` on client unless include flag;
- client closest player -> `(playerId,ped,coords,vehicle)`; server ->
  `(serverId,ped,coords)` with optional ignored server id;
- nearby arrays: object `{object,coords}`, ped `{ped,coords}`, vehicle
  `{vehicle,coords}`, player `{id,ped,coords,vehicle?}`; client can include self;
- in-vehicle player coordinates use entity bone 0 on client;
- `getRelativeCoords` supports (vec3,heading,offset), (vec4,offset), or
  (vec3,rotationVec3,offset), preserving vec4 heading.

qblib `QB.closest/world` uses different options/filtering, defaults and return
shapes. Thin exact adapters are possible but must preserve strict boundary and
vector types.

## 11. Streaming/animation/controls/rendering (P1/P2)

Client imports:

- `streamingRequest(request,hasLoaded,assetType,asset,timeout=30000,...)`;
- `requestModel(model,timeout?) -> hash` (hashes strings, validates);
- `requestAnimDict`, `requestAnimSet`, `requestNamedPtfxAsset`,
  `requestStreamedTextureDict` -> same string;
- `requestWeaponAsset(weapon,timeout?,resourceFlags=31,componentFlags=0)`;
- `requestAudioBank(bank,timeout=30000)`;
- `requestScaleformMovie(name,timeout default waitFor 1000)->handle`;
- `playAnim(ped,dict,name,blendIn=8,blendOut=-8,duration=-1,flags=0,
  startPhase=0,phaseControlled=false,controlFlags=0,overrideCloneUpdate=false)`
  requests dict, plays, removes dict.

All requests return synchronously after yielding; invalid input/load timeout
raises an error. qblib `QB.stream.*` is callback-oriented with different
timeouts/failure values, so exact wrappers are required.

`lib.disableControls` is callable each frame and has capitalized
`:Add(...ids|table)`, `:Remove(...)` with reference counts, and `:Clear(...)`;
qblib's lease-based control API is intentionally different.

`lib.addKeybind(data)->CKeybind` retains caller fields and adds `hash`, dynamic
`currentKey`, boolean `disabled` and `isPressed`, plus methods
`getCurrentKey()`, `isControlPressed()`, and `disable(toggle)`. Data requires
`name,description` and supports `defaultMapper='keyboard'`, `defaultKey=''`,
`secondaryMapper?`, `secondaryKey?`, `disabled?`, `allowInPauseMenu?`,
`onPressed(self)?`, and `onReleased(self)?`. It registers `+name`/`-name`
commands and primary/secondary key mappings, blocks callbacks in the pause
menu unless allowed, and removes chat suggestions after 500 ms. qblib's
related handle uses different property/method names (`isPressed()` function,
`getCurrentBinding`) and has different pause/release/error/cleanup behavior.

`lib.marker.new(options)->marker`; defaults type 0, width 2, height 1, orange
RGBA, zero rotation/direction and boolean flags false. String MarkerType names
map to: `UpsideDownCone`, `VerticalCylinder`, `ThickChevronUp`, `ThinChevronUp`,
`CheckeredFlagRect`, `CheckeredFlagCircle`, `VerticleCircle`, `PlaneModel`,
`LostMCTransparent`, `LostMC`, `Number0` through `Number9`, `ChevronUpx1`
through `ChevronUpx3`, `HorizontalCircleFat`, `ReplayIcon`,
`HorizontalCircleSkinny`, `HorizontalCircleSkinny_Arrow`,
`HorizontalSplitArrowCircle`, `DebugSphere`, `DollarSign`, `HorizontalBars`,
`WolfHead`, `QuestionMark`, `PlaneSymbol`, `HelicopterSymbol`, `BoatSymbol`,
`CarSymbol`, `MotorcycleSymbol`, `BikeSymbol`, `TruckSymbol`,
`ParachuteSymbol`, `Unknown41`, `SawbladeSymbol`, and `Unknown43` (values
0..43). `marker:draw()` forwards exact DrawMarker parameters.

`lib.dui:new({url,width,height,debug?})` exposes url/duiObject/duiHandle/
runtimeTxd/txdObject/dictName/txtName and methods `remove,setUrl,sendMessage,
sendMouseMove,sendMouseDown,sendMouseUp,sendMouseWheel`; all consumer-owned DUIs
are removed on consumer stop.

`lib.scaleform:new(name|details)` where details supports fullscreen/properties/
renderTarget. Methods `callMethod(name,args?,returnType?)`, `setFullScreen`,
`setProperties`, `setRenderTarget`, `isDrawing`, `draw`, `startDrawing`,
`stopDrawing`, `dispose`; argument conversion and boolean/integer/string returns
are exact. qblib only loads raw scaleform handles.

## 12. Entity/player/vehicle classes and properties (P1)

Class imports compose consumer-local objects:

- `gameEntity:new(handle)` fields `handle,netId,statebag,type`; methods
  `set(key,value,mode?)`, `setr`, `sets`, `get`, `has`, `keys`, `setHandle`,
  `getCoords,setCoords,getModel,getHeading,setHeading,getRoutingBucket,
  setRoutingBucket`;
- `ped` extends entity: `getArmour,setArmour`, realm-specific
  `ped.create(model,x,y,z,heading?,networked?,scriptHost?)`;
- `player:new(serverId|-1)` dynamically resolves client ped and has
  `setModel,getRoutingBucket,setRoutingBucket`;
- `prop` extends entity: realm-specific `create`, `setOnGround`;
- `vehicle` extends entity: realm-specific `create` (server requires type),
  `getType,getPlate,setPlate,setOnGround`.

Replicated/synced state writes respect `sv_stateBagStrictMode`; client writes
request server authorization through `ox_lib:requestSetStateBag`. Mode 2 only
supports players. The ox resource installs filterable setPlayerState/
setEntityState hook pipelines and default validators for vehicle-property clear
and on-ground operations.

Vehicle property export schema is not QBCore's schema. It includes:

`model,plate,plateIndex,lockState,bodyHealth,engineHealth,tankHealth,fuelLevel,
oilLevel,dirtLevel,paintType1,paintType2,color1,color2,pearlescentColor,
interiorColor,dashboardColor,wheelColor,wheelWidth,wheelSize,wheels,windowTint,
xenonColor,neonEnabled,neonColor,extras,tyreSmokeColor,modSpoilers,
modFrontBumper,modRearBumper,modSideSkirt,modExhaust,modFrame,modGrille,modHood,
modFender,modRightFender,modRoof,modEngine,modBrakes,modTransmission,modHorns,
modSuspension,modArmor,modNitrous,modTurbo,modSubwoofer,modSmokeEnabled,
modHydraulics,modXenon,modFrontWheels,modBackWheels,modCustomTiresF,
modCustomTiresR,modPlateHolder,modVanityPlate,modTrimA,modOrnaments,
modDashboard,modDial,modDoorSpeaker,modSeats,modSteeringWheel,
modShifterLeavers,modAPlate,modSpeakers,modTrunk,modHydrolic,modEngineBlock,
modAirFilter,modStruts,modArchCover,modAerials,modTrimB,modTank,modWindows,
modDoorR,modLivery,modRoofLivery,modLightbar,livery,windows,doors,tyres,
bulletProofTyres,driftTyres`.

Critical representations: colors may be palette number or RGB array; extras
are 0 enabled / 1 disabled; windows and doors are arrays of damaged indices;
tyres maps wheel id to 1/2 burst state; get rounds health/fuel/oil/dirt;
`bulletProofTyres` follows upstream native result semantics. Client set applies
and optionally fixes vehicle, statebag handler validates entity ownership;
server set writes the `ox_lib:setVehicleProperties` entity state key.

qblib vehicle schema differs (boolean extras, intact/broken maps, tireHealth/
tireBurstState/tireBurstCompletely, liveryRoof naming, custom xenon RGB, missing
lock/paint/nitrous/subwoofer/hydraulics/drift fields). Never pass snapshots
through unchanged; implement lossless ox normalization.

## 13. Hooks, cron, commands, logging, ACL/version (P1/P2)

Hooks:

- `lib.hook:new(event,filter?)` owns ordered hooks and creates dynamic exports;
- `registerHook(cb?,options?)->hookId`, `remove(resource,hookId?)`,
  `dispatch(payload)->to-be-closed {ok,size}`;
- filter/callback returning false rejects; dispatch records post-hook event ids;
  closing the result marks failure on error and triggers each event with
  `(ok,payload)`;
- `lib.registerHook('resource:event',handler?|options,options?)->EventHook`;
  handle has `on(handler)`, `off()`, `remove()` and uses exported hook registry.

Cron: server `lib.cron.new('minute hour day month weekday',job,options?)` parses
wildcard, number, comma lists, ranges, steps, weekday short names. Returned
OxTask fields include expression/id/job/isActive/debug/lastRun/maxDelay (default
1 second) and methods `getNextTime,getAbsoluteNextTime,getTimeAsString,
scheduleTask,run,stop`. Job receives `(task,currentDate)`. Built-in midnight job
revives stopped/dead tasks.

Commands: server `addCommand(name|string[], properties|false, cb, ...)` supports
properties `help,params,restricted`; params `name,help?,type? number|playerId|
string|longString,optional?`. Named parsed args replace numeric slots. Restricted
boolean/string/string[] installs ACEs and native restriction. Errors trace and
do not propagate. Deprecated pre-v3 syntax routes to `__addCommand`. Client
ox_lib wraps global `RegisterCommand` so `restricted=true` checks
`command.<name>` by callback before execution.

`triggerClientEvent(event,target|Array,...)` msgpacks once and dispatches
internal events. `getFilesInDirectory(path,pattern)->files,count` supports
resource-relative or `@` absolute path. `logger(source,event,message,...)`
batches 500 ms and supports convar-selected datadog/fivemanage/loki providers,
color stripping and player identifier tags. Logger convars are `ox:logger`,
`ox:logger:hostname`, `datadog:key`, `datadog:site`, `fivemanage:key`,
`fivemanage:dataset`, `loki:user`, `loki:password` (fallback `loki:key`),
`loki:endpoint`, and `loki:tenant`; expected HTTP success codes are 202, 200,
and 204 respectively.

ACL exports map numeric principal to `player.<id>` and execute add/remove ACE
and principal commands. `checkDependency(resource,minSemver,print?)` returns
true or `false,msg` / prints. `versionCheck(repo)` asynchronously checks the
latest GitHub release and prints only an upgrade. Preserve semver comparison
and delayed/no-op failure behavior.

## 14. Implementation partitions and acceptance gates

P0-A bootstrap/resource (one owner): actual `ox_lib` resource, upstream
manifest/file list, built NUI assets, startup/loader/globals, all direct exports.
Gate: a foreign fixture with only `shared_script '@ox_lib/init.lua'` loads in
both realms and sees correct globals; direct `exports.ox_lib:*` names enumerate.

P0-B callback/cache/protocol (one owner): exact callback validation and
multi-return paths, cache events/false sentinels/onCache, notification server
bridge. Gate: two fixture resources exercise ownership, missing callback,
timeout, throttle, multi-return, errors, player callbacks and resource stops.

P0-C UI (one owner): upstream-compatible web build and all UI export schemas,
singletons, focus, registry lifecycles, progress remote props. Gate: NUI contract
tests assert every action/callback payload plus cancel/timeout/concurrency.

P1-A local primitives (one owner): class, array/map/set/heap/LRU/ringbuffer,
selector, DataView, string/math/table, require, waitFor, timer, print, UUID.
Gate: run copied/ported upstream semantic tests inside two isolated consumer
environments to detect leaked caches/metatables.

P1-B spatial/rendering (one owner): grid/points/zones, raycast, nearby/closest,
relative coords, marker/DUI/scaleform, controls, streaming/animation. Gate:
native mocks verify exact argument order/defaults, 1/300 ms scheduling,
boundary geometry, five-value ray returns, errors/timeouts, cleanup.

P1-C entities/vehicle/hooks (one owner): entity classes/create methods,
state-write authorization, hook pipelines, complete vehicle property schema.
Gate: strict-mode on/off, client/server ownership and all property round trips.

P2 server/tooling (one owner): cron, command/ACE, triggerClientEvent,
directory/logger/version, locale settings/catalog, txAdmin, zone creator.
Gate: cron parser/date fixtures; commands/ACE/event payload fixtures; no real
network dependency in tests.

Cross-cutting release gates:

1. Compare `rg --files` under pinned upstream `imports`, `resource`, `modules`,
   `locales`, and web build against shim; every omission must be intentional and
   tested. For literal parity, `diff -qr` should be empty except manifest
   metadata/branding changes that do not affect runtime.
2. Enumerate direct exports in client and server and compare to section 2.
3. Run qblib's full smoke suite and every qbcore2 consumer suite after adding
   aliases/adapters; existing `QB.*` contracts must remain unchanged.
4. Add external black-box fixtures using only documented ox syntax—never
   loading qblib directly—including manifest eager imports.
5. Preserve upstream LGPL-3.0 `LICENSE`, `NOTICE.md`, source headers, and make
   modified source available.

## 15. Live workspace delta observed during audit

At audit time a concurrently-created `resources/[test]/ox_lib` tree existed.
Every file it contained compared byte-for-byte with the pinned upstream
version. It had most `imports/`, `modules/DataView`, and non-client-interface
resource scripts, but initially lacked:

- `fxmanifest.lua`;
- all `web/build/**` (therefore `hasLoaded()` fails);
- `resource/settings.lua`;
- `resource/locale/client.lua`, `resource/locale/server.lua`;
- every `resource/interface/client/*.lua` (all UI exports);
- `resource/zoneCreator/client.lua`, `resource/zoneCreator/server.lua`.

Re-run the file-list diff after concurrent agents finish; this observation is a
point-in-time snapshot, not ownership of those edits.
