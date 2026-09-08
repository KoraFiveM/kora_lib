-- QB.sound -- frontend/world/entity sound playback with managed sound ids.
--
-- The reason this is a module and not three inlined natives: GTA's sound-id
-- pool is small and finite. GetSoundId() hands out a slot that stays claimed
-- until ReleaseSoundId(), and a script that allocates one per alert without
-- ever releasing will silently stop producing audio partway through a session
-- -- a bug that looks like "the dispatch sound randomly stopped working" and
-- is near-impossible to trace back. Every id allocated here is auto-released
-- on a timer, released early by QB.sound.stop, and swept when the owning
-- resource stops.
--
-- The alternative (passing -1 as the sound id, the usual fire-and-forget
-- idiom) needs no bookkeeping but produces a handle you can never stop.
-- Managing the id uniformly means every call site gets a stoppable handle and
-- none of them can leak.

---@class QBSoundOptions
---@field network? boolean Play for nearby players too, rather than only locally. Defaults to `false`.
---@field range? number Audible range in metres, world sounds only. Defaults to `Config.sound.defaultRange`.
---@field bank? string Audio bank to request before playing (e.g. `"DLC_MPHEIST/HEIST_FLEECA_BANK"`). Waits for the load.
---@field releaseAfter? number Milliseconds before the sound id is auto-released. Defaults to `Config.sound.defaultReleaseAfter`.

local live = {}
local bankRefs = {}
local nextClaimGeneration = 0

local function releaseBank(bank)
    if not bank then return end
    local count = bankRefs[bank]
    if not count then return end
    if count > 1 then
        bankRefs[bank] = count - 1
    else
        bankRefs[bank] = nil
        ReleaseNamedScriptAudioBank(bank)
    end
end

local function disposeSound(soundId)
    local entry = live[soundId]
    if not entry then return false end
    live[soundId] = nil
    StopSound(soundId)
    ReleaseSoundId(soundId)
    releaseBank(entry.bank)
    return true
end

-- soundId -> claim metadata. The registry sweeps ids still held when their owning
-- resource stops; StopSound before ReleaseSoundId because releasing an id
-- that is still playing leaves the audio running with no handle to stop it.
local soundRegistry = QB.resources.registry(function(soundId)
    disposeSound(soundId)
end)

---@param name any
---@param set any
local function assertSound(name, set)
    assert(type(name) == "string" and name ~= "", "QB.sound requires a non-empty sound name.")
    assert(type(set) == "string" and set ~= "", "QB.sound requires a non-empty sound set/ref.")
end

---Claims a sound id, registers it against the caller, and arms its
---auto-release. Returns the id so each play* function only has to fire its
---own native.
---@param owner string
---@param options QBSoundOptions
---@return number|false soundId
---@return string? error
local function claim(owner, options)
    if options.bank then
        -- QB.stream.loadAudioBank yields until the bank is resident. Playing
        -- before it loads is a silent no-op, not an error, which is the other
        -- classic "the sound sometimes doesn't play" cause.
        if bankRefs[options.bank] then
            bankRefs[options.bank] = bankRefs[options.bank] + 1
        else
            local loaded = QB.stream.loadAudioBank(options.bank)
            if not loaded then return false, ("Failed to load audio bank '%s'."):format(options.bank) end
            bankRefs[options.bank] = 1
        end
    end

    local soundId = GetSoundId()
    if not soundId or soundId == -1 then
        releaseBank(options.bank)
        return false, "No free sound id available."
    end

    nextClaimGeneration = nextClaimGeneration + 1
    local generation = nextClaimGeneration
    live[soundId] = { generation = generation, bank = options.bank }
    soundRegistry.track(owner, soundId)

    local releaseAfter = options.releaseAfter or Config.sound.defaultReleaseAfter
    if releaseAfter and releaseAfter > 0 then
        QB.timers.setTimeout(function()
            local current = live[soundId]
            if current and current.generation == generation then QB.sound.stop(soundId) end
        end, releaseAfter)
    end

    return soundId
end

---Plays a 2D UI/frontend sound (the `PlaySoundFrontend` family -- notification
---beeps, dispatch tones, menu clicks).
---@param name string Sound name, e.g. `"Lose_1st"`.
---@param set string Sound set/ref, e.g. `"GTAO_FM_Events_Soundset"`.
---@param options? QBSoundOptions
---@return number|false soundId Pass to QB.sound.stop.
---@return string? error
function QB.sound.playFrontend(name, set, options)
    local owner = GetInvokingResource() or GetCurrentResourceName()
    options = options or {}
    assertSound(name, set)

    local soundId, err = claim(owner, options)
    if not soundId then return false, err end

    PlaySoundFrontend(soundId, name, set, options.network or false)

    return soundId
end

---Plays a positional sound at world coordinates.
---@param coords vector3 | {x: number, y: number, z: number}
---@param name string
---@param set string
---@param options? QBSoundOptions
---@return number|false soundId
---@return string? error
function QB.sound.playFromCoords(coords, name, set, options)
    local owner = GetInvokingResource() or GetCurrentResourceName()
    options = options or {}
    assertSound(name, set)
    assert(coords and type(coords.x) == "number" and type(coords.y) == "number" and type(coords.z) == "number",
        "Invalid coords: expected a vector3 or {x, y, z} table.")

    local soundId, err = claim(owner, options)
    if not soundId then return false, err end

    PlaySoundFromCoord(soundId, name, coords.x + 0.0, coords.y + 0.0, coords.z + 0.0, set,
        options.network or false, math.floor(options.range or Config.sound.defaultRange), false)

    return soundId
end

---Plays a sound that follows an entity.
---@param entity number
---@param name string
---@param set string
---@param options? QBSoundOptions
---@return number|false soundId
---@return string? error
function QB.sound.playFromEntity(entity, name, set, options)
    local owner = GetInvokingResource() or GetCurrentResourceName()
    options = options or {}
    assertSound(name, set)
    assert(type(entity) == "number" and DoesEntityExist(entity), ("Invalid entity: %s"):format(entity))

    local soundId, err = claim(owner, options)
    if not soundId then return false, err end

    PlaySoundFromEntity(soundId, name, entity, set, options.network or false, 0)

    return soundId
end

---Stops a sound and releases its id. Refuses ids this module didn't allocate
----- exports.qblib:sound_stop is callable from any resource, and the
---untracked-id gate is what stops it doubling as a stop-anything primitive
---against another resource's audio (same rule QB.blips.remove enforces).
---@param soundId number
---@return boolean success
---@return string? error
function QB.sound.stop(soundId)
    if type(soundId) ~= "number" or not live[soundId] then
        return false, "Sound id is not tracked by QB.sound."
    end

    soundRegistry.untrack(soundId)
    disposeSound(soundId)

    return true
end

---Whether a sound id allocated by this module is still held.
---@param soundId number
---@return boolean
function QB.sound.isLive(soundId)
    return live[soundId] ~= nil
end
