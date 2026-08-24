QB.visuals = QB.visuals or {}

local function getDuration(duration)
    duration = tonumber(duration)
    if not duration then return 3000 end
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

-- Overlapping drug effects (e.g. meth started while crack's boost is still
-- running) must not stomp each other's sprint multiplier: each effect's own
-- CreateThread ends with an unconditional reset to 1.0, so whichever effect
-- finishes first would otherwise cancel a still-active later effect's boost.
-- sprintEffectGeneration is a monotonically increasing token: beginSprintEffect
-- bumps it and hands the new value back to the caller; endSprintEffect only
-- resets the multiplier if the token it was given still matches the CURRENT
-- generation -- i.e. only if no later effect has started since. A later
-- effect's own beginSprintEffect call invalidates every earlier token, so an
-- earlier effect's teardown becomes a no-op once superseded.
local sprintEffectGeneration = 0

---@param multiplier number
---@return integer token Pass to endSprintEffect once this effect's loop finishes.
local function beginSprintEffect(multiplier)
    sprintEffectGeneration = sprintEffectGeneration + 1
    setSprintMultiplier(multiplier)
    return sprintEffectGeneration
end

---Resets the sprint multiplier to 1.0, but only if `token` still matches the
---current generation -- i.e. only if no later effect has claimed the slot
---since. A no-op otherwise, leaving the still-active later effect alone.
---@param playerId integer
---@param token integer
local function endSprintEffect(playerId, token)
    if token ~= sprintEffectGeneration then return end
    SetRunSprintMultiplierForPlayer(playerId, 1.0)
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

---Shared stamina-tick loop behind QB.visuals.meth/crack/coke. Always reads the
---ped fresh via QB.cache.ped() at each point of use rather than caching it
---once up front, so a death/respawn mid-loop (up to 20s) doesn't ragdoll a
---stale/dead ped handle.
---@param options QBVisualsStaminaEffectOptions
---@param duration number|string|nil Raw duration argument as passed to the public QB.visuals.<fn>.
local function runStaminaDrugEffect(options, duration)
    local playerId = PlayerId()

    playDrugEffect(options.prefix, duration)

    local token = beginSprintEffect(options.multiplier)

    local stamina = options.ticks
    while stamina > 0 do
        Wait(1000)
        restoreStamina(options.restoreChance)

        if options.perTickRagdoll and math.random(1, 100) <= options.perTickRagdoll.chance then
            ragdollIfRunning(QB.cache.ped(), options.perTickRagdoll.minTime, options.perTickRagdoll.maxTime)
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
        ragdollIfRunning(QB.cache.ped(), options.finalRagdoll.minTime, options.finalRagdoll.maxTime)
    end

    endSprintEffect(playerId, token)
end

function QB.visuals.fade(coords, duration)
    duration = tonumber(duration) or 500
    DoScreenFadeOut(duration)
    while not IsScreenFadedOut() do
        Wait(10)
    end
    if coords then
        SetEntityCoords(PlayerPedId(),coords.x,coords.y, coords.z)
    end
    DoScreenFadeIn(duration)
end

function QB.visuals.trevor(duration)
    CreateThread(function()
        playDrugEffect('DrugsTrevorClownsFight', duration)
    end)
end

function QB.visuals.meth(duration)
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

function QB.visuals.ecstacy(duration)
    CreateThread(function()
        local playerId = PlayerId()
        local stamina = math.max(1, math.floor((tonumber(duration) or 30000) / 1000))
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
        ragdollIfRunning(QB.cache.ped(), 1000, 3000)
    end)
end

function QB.visuals.alien(duration)
    CreateThread(function()
        playDrugEffect('DrugsMichaelAliensFight', duration)
    end)
end

function QB.visuals.crack(duration)
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

function QB.visuals.coke(duration)
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