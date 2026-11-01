---Generic request -> poll-until-loaded -> callback -> cleanup driver for every `Kora.stream.load*` function.
---Skips the request if already loaded and polls once per frame up to a 10s timeout. Cleanup runs on failure and
---after a callback returns; with NO callback the asset is left loaded and the caller must release it.
---@param request fun(key: any): any Streaming request native. Its return value becomes `identifier` when `identifierFromRequest` is true; otherwise it's called for its side effect and `key` is used as `identifier`.
---@param hasLoaded fun(identifier: any): boolean Poll predicate, called with `identifier`.
---@param remove fun(identifier: any): nil Cleanup native, called with `identifier`.
---@param key any Value passed into `request`, and the identifier for `hasLoaded`/`remove` unless `identifierFromRequest` is set.
---@param cb? fun(identifier: any): nil Optional callback invoked once loaded, before cleanup.
---@param identifierFromRequest? boolean Set true when `request`'s return value (not `key`) is what `hasLoaded`/`remove` expect -- required for scaleform movie handles.
---@param options? QBStreamLoadOptions
---@return any | false identifier `key`, or the value returned by `request` when `identifierFromRequest` is set, or false if it never loaded.
---@return string? error
local function loadStreamingAsset(request, hasLoaded, remove, key, cb, identifierFromRequest, options)
    assert(cb == nil or Kora.util.isCallable(cb), "Kora.stream callback must be callable.")
    assert(options == nil or type(options) == "table", "Kora.stream load options must be a table.")
    options = options or {}
    assert(options.timeout == nil or Kora.util.isInteger(options.timeout) and options.timeout >= 0,
        "Kora.stream timeout must be a non-negative integer.")
    assert(options.shouldContinue == nil or Kora.util.isCallable(options.shouldContinue),
        "Kora.stream shouldContinue must be callable.")

    local identifier = key

    if identifierFromRequest then
        identifier = request(key)
    elseif not hasLoaded(identifier) then
        request(key)
    end

    if not hasLoaded(identifier) then
        local cancelled = false
        local ok, err = Kora.loops.controlled(function()
            if options.shouldContinue and not options.shouldContinue() then
                cancelled = true
                return true
            end
            if hasLoaded(identifier) then return true end
        end, false, options.timeout or 10000, false)

        if cancelled or not ok then
            remove(identifier)
            return false, cancelled and "cancelled" or err
        end
    end

    if cb then
        local success, cbErr = pcall(cb, identifier)
        remove(identifier)
        if not success then error(cbErr, 2) end
    end

    return identifier
end

local function assertName(value, label)
    assert(type(value) == 'string' and value ~= '', ('Invalid %s: expected a non-empty string.'):format(label))
end

---@param model string | number The model to be loaded.
---@param cb? fun(model: number) : nil You can pass a callback function. An example would be to create a ped. Then the model will automatically clean up afterwards.
---@param options? QBStreamLoadOptions
---@return number | false model The loaded model hash, or false if it never loaded.
---@return string? error
function Kora.stream.loadModel(model, cb, options)
    if type(model) == "string" then
        assertName(model, 'model')
        model = joaat(model)
    end
    assert(Kora.util.isInteger(model), ("Invalid model: %s"):format(model))
    assert(IsModelValid(model), ("Invalid model: %s"):format(model))

    return loadStreamingAsset(RequestModel, HasModelLoaded, SetModelAsNoLongerNeeded, model, cb, false, options)
end

---Loads a named particle effect (ptfx) asset, runs an optional callback, then releases it.
---@param fxName string The particle effect asset name.
---@param cb? fun(fxName: string) : nil Optional callback run once loaded; asset is released right after it returns.
---@param options? QBStreamLoadOptions
---@return string | false fxName The loaded asset name, or false if it never loaded.
---@return string? error
function Kora.stream.loadPtfx(fxName, cb, options)
    assertName(fxName, 'ptfx asset name')
    return loadStreamingAsset(RequestNamedPtfxAsset, HasNamedPtfxAssetLoaded, RemoveNamedPtfxAsset, fxName, cb, false, options)
end

---Loads an animation dictionary, runs an optional callback, then releases it immediately afterwards.
---@param animDict string The animation dictionary to load.
---@param cb? fun(animDict: string) : nil Optional callback run once loaded; dict is released right after it returns.
---@param options? QBStreamLoadOptions
---@return string | false animDict The loaded dictionary name, or false if it never loaded.
---@return string? error
function Kora.stream.loadAnimDict(animDict, cb, options)
    assertName(animDict, 'anim dict')
    assert(DoesAnimDictExist(animDict), ("Anim dict does not exist: %s"):format(animDict))
    return loadStreamingAsset(RequestAnimDict, HasAnimDictLoaded, RemoveAnimDict, animDict, cb, false, options)
end

---Loads an animation set, runs an optional callback, then releases it.
---@param animSet string The animation set to load.
---@param cb? fun(animSet: string) : nil Optional callback run once loaded; set is released right after it returns.
---@param options? QBStreamLoadOptions
---@return string | false animSet The loaded set name, or false if it never loaded.
---@return string? error
function Kora.stream.loadAnimSet(animSet, cb, options)
    assertName(animSet, 'anim set')
    return loadStreamingAsset(RequestAnimSet, HasAnimSetLoaded, RemoveAnimSet, animSet, cb, false, options)
end

---Loads a clip set, runs an optional callback, then releases it.
---@param clipSet string The clip set to load.
---@param cb? fun(clipSet: string) : nil Optional callback run once loaded; set is released right after it returns.
---@param options? QBStreamLoadOptions
---@return string | false clipSet The loaded clip set name, or false if it never loaded.
---@return string? error
function Kora.stream.loadClipSet(clipSet, cb, options)
    assertName(clipSet, 'clip set')
    return loadStreamingAsset(RequestClipSet, HasClipSetLoaded, RemoveClipSet, clipSet, cb, false, options)
end

---Loads (activates) an interior proplist (IPL), runs an optional callback, then deactivates it.
---@param iplName string The IPL to load.
---@param cb? fun(iplName: string) : nil Optional callback run once active; IPL is removed right after it returns.
---@param options? QBStreamLoadOptions
---@return string | false iplName The loaded IPL name, or false if it never activated.
---@return string? error
function Kora.stream.loadIpl(iplName, cb, options)
    assertName(iplName, 'IPL')
    return loadStreamingAsset(RequestIpl, IsIplActive, RemoveIpl, iplName, cb, false, options)
end

---Loads a scaleform movie, runs an optional callback with its handle, then releases it.
---@param scaleformName string The scaleform movie to load.
---@param cb? fun(handle: number) : nil Optional callback run once loaded, receiving the scaleform handle; movie is released right after it returns.
---@param options? QBStreamLoadOptions
---@return number | false handle The loaded scaleform handle, or false if it never loaded.
---@return string? error
function Kora.stream.loadScaleformMovie(scaleformName, cb, options)
    assertName(scaleformName, 'scaleform movie')
    return loadStreamingAsset(RequestScaleformMovie, HasScaleformMovieLoaded, SetScaleformMovieAsNoLongerNeeded,
        scaleformName, cb, true, options)
end

---Loads a streamed texture dictionary, runs an optional callback, then releases it.
---@param textureDict string The texture dictionary to load.
---@param cb? fun(textureDict: string) : nil Optional callback run once loaded; dict is released right after it returns.
---@param isAdditionalTextures? boolean Second argument forwarded to `RequestStreamedTextureDict`; Rockstar/FiveM do not document its exact effect. Defaults to false, matching common usage.
---@return string | false textureDict The loaded dictionary name, or false if it never loaded.
---@return string? error
function Kora.stream.loadTextureDict(textureDict, cb, isAdditionalTextures)
    assertName(textureDict, 'texture dict')
    assert(isAdditionalTextures == nil or type(isAdditionalTextures) == "boolean",
        "Texture dictionary additional-textures flag must be a boolean.")
    return loadStreamingAsset(function(dict)
        RequestStreamedTextureDict(dict, isAdditionalTextures == true)
    end, HasStreamedTextureDictLoaded, SetStreamedTextureDictAsNoLongerNeeded, textureDict, cb)
end

---Loads a script audio bank, runs an optional callback, then releases it.
---There is no `Has...Loaded` native: `RequestScriptAudioBank` returns true once resident, so it doubles as the
---poll predicate (hence `loadStreamingAsset` calls `hasLoaded` before `request`).
---@param audioBank string The audio bank to load, e.g. "DLC_HEIST_FLEECA_SOUNDSET".
---@param cb? fun(audioBank: string) : nil Optional callback run once loaded; bank is released right after it returns.
---@return string | false audioBank The loaded bank name, or false if it never loaded.
---@return string? error
function Kora.stream.loadAudioBank(audioBank, cb)
    assertName(audioBank, 'audio bank')

    local function requestBank(bank)
        return RequestScriptAudioBank(bank, false)
    end

    return loadStreamingAsset(requestBank, requestBank, ReleaseNamedScriptAudioBank, audioBank, cb)
end

---Waits for world collision to stream in around `coords`, so a teleported or spawned entity doesn't fall through the map.
---Not built on `loadStreamingAsset`: `RequestCollisionAtCoord` must be re-issued every poll, readiness is
---reported per entity, and there is no release native.
---@param coords vector3 | {x: number, y: number, z: number} The point to stream collision around.
---@param cb? fun() : nil Optional callback run once collision is ready.
---@param entity? number Entity whose surroundings are checked (`HasCollisionLoadedAroundEntity`). Defaults to the local player's ped -- the usual case, where the ped has just been moved to `coords`.
---@return boolean success False if collision never finished loading.
---@return string? error
function Kora.stream.loadCollision(coords, cb, entity)
    assert(coords and Kora.util.isFiniteNumber(coords.x) and Kora.util.isFiniteNumber(coords.y) and Kora.util.isFiniteNumber(coords.z),
        "Invalid coords: expected a vector3 or {x, y, z} table.")
    assert(cb == nil or Kora.util.isCallable(cb), "Kora.stream callback must be callable.")
    assert(entity == nil or Kora.util.isInteger(entity), "Collision entity must be a finite integer.")

    if entity == nil then entity = PlayerPedId() end

    local ok, err = Kora.loops.controlled(function()
        RequestCollisionAtCoord(coords.x, coords.y, coords.z)
        return HasCollisionLoadedAroundEntity(entity)
    end, false, 10000, false)

    if not ok then
        return false, err
    end

    if cb then cb() end

    return true
end

---Loads a weapon's streaming asset, runs an optional callback, then releases it.
---@param weapon string | number The weapon name or hash to load assets for.
---@param cb? fun(weaponHash: number) : nil Optional callback run once loaded, receiving the weapon hash; asset is released right after it returns.
---@param weaponResourceFlags? integer Forwarded to `RequestWeaponAsset`; undocumented upstream, almost universally 31 in practice. Defaults to 31.
---@param extraWeaponComponentFlags? integer Forwarded to `RequestWeaponAsset`; undocumented upstream, almost universally 0 in practice. Defaults to 0.
---@return number | false weaponHash The loaded weapon hash, or false if it never loaded.
---@return string? error
function Kora.stream.loadWeaponAsset(weapon, cb, weaponResourceFlags, extraWeaponComponentFlags)
    if type(weapon) == "string" then
        assertName(weapon, 'weapon')
        weapon = joaat(weapon)
    end
    assert(Kora.util.isInteger(weapon), ("Invalid weapon: %s"):format(weapon))
    assert(IsWeaponValid(weapon), ("Invalid weapon: %s"):format(weapon))
    assert(weaponResourceFlags == nil or Kora.util.isInteger(weaponResourceFlags),
        "Weapon resource flags must be finite integers.")
    assert(extraWeaponComponentFlags == nil or Kora.util.isInteger(extraWeaponComponentFlags),
        "Weapon component flags must be finite integers.")

    return loadStreamingAsset(function(hash)
        RequestWeaponAsset(hash, weaponResourceFlags == nil and 31 or weaponResourceFlags,
            extraWeaponComponentFlags == nil and 0 or extraWeaponComponentFlags)
    end, HasWeaponAssetLoaded, RemoveWeaponAsset, weapon, cb)
end
