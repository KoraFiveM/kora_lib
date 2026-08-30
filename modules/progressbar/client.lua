---@class QBProgressBarDisable
---@field move? boolean Freezes the ped in place for the duration (`FreezeEntityPosition`). Defaults to false.
---@field combat? boolean Disables attack/aim/weapon-switch/melee controls for the duration. Defaults to false.
---@field car? boolean Disables vehicle driving controls while the ped is in a vehicle. Defaults to false.

---@class QBProgressBarAnim
---@field dict string Animation dictionary to play, requested and released automatically.
---@field clip string Clip name within `dict`.
---@field flag? number AnimFlags bitmask passed to `TaskPlayAnim`. Defaults to 1 (loop).
---@field blendIn? number Defaults to 8.0.
---@field blendOut? number Defaults to 8.0.

---@class QBProgressBarScenario
---@field name string Scenario name to play, e.g. `"WORLD_HUMAN_HAMMERING"`.
---@field playEnter? boolean Whether to play the scenario's enter animation. Defaults to true.

---@class QBProgressBarPayload
---@field label string Text shown above the bar.
---@field duration integer Milliseconds the bar takes to fill. Must be > 0 and <= Config.progressbar.maxDuration.
---@field canCancel? boolean Lets the player abort early by pressing Config.progressbar.cancelControl. Defaults to false.
---@field disable? QBProgressBarDisable
---@field anim? QBProgressBarAnim Played for the duration, stopped and released automatically when the bar ends. Mutually exclusive with `scenario`.
---@field scenario? QBProgressBarScenario Played in place for the duration, stopped automatically when the bar ends. Mutually exclusive with `anim`.

-- Only one bar at a time -- see QB.progressbar.start's doc comment for why
-- that's a hard rule rather than a queue/stack.
local busy = false
local cancelRequested = false

-- DisableControlAction only holds for the current frame, so these are
-- reapplied every tick of the loop below rather than once up front.
local COMBAT_CONTROLS = { 24, 25, 47, 58, 140, 141, 142, 143 } -- attack, aim, weapon x2, melee light/heavy/alt/block
local CAR_CONTROLS = { 63, 64, 71, 72 } -- steer left/right, accelerate, brake/reverse

---@param payload QBProgressBarPayload
local function assertPayload(payload)
    assert(type(payload) == "table", "Progress bar payload must be a table.")
    assert(type(payload.label) == "string" and #payload.label > 0, "Progress bar requires a label string.")
    assert(type(payload.duration) == "number" and payload.duration > 0, "Progress bar duration must be a positive number.")
    assert(payload.duration <= Config.progressbar.maxDuration,
        ("Progress bar duration must be at most %d ms (Config.progressbar.maxDuration)."):format(Config.progressbar.maxDuration))

    if payload.anim then
        assert(type(payload.anim.dict) == "string" and type(payload.anim.clip) == "string",
            "Progress bar anim requires string dict/clip fields.")
    end

    if payload.scenario then
        assert(type(payload.scenario.name) == "string" and #payload.scenario.name > 0,
            "Progress bar scenario requires a string name field.")
    end

    assert(not (payload.anim and payload.scenario), "Progress bar cannot play both anim and scenario -- pick one.")
end

---@param dict string
---@return boolean loaded
local function ensureAnimDict(dict)
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    return QB.loops.controlled(function() return HasAnimDictLoaded(dict) end, false, 5000, true) ~= false
end

---Shows a filling progress bar for `payload.duration` ms, optionally playing
---an animation or scenario and disabling controls, and reports whether it
---ran to completion or was cancelled.
---
---Only one bar can be active at once: calling this while another is already
---running does not queue or interrupt it, it just fails immediately -- a
---progress bar represents "the player is busy doing one specific thing right
---now", and silently stacking a second one on top would make both visually
---and mechanically incoherent (which anim plays, whose controls win).
---@param payload QBProgressBarPayload
---@return boolean completed False if the bar never started, or was cancelled (death, the cancel key, QB.progressbar.cancel(), or an internal error) before `duration` elapsed.
---@return string? error Set only when the bar never started at all (another one is already active).
function QB.progressbar.start(payload)
    assertPayload(payload)

    if busy then
        return false, "A progress bar is already active."
    end

    busy = true
    cancelRequested = false

    local ok, result = pcall(function()
        local ped = PlayerPedId()
        local disable = payload.disable or {}
        local anim = payload.anim
        local scenario = payload.scenario
        local animLoaded = false
        local scenarioStarted = false

        QB.nui.send("progressStart", { label = payload.label, duration = payload.duration })

        if scenario then
            TaskStartScenarioInPlace(ped, scenario.name, 0, scenario.playEnter ~= false)
            scenarioStarted = true
        elseif anim then
            animLoaded = ensureAnimDict(anim.dict)
            if animLoaded then
                TaskPlayAnim(ped, anim.dict, anim.clip, anim.blendIn or 8.0, anim.blendOut or 8.0, -1, anim.flag or 1, 0, false, false, false)
            else
                print(("[qblib:progressbar] anim dict '%s' failed to load in time -- continuing without it."):format(anim.dict))
            end
        end

        if disable.move then FreezeEntityPosition(ped, true) end

        -- QB.loops.controlled's own "Loop timed out" IS our success case
        -- here: the predicate below returns truthy ONLY to cancel early, so
        -- running out the clock without it ever doing so is exactly what
        -- "completed" means. See modules/loops/shared.lua.
        local cancelled = QB.loops.controlled(function()
            if IsEntityDead(ped) then return true end
            if cancelRequested then return true end

            if disable.combat then
                for _, control in ipairs(COMBAT_CONTROLS) do DisableControlAction(0, control, true) end
            end

            if disable.car and IsPedInAnyVehicle(ped, false) then
                for _, control in ipairs(CAR_CONTROLS) do DisableControlAction(0, control, true) end
            end

            if payload.canCancel and IsControlJustPressed(0, Config.progressbar.cancelControl) then return true end

            return false
        end, false, payload.duration)

        if disable.move then FreezeEntityPosition(ped, false) end

        if scenarioStarted then
            ClearPedTasks(ped)
        elseif animLoaded then
            StopAnimTask(ped, anim.dict, anim.clip, anim.blendOut or 8.0)
            RemoveAnimDict(anim.dict)
        end

        local completed = cancelled == false

        if not completed then QB.nui.send("progressCancel") end

        return completed
    end)

    busy = false

    if not ok then
        QB.nui.send("progressCancel")
        error(result, 0)
    end

    return result
end

---Cancels the currently active progress bar started by this module, if any.
---The active QB.progressbar.start call notices on its next tick (at most one
---frame later) and returns `completed = false` -- this does not interrupt it
---synchronously.
---@return boolean cancelled True if a bar was actually running and got cancelled; false if none was active.
function QB.progressbar.cancel()
    if not busy then return false end
    cancelRequested = true
    return true
end

---True while a progress bar started by this module is currently running.
---@return boolean
function QB.progressbar.isActive()
    return busy
end