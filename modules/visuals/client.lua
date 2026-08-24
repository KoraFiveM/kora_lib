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
        local playerId = PlayerId()
        local stamina = 8
        playDrugEffect('DrugsTrevorClownsFight', duration)
        setSprintMultiplier(1.49)
        while stamina > 0 do
            Wait(1000)
            restoreStamina(10)
            if math.random(1, 100) <= 51 then
                playDrugEffect('DrugsTrevorClownsFight', duration)
            end
            stamina -= 1
        end
        SetRunSprintMultiplierForPlayer(playerId, 1.0)
    end)
end

function QB.visuals.ecstacy(duration)
    CreateThread(function()
        local playerId = PlayerId()
        local ped = PlayerPedId()
        local stamina = math.max(1, math.floor((tonumber(duration) or 30000) / 1000))
        SetFlash(0, 0, 500, 7000, 500)
        while stamina > 0 do
            Wait(1000)
            RestorePlayerStamina(playerId, 1.0)
            if math.random(1, 100) <= 51 then
                SetFlash(0, 0, 500, 7000, 500)
                ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', 0.08)
            end
            stamina -= 1
        end
        ragdollIfRunning(ped, 1000, 3000)
    end)
end

function QB.visuals.alien(duration)
    CreateThread(function()
        playDrugEffect('DrugsMichaelAliensFight', duration)
    end)
end

function QB.visuals.crack(duration)
    CreateThread(function()
        local playerId = PlayerId()
        local ped = PlayerPedId()
        local stamina = 8
        playDrugEffect('DrugsMichaelAliensFight', duration)
        setSprintMultiplier(1.3)
        while stamina > 0 do
            Wait(1000)
            restoreStamina(10)
            if math.random(1, 100) <= 60 then
                ragdollIfRunning(ped, 1000, 2000)
            end
            if math.random(1, 100) <= 51 then
                playDrugEffect('DrugsMichaelAliensFight', duration)
            end
            stamina -= 1
        end
        ragdollIfRunning(ped, 1000, 3000)
        SetRunSprintMultiplierForPlayer(playerId, 1.0)
    end)
end

function QB.visuals.coke(duration)
    CreateThread(function()
        local playerId = PlayerId()
        local ped = PlayerPedId()
        local stamina = 20
        playDrugEffect('DrugsMichaelAliensFight', duration)
        setSprintMultiplier(1.1)
        while stamina > 0 do
            Wait(1000)
            restoreStamina(20)
            if math.random(1, 100) <= 10 then
                ragdollIfRunning(ped, 1000, 3000)
            end
            if math.random(1, 300) <= 10 then
                playDrugEffect('DrugsMichaelAliensFight', duration)
                Wait(math.random(3000, 6000))
            end
            stamina -= 1
        end
        ragdollIfRunning(ped, 1000, 3000)
        SetRunSprintMultiplierForPlayer(playerId, 1.0)
    end)
end