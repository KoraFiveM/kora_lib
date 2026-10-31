Kora.visuals = Kora.visuals or {}
local FADE_TIMEOUT_BUFFER = 1000

local function parseDuration(duration, default)
    duration = tonumber(duration)
    if duration == nil then return default end

    assert(Kora.util.isFiniteNumber(duration) and duration >= 0,
        'Visual effect duration must be a finite non-negative number.')
    return duration
end

local function getDuration(duration)
    duration = parseDuration(duration, 3000)
    return math.floor(duration / 2)
end

local function playDrugEffect(prefix, duration)
    duration = getDuration(duration)
    local effectIn = prefix .. 'In'
    local effect = prefix
    local effectOut = prefix .. 'Out'
    StartScreenEffect(effectIn, 3.0, false)
    Wait(duration)
    StartScreenEffect(effect, 3.0, false)
    Wait(duration)
    StartScreenEffect(effectOut, 3.0, false)
    StopScreenEffect(effectIn)
    StopScreenEffect(effect)
    StopScreenEffect(effectOut)
end

local function ragdollIfRunning(ped, minTime, maxTime)
    if not IsPedRunning(ped) then return end

    SetPedToRagdoll(ped, math.random(minTime, maxTime), math.random(minTime, maxTime),  3,  false,  false,  false)
end

local function restoreStamina(chance)
    if math.random(1, 100) <= chance then
        RestorePlayerStamina(PlayerId(), 1.0)
    end
end

local function setSprintMultiplier(multiplier)
    SetRunSprintMultiplierForPlayer(PlayerId(), multiplier)
end

-- Overlapping drug effects need stack-like ownership of the one native sprint
-- multiplier. The most recently started live effect wins. If it finishes
-- first, the previous live effect is restored; if an older effect finishes
-- first, the current value is left alone.
local sprintEffectGeneration = 0
local sprintEffects = {}
local currentSprintToken = nil

---@param multiplier number
---@return integer token Pass to endSprintEffect once this effect's loop finishes.
local function beginSprintEffect(multiplier)
    sprintEffectGeneration = sprintEffectGeneration + 1
    local token = sprintEffectGeneration
    sprintEffects[token] = multiplier
    currentSprintToken = token
    setSprintMultiplier(multiplier)
    return token
end

---Releases one sprint effect and restores the newest still-live effect, or
---the native default when none remain.
---@param playerId integer
---@param token integer
local function endSprintEffect(playerId, token)
    if sprintEffects[token] == nil then return end
    sprintEffects[token] = nil
    if token ~= currentSprintToken then return end

    local newestToken = nil
    for candidate in pairs(sprintEffects) do
        if not newestToken or candidate > newestToken then newestToken = candidate end
    end

    currentSprintToken = newestToken
    SetRunSprintMultiplierForPlayer(playerId, newestToken and sprintEffects[newestToken] or 1.0)
end

---@class QBVisualsStaminaEffectOptions
---@field prefix string playDrugEffect prefix (`<prefix>In`/`<prefix>`/`<prefix>Out`).
---@field multiplier number Sprint multiplier applied for the duration of the effect.
---@field ticks integer Number of 1-second stamina ticks the effect runs for.
---@field restoreChance integer Chance out of 100, rolled each tick, to restore stamina.
---@field replayChance integer Chance, rolled each tick against replayScale, to replay the drug screen effect.
---@field replayScale? integer Denominator replayChance is rolled against. Default 100 -- coke uses 300, preserve exactly.
---@field replayExtraWait? {min: integer, max: integer} Extra Wait(math.random(min,max)) after a successful replay (coke only).
---@field perTickRagdoll? {chance: integer, minTime: integer, maxTime: integer} Chance out of 100, each tick, to ragdoll if running.
---@field finalRagdoll? {minTime: integer, maxTime: integer} Ragdoll unconditionally once the tick loop ends.

---Shared stamina-tick loop behind Kora.visuals.meth/crack/coke. Always reads the
---ped fresh via Kora.cache.ped() at each point of use rather than caching it
---once up front, so a death/respawn mid-loop (up to 20s) doesn't ragdoll a
---stale/dead ped handle.
---@param options QBVisualsStaminaEffectOptions
---@param duration number|string|nil Raw duration argument as passed to the public Kora.visuals.<fn>.
local function runStaminaDrugEffect(options, duration)
    local playerId = PlayerId()

    playDrugEffect(options.prefix, duration)

    local token = beginSprintEffect(options.multiplier)

    local stamina = options.ticks
    while stamina > 0 do
        Wait(1000)
        restoreStamina(options.restoreChance)

        if options.perTickRagdoll and math.random(1, 100) <= options.perTickRagdoll.chance then
            ragdollIfRunning(Kora.cache.ped(), options.perTickRagdoll.minTime, options.perTickRagdoll.maxTime)
        end

        if math.random(1, options.replayScale or 100) <= options.replayChance then
            playDrugEffect(options.prefix, duration)
            if options.replayExtraWait then
                Wait(math.random(options.replayExtraWait.min, options.replayExtraWait.max))
            end
        end

        stamina = stamina - 1
    end

    if options.finalRagdoll then
        ragdollIfRunning(Kora.cache.ped(), options.finalRagdoll.minTime, options.finalRagdoll.maxTime)
    end

    endSprintEffect(playerId, token)
end

-- Cross-resource function references arrive as callable tables rather than
-- plain Lua functions. Public callback-taking APIs must accept both shapes.
local isCallable = Kora.compat.isCallable

local function isCoords(value)
    local kind = type(value)
    return kind == 'table' or kind == 'vector3' or kind == 'vector4'
end

---Fades the screen around `fn`, running it while the screen is fully black.
---The legacy `(coords, duration)` form remains supported; new movement code
---should use `Kora.teleport.entity`/`Kora.teleport.player` instead.
---@param duration number|vector3|vector4|table|nil Fade duration in milliseconds, or legacy destination coords.
---@param fn function|table|number|string|nil Work to perform while faded out, a masked callable, or legacy duration.
function Kora.visuals.fade(duration, fn)
    if isCoords(duration) then
        local coords, legacyDuration = duration, fn
        return Kora.visuals.fade(legacyDuration, function()
            SetEntityCoords(Kora.cache.ped(), coords.x, coords.y, coords.z)
            if type(coords.w) == 'number' then SetEntityHeading(Kora.cache.ped(), coords.w) end
        end)
    end

    duration = parseDuration(duration, 500)
    DoScreenFadeOut(duration)
    local deadline = GetGameTimer() + duration + FADE_TIMEOUT_BUFFER
    while not IsScreenFadedOut() and GetGameTimer() < deadline do
        Wait(10)
    end

    local ok, err = true
    if isCallable(fn) then ok, err = pcall(fn) end

    -- Never strand the player behind a black screen when work performed at
    -- full fade errors. Restore the display first, then preserve the error.
    DoScreenFadeIn(duration)
    if not ok then error(err, 0) end
end

---@param duration? number|string
function Kora.visuals.trevor(duration)
    CreateThread(function()
        playDrugEffect('DrugsTrevorClownsFight', duration)
    end)
end

---@param duration? number|string
function Kora.visuals.meth(duration)
    CreateThread(function()
        runStaminaDrugEffect({
            prefix = 'DrugsTrevorClownsFight',
            multiplier = 1.49,
            ticks = 8,
            restoreChance = 10,
            replayChance = 51,
        }, duration)
    end)
end

---@param duration? number|string
function Kora.visuals.ecstacy(duration)
    CreateThread(function()
        local playerId = PlayerId()
        local stamina = math.max(1, math.floor(parseDuration(duration, 30000) / 1000))
        SetFlash(0, 0, 500, 7000, 500)
        while stamina > 0 do
            Wait(1000)
            RestorePlayerStamina(playerId, 1.0)
            if math.random(1, 100) <= 51 then
                SetFlash(0, 0, 500, 7000, 500)
                ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', 0.08)
            end
            stamina = stamina - 1
        end
        -- Read fresh, not the ped from when this thread started -- this loop
        -- can run tens of seconds, long enough to outlive a death/respawn.
        ragdollIfRunning(Kora.cache.ped(), 1000, 3000)
    end)
end

---@param duration? number|string
function Kora.visuals.alien(duration)
    CreateThread(function()
        playDrugEffect('DrugsMichaelAliensFight', duration)
    end)
end

---@param duration? number|string
function Kora.visuals.crack(duration)
    CreateThread(function()
        runStaminaDrugEffect({
            prefix = 'DrugsMichaelAliensFight',
            multiplier = 1.3,
            ticks = 8,
            restoreChance = 10,
            replayChance = 51,
            perTickRagdoll = { chance = 60, minTime = 1000, maxTime = 2000 },
            finalRagdoll = { minTime = 1000, maxTime = 3000 },
        }, duration)
    end)
end

---@param duration? number|string
function Kora.visuals.coke(duration)
    CreateThread(function()
        runStaminaDrugEffect({
            prefix = 'DrugsMichaelAliensFight',
            multiplier = 1.1,
            ticks = 20,
            restoreChance = 20,
            replayChance = 10,
            replayScale = 300,
            replayExtraWait = { min = 3000, max = 6000 },
            perTickRagdoll = { chance = 10, minTime = 1000, maxTime = 3000 },
            finalRagdoll = { minTime = 1000, maxTime = 3000 },
        }, duration)
    end)
end
