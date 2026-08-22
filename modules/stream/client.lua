---Generic request -> poll-until-loaded -> callback -> cleanup driver shared by
---every `QB.stream.load*` function, including `loadModel`. Skips the request
---if already loaded, polls with an exponential backoff up to a 10s timeout.
---Cleanup runs on the failure path and right after a callback returns; when
---called WITHOUT a callback the asset is deliberately left loaded and the
---caller owns releasing it -- see each public function's doc comment for the
---auto-cleanup timing tradeoff this implies.
---@param request fun(key: any): any Streaming request native. Its return value becomes `identifier` when `identifierFromRequest` is true; otherwise it's called for its side effect and `key` is used as `identifier`.
---@param hasLoaded fun(identifier: any): boolean Poll predicate, called with `identifier`.
---@param remove fun(identifier: any): nil Cleanup native, called with `identifier`.
---@param key any Value passed into `request`, and the identifier for `hasLoaded`/`remove` unless `identifierFromRequest` is set.
---@param cb? fun(identifier: any): nil Optional callback invoked once loaded, before cleanup.
---@param identifierFromRequest? boolean Set true when `request`'s return value (not `key`) is what `hasLoaded`/`remove` expect -- required for scaleform movie handles.
---@return any | false identifier `key`, or the value returned by `request` when `identifierFromRequest` is set, or false if it never loaded.
---@return string? error
local function loadStreamingAsset(request, hasLoaded, remove, key, cb, identifierFromRequest)
    local identifier = key

    if identifierFromRequest then
        identifier = request(key)
    elseif not hasLoaded(identifier) then
        request(key)
    end

    if not hasLoaded(identifier) then
        local ok, err = QB.loops.controlled(function()
            if hasLoaded(identifier) then return true end
        end, false, 10000, true)

        if not ok then
            remove(identifier)
            return false, err
        end
    end

    if cb then
        local success, cbErr = pcall(cb, identifier)
        remove(identifier)
        if not success then error(cbErr, 2) end
    end

    return identifier
end

---@param model string | number The model to be loaded.
---@param cb? fun(model: number) : nil You can pass a callback function. An example would be to create a ped. Then the model will automatically clean up afterwards.
---@return number | false model The loaded model hash, or false if it never loaded.
---@return string? error
function QB.stream.loadModel(model, cb)
    if type(model) == "string" then model = joaat(model) end
    assert(IsModelValid(model), ("Invalid model: %s"):format(model))

    return loadStreamingAsset(RequestModel, HasModelLoaded, SetModelAsNoLongerNeeded, model, cb)
end

---Loads a named particle effect (ptfx) asset, runs an optional callback, then
---releases it immediately afterwards -- effects that must keep playing beyond
---the callback's synchronous scope should not be requested this way.
---@param fxName string The particle effect asset name.
---@param cb? fun(fxName: string) : nil Optional callback run once loaded; asset is released right after it returns.
---@return string | false fxName The loaded asset name, or false if it never loaded.
---@return string? error
function QB.stream.loadPtfx(fxName, cb)
    assert(type(fxName) == "string", ("Invalid ptfx asset name: %s"):format(fxName))
    return loadStreamingAsset(RequestNamedPtfxAsset, HasNamedPtfxAssetLoaded, RemoveNamedPtfxAsset, fxName, cb)
end

---Loads an animation dictionary, runs an optional callback, then releases it
---immediately afterwards -- anims that must keep playing beyond the
---callback's synchronous scope should not be requested this way.
---@param animDict string The animation dictionary to load.
---@param cb? fun(animDict: string) : nil Optional callback run once loaded; dict is released right after it returns.
---@return string | false animDict The loaded dictionary name, or false if it never loaded.
---@return string? error
function QB.stream.loadAnimDict(animDict, cb)
    assert(type(animDict) == "string", ("Invalid anim dict: %s"):format(animDict))
    assert(DoesAnimDictExist(animDict), ("Anim dict does not exist: %s"):format(animDict))
    return loadStreamingAsset(RequestAnimDict, HasAnimDictLoaded, RemoveAnimDict, animDict, cb)
end

---Loads an animation set, runs an optional callback, then releases it
---immediately afterwards -- see `loadAnimDict` for the auto-cleanup timing
---tradeoff this implies.
---@param animSet string The animation set to load.
---@param cb? fun(animSet: string) : nil Optional callback run once loaded; set is released right after it returns.
---@return string | false animSet The loaded set name, or false if it never loaded.
---@return string? error
function QB.stream.loadAnimSet(animSet, cb)
    assert(type(animSet) == "string", ("Invalid anim set: %s"):format(animSet))
    return loadStreamingAsset(RequestAnimSet, HasAnimSetLoaded, RemoveAnimSet, animSet, cb)
end

---Loads a clip set, runs an optional callback, then releases it immediately
---afterwards -- see `loadAnimDict` for the auto-cleanup timing tradeoff this
---implies.
---@param clipSet string The clip set to load.
---@param cb? fun(clipSet: string) : nil Optional callback run once loaded; set is released right after it returns.
---@return string | false clipSet The loaded clip set name, or false if it never loaded.
---@return string? error
function QB.stream.loadClipSet(clipSet, cb)
    assert(type(clipSet) == "string", ("Invalid clip set: %s"):format(clipSet))
    return loadStreamingAsset(RequestClipSet, HasClipSetLoaded, RemoveClipSet, clipSet, cb)
end

---Loads (activates) an interior proplist (IPL), runs an optional callback,
---then deactivates it again immediately afterwards -- IPLs that must stay
---active beyond the callback's synchronous scope (e.g. an interior that
---should remain visible) should not be loaded this way.
---@param iplName string The IPL to load.
---@param cb? fun(iplName: string) : nil Optional callback run once active; IPL is removed right after it returns.
---@return string | false iplName The loaded IPL name, or false if it never activated.
---@return string? error
function QB.stream.loadIpl(iplName, cb)
    assert(type(iplName) == "string", ("Invalid IPL: %s"):format(iplName))
    return loadStreamingAsset(RequestIpl, IsIplActive, RemoveIpl, iplName, cb)
end

---Loads a scaleform movie, runs an optional callback with its handle, then
---releases it immediately afterwards -- movies that must keep drawing beyond
---the callback's synchronous scope should not be requested this way.
---@param scaleformName string The scaleform movie to load.
---@param cb? fun(handle: number) : nil Optional callback run once loaded, receiving the scaleform handle; movie is released right after it returns.
---@return number | false handle The loaded scaleform handle, or false if it never loaded.
---@return string? error
function QB.stream.loadScaleformMovie(scaleformName, cb)
    assert(type(scaleformName) == "string", ("Invalid scaleform movie: %s"):format(scaleformName))
    return loadStreamingAsset(RequestScaleformMovie, HasScaleformMovieLoaded, SetScaleformMovieAsNoLongerNeeded, scaleformName, cb, true)
end

---Loads a streamed texture dictionary, runs an optional callback, then
---releases it immediately afterwards -- see `loadAnimDict` for the
---auto-cleanup timing tradeoff this implies.
---@param textureDict string The texture dictionary to load.
---@param cb? fun(textureDict: string) : nil Optional callback run once loaded; dict is released right after it returns.
---@param isAdditionalTextures? boolean Second argument forwarded to `RequestStreamedTextureDict`; Rockstar/FiveM do not document its exact effect. Defaults to false, matching common usage.
---@return string | false textureDict The loaded dictionary name, or false if it never loaded.
---@return string? error
function QB.stream.loadTextureDict(textureDict, cb, isAdditionalTextures)
    assert(type(textureDict) == "string", ("Invalid texture dict: %s"):format(textureDict))
    return loadStreamingAsset(function(dict)
        RequestStreamedTextureDict(dict, isAdditionalTextures or false)
    end, HasStreamedTextureDictLoaded, SetStreamedTextureDictAsNoLongerNeeded, textureDict, cb)
end

---Loads a script audio bank, runs an optional callback, then releases it
---immediately afterwards -- a bank whose sounds must keep playing beyond the
---callback's synchronous scope should not be requested this way.
---
---Unlike every other loader here there is no separate `Has...Loaded` native:
---`RequestScriptAudioBank` itself returns true once the bank is in memory, so
---it doubles as the poll predicate (which is why `loadStreamingAsset` calls
---`hasLoaded` before `request` -- an already-loaded bank short-circuits).
---@param audioBank string The audio bank to load, e.g. "DLC_HEIST_FLEECA_SOUNDSET".
---@param cb? fun(audioBank: string) : nil Optional callback run once loaded; bank is released right after it returns.
---@return string | false audioBank The loaded bank name, or false if it never loaded.
---@return string? error
function QB.stream.loadAudioBank(audioBank, cb)
    assert(type(audioBank) == "string", ("Invalid audio bank: %s"):format(audioBank))

    local function requestBank(bank)
        return RequestScriptAudioBank(bank, false)
    end

    return loadStreamingAsset(requestBank, requestBank, ReleaseNamedScriptAudioBank, audioBank, cb)
end

---Waits for world collision to stream in around `coords`, so a freshly
---teleported or spawned entity doesn't fall through unloaded map geometry.
---
---Deliberately NOT built on `loadStreamingAsset`: collision has no
---identifier-keyed request/has-loaded/release triad. `RequestCollisionAtCoord`
---must be re-issued on every poll (a single call is not sticky), readiness is
---reported for an *entity* rather than for the requested point, and there is
---no release native at all -- collision unloads on its own as the streamer
---moves on, so there is nothing to clean up and no callback-scoped lifetime.
---@param coords vector3 | {x: number, y: number, z: number} The point to stream collision around.
---@param cb? fun() : nil Optional callback run once collision is ready.
---@param entity? number Entity whose surroundings are checked (`HasCollisionLoadedAroundEntity`). Defaults to the local player's ped -- the usual case, where the ped has just been moved to `coords`.
---@return boolean success False if collision never finished loading.
---@return string? error
function QB.stream.loadCollision(coords, cb, entity)
    assert(coords and type(coords.x) == "number" and type(coords.y) == "number" and type(coords.z) == "number",
        "Invalid coords: expected a vector3 or {x, y, z} table.")

    entity = entity or PlayerPedId()

    local ok, err = QB.loops.controlled(function()
        RequestCollisionAtCoord(coords.x, coords.y, coords.z)
        return HasCollisionLoadedAroundEntity(entity)
    end, false, 10000, true)

    if not ok then
        return false, err
    end

    if cb then cb() end

    return true
end

---Loads a weapon's streaming asset (model/anims/etc), runs an optional
---callback, then releases it immediately afterwards -- see `loadAnimDict`
---for the auto-cleanup timing tradeoff this implies.
---@param weapon string | number The weapon name or hash to load assets for.
---@param cb? fun(weaponHash: number) : nil Optional callback run once loaded, receiving the weapon hash; asset is released right after it returns.
---@param weaponResourceFlags? integer Forwarded to `RequestWeaponAsset`; undocumented upstream, almost universally 31 in practice. Defaults to 31.
---@param extraWeaponComponentFlags? integer Forwarded to `RequestWeaponAsset`; undocumented upstream, almost universally 0 in practice. Defaults to 0.
---@return number | false weaponHash The loaded weapon hash, or false if it never loaded.
---@return string? error
function QB.stream.loadWeaponAsset(weapon, cb, weaponResourceFlags, extraWeaponComponentFlags)
    if type(weapon) == "string" then weapon = joaat(weapon) end
    assert(IsWeaponValid(weapon), ("Invalid weapon: %s"):format(weapon))

    return loadStreamingAsset(function(hash)
        RequestWeaponAsset(hash, weaponResourceFlags or 31, extraWeaponComponentFlags or 0)
    end, HasWeaponAssetLoaded, RemoveWeaponAsset, weapon, cb)
end
