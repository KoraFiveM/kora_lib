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

local soundRegistry = Kora.resources.registry(function(soundId)
    disposeSound(soundId)
end)

---@param name any
---@param set any
local function assertSound(name, set)
    assert(type(name) == "string" and name ~= "", "Kora.sound requires a non-empty sound name.")
    assert(type(set) == "string" and set ~= "", "Kora.sound requires a non-empty sound set/ref.")
end

---@param options any
local function assertOptions(options)
    assert(type(options) == "table", "Sound options must be a table.")
    assert(options.network == nil or type(options.network) == "boolean", "Sound network must be a boolean.")
    assert(options.bank == nil or (type(options.bank) == "string" and options.bank ~= ""),
        "Sound bank must be a non-empty string.")
end

---Claims a sound id, registers it against the caller and arms its auto-release.
---@param owner string
---@param options KoraSoundOptions
---@return number|false soundId
---@return string? error
local function claim(owner, options)
    local releaseAfter = options.releaseAfter
    if releaseAfter == nil then releaseAfter = Config.sound.defaultReleaseAfter end
    assert(Kora.util.isFiniteNumber(releaseAfter) and releaseAfter >= 0,
        'Sound releaseAfter must be a finite non-negative number.')

    if options.bank then
        if bankRefs[options.bank] then
            bankRefs[options.bank] = bankRefs[options.bank] + 1
        else
            local loaded = Kora.stream.loadAudioBank(options.bank)
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

    if releaseAfter > 0 then
        Kora.timers.setTimeout(function()
            local current = live[soundId]
            if current and current.generation == generation then Kora.sound.stop(soundId) end
        end, releaseAfter)
    end

    return soundId
end

---Plays a 2D UI/frontend sound (`PlaySoundFrontend` family).
---@param name string Sound name, e.g. `"Lose_1st"`.
---@param set string Sound set/ref, e.g. `"GTAO_FM_Events_Soundset"`.
---@param options? KoraSoundOptions
---@return number|false soundId Pass to Kora.sound.stop.
---@return string? error
function Kora.sound.playFrontend(name, set, options)
    local owner = GetInvokingResource() or GetCurrentResourceName()
    if options == nil then options = {} end
    assertSound(name, set)
    assertOptions(options)

    local soundId, err = claim(owner, options)
    if not soundId then return false, err end

    PlaySoundFrontend(soundId, name, set, options.network == true)

    return soundId
end

---Plays a positional sound at world coordinates.
---@param coords vector3 | {x: number, y: number, z: number}
---@param name string
---@param set string
---@param options? KoraSoundOptions
---@return number|false soundId
---@return string? error
function Kora.sound.playFromCoords(coords, name, set, options)
    local owner = GetInvokingResource() or GetCurrentResourceName()
    if options == nil then options = {} end
    assertSound(name, set)
    assertOptions(options)
    assert(coords and Kora.util.isFiniteNumber(coords.x) and Kora.util.isFiniteNumber(coords.y) and Kora.util.isFiniteNumber(coords.z),
        "Invalid coords: expected a vector3 or {x, y, z} table.")
    local range = options.range
    if range == nil then range = Config.sound.defaultRange end
    assert(Kora.util.isFiniteNumber(range) and range >= 0,
        'Sound range must be a finite non-negative number.')

    local soundId, err = claim(owner, options)
    if not soundId then return false, err end

    PlaySoundFromCoord(soundId, name, coords.x + 0.0, coords.y + 0.0, coords.z + 0.0, set,
        options.network == true, math.floor(range), false)

    return soundId
end

---Plays a sound that follows an entity.
---@param entity number
---@param name string
---@param set string
---@param options? KoraSoundOptions
---@return number|false soundId
---@return string? error
function Kora.sound.playFromEntity(entity, name, set, options)
    local owner = GetInvokingResource() or GetCurrentResourceName()
    if options == nil then options = {} end
    assertSound(name, set)
    assertOptions(options)
    assert(Kora.util.isInteger(entity) and entity ~= 0 and DoesEntityExist(entity), ("Invalid entity: %s"):format(entity))

    local soundId, err = claim(owner, options)
    if not soundId then return false, err end

    PlaySoundFromEntity(soundId, name, entity, set, options.network == true, 0)

    return soundId
end

---Stops a sound and releases its id. Refuses ids this module didn't allocate: the export is callable
---from any resource, and this gate stops it being a stop-anything primitive (same rule as Kora.blips.remove).
---@param soundId number
---@return boolean success
---@return string? error
function Kora.sound.stop(soundId)
    if not Kora.util.isInteger(soundId) or not live[soundId] then
        return false, "Sound id is not tracked by Kora.sound."
    end

    local caller = GetInvokingResource()
    if caller and soundRegistry.owner(soundId) ~= caller then
        return false, "Sound id is owned by another resource."
    end

    soundRegistry.untrack(soundId)
    disposeSound(soundId)

    return true
end

---Whether a sound id allocated by this module is still held.
---@param soundId number
---@return boolean
function Kora.sound.isLive(soundId)
    return Kora.util.isInteger(soundId) and live[soundId] ~= nil
end
