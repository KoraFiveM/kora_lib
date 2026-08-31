---@class QBControlsOptions
---@field inputGroup? integer Input group passed to DisableControlAction. Defaults to 0.
---@field disablePlayerFiring? boolean Calls DisablePlayerFiring every frame while the lease is active. Defaults to false.

---@class QBControlLease
---@field inputGroup integer
---@field controls integer[]
---@field disablePlayerFiring boolean

local nextLeaseId = 0
local leases = {}
local controlCounts = {}
local firingCount = 0
local threadRunning = false

local releaseLease
local leaseRegistry = QB.resources.registry(function(leaseId)
    releaseLease(leaseId, true)
end)

local function applyControls()
    for inputGroup, controls in pairs(controlCounts) do
        for control in pairs(controls) do
            DisableControlAction(inputGroup, control, true)
        end
    end

    if firingCount > 0 then
        DisablePlayerFiring(PlayerId(), true)
    end
end

local function ensureThread()
    if threadRunning then return end
    threadRunning = true

    CreateThread(function()
        local ok, err = pcall(function()
            while next(leases) do
                applyControls()
                Wait(0)
            end
        end)

        threadRunning = false

        if not ok then
            print(("[qblib:controls] control loop stopped after an error: %s"):format(tostring(err)))
        end
    end)
end

local function assertInteger(value, message)
    assert(type(value) == "number" and value % 1 == 0 and value >= 0, message)
end

---@param leaseId integer
---@param alreadyUntracked? boolean
---@return boolean released
releaseLease = function(leaseId, alreadyUntracked)
    local lease = leases[leaseId]
    if not lease then return false end

    leases[leaseId] = nil
    if not alreadyUntracked then leaseRegistry.untrack(leaseId) end

    local counts = controlCounts[lease.inputGroup]
    for _, control in ipairs(lease.controls) do
        local count = counts[control] - 1
        if count == 0 then
            counts[control] = nil
        else
            counts[control] = count
        end
    end

    if next(counts) == nil then controlCounts[lease.inputGroup] = nil end
    if lease.disablePlayerFiring then firingCount = firingCount - 1 end

    return true
end

---Acquires a reference-counted lease that disables the supplied controls every
---frame until released. Overlapping leases are independent: releasing one does
---not re-enable a control that another active lease still owns.
---@param controlIds integer[]
---@param options? QBControlsOptions
---@return integer leaseId
function QB.controls.acquire(controlIds, options)
    options = options or {}
    assert(type(options) == "table", "Control lease options must be a table.")
    assert(type(controlIds) == "table", "Control lease IDs must be an array.")

    local inputGroup = options.inputGroup or 0
    assertInteger(inputGroup, "Control lease inputGroup must be a non-negative integer.")
    assert(options.disablePlayerFiring == nil or type(options.disablePlayerFiring) == "boolean",
        "Control lease disablePlayerFiring must be a boolean.")

    local controls = {}
    local seen = {}
    for index, control in ipairs(controlIds) do
        assertInteger(control, ("Control lease ID at index %d must be a non-negative integer."):format(index))
        if not seen[control] then
            seen[control] = true
            controls[#controls + 1] = control
        end
    end

    local keyCount = 0
    for key in pairs(controlIds) do
        assert(type(key) == "number" and key % 1 == 0 and key >= 1,
            "Control lease IDs must be a dense array.")
        keyCount = keyCount + 1
    end
    assert(keyCount == #controlIds, "Control lease IDs must be a dense array.")

    local disablePlayerFiring = options.disablePlayerFiring == true
    assert(#controls > 0 or disablePlayerFiring,
        "Control lease requires at least one control ID or disablePlayerFiring = true.")

    nextLeaseId = nextLeaseId + 1
    local leaseId = nextLeaseId
    leases[leaseId] = {
        inputGroup = inputGroup,
        controls = controls,
        disablePlayerFiring = disablePlayerFiring,
    }

    local counts = controlCounts[inputGroup]
    if not counts then
        counts = {}
        controlCounts[inputGroup] = counts
    end

    for _, control in ipairs(controls) do
        counts[control] = (counts[control] or 0) + 1
    end

    if disablePlayerFiring then firingCount = firingCount + 1 end

    leaseRegistry.track(GetInvokingResource() or GetCurrentResourceName(), leaseId)

    -- Apply once before returning so callers can immediately use
    -- IsDisabledControlJustPressed/GetDisabledControlNormal in the same tick.
    local applied, applyErr = pcall(applyControls)
    if not applied then
        releaseLease(leaseId)
        error(applyErr, 0)
    end
    ensureThread()

    return leaseId
end

---Releases a control lease. Safe to call repeatedly during idempotent cleanup.
---@param leaseId integer
---@return boolean released False when the lease was unknown or already released.
function QB.controls.release(leaseId)
    if type(leaseId) ~= "number" or leaseId % 1 ~= 0 then return false end
    return releaseLease(leaseId)
end
