local nextLeaseId = 0
local leases = {}
local controlCounts = {}
local firingCount = 0
local weaponWheelCount = 0
local threadRunning = false
local isInteger = Kora.util.isInteger

local releaseLease
local leaseRegistry = Kora.resources.registry(function(leaseId)
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
    if weaponWheelCount > 0 then HudWeaponWheelIgnoreSelection() end
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
            print(("[kora_lib:controls] control loop stopped after an error: %s"):format(tostring(err)))
        end
    end)
end

local function assertInteger(value, message)
    assert(isInteger(value) and value >= 0, message)
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
    for controlIndex = 1, #lease.controls do
        local control = lease.controls[controlIndex]
        local count = counts[control] - 1
        if count == 0 then
            counts[control] = nil
        else
            counts[control] = count
        end
    end

    if next(counts) == nil then controlCounts[lease.inputGroup] = nil end
    if lease.disablePlayerFiring then firingCount = firingCount - 1 end
    if lease.ignoreWeaponWheel then weaponWheelCount = weaponWheelCount - 1 end

    return true
end

local function acquire(controlIds, options, owner)
    options = options == nil and {} or options
    assert(type(options) == "table", "Control lease options must be a table.")
    assert(type(controlIds) == "table", "Control lease IDs must be an array.")

    local inputGroup = options.inputGroup == nil and 0 or options.inputGroup
    assertInteger(inputGroup, "Control lease inputGroup must be a non-negative integer.")
    assert(options.disablePlayerFiring == nil or type(options.disablePlayerFiring) == "boolean",
        "Control lease disablePlayerFiring must be a boolean.")
    assert(options.ignoreWeaponWheel == nil or type(options.ignoreWeaponWheel) == "boolean",
        "Control lease ignoreWeaponWheel must be a boolean.")

    local controls = {}
    local seen = {}
    for index = 1, #controlIds do
        local control = controlIds[index]
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
    local ignoreWeaponWheel = options.ignoreWeaponWheel == true
    assert(#controls > 0 or disablePlayerFiring or ignoreWeaponWheel,
        "Control lease requires a control ID or an active suppression option.")

    nextLeaseId = nextLeaseId + 1
    local leaseId = nextLeaseId
    leases[leaseId] = {
        inputGroup = inputGroup,
        controls = controls,
        disablePlayerFiring = disablePlayerFiring,
        ignoreWeaponWheel = ignoreWeaponWheel,
    }

    local counts = controlCounts[inputGroup]
    if not counts then
        counts = {}
        controlCounts[inputGroup] = counts
    end

    for controlIndex = 1, #controls do
        local control = controls[controlIndex]
        counts[control] = (counts[control] or 0) + 1
    end

    if disablePlayerFiring then firingCount = firingCount + 1 end
    if ignoreWeaponWheel then weaponWheelCount = weaponWheelCount + 1 end

    leaseRegistry.track(owner or GetInvokingResource() or GetCurrentResourceName(), leaseId)

    local applied, applyErr = pcall(applyControls)
    if not applied then
        releaseLease(leaseId)
        error(applyErr, 0)
    end
    ensureThread()

    return leaseId
end

---Acquires a reference-counted lease that disables the supplied controls every
---frame until released. Overlapping leases are independent: releasing one does
---not re-enable a control that another active lease still owns.
---@param controlIds integer[]
---@param options? QBControlsOptions
---@return integer leaseId
function Kora.controls.acquire(controlIds, options)
    return acquire(controlIds, options)
end

---Internal captured-owner bridge for kora_lib's asynchronous UI flows. Kept in
---Kora.compat so it is never published as a consumer-facing export.
---@param controlIds integer[]
---@param options QBControlsOptions?
---@param owner string
---@return integer leaseId
function Kora.compat.acquireControls(controlIds, options, owner)
    assert(type(owner) == 'string' and owner ~= '', 'Control lease owner must be a non-empty string.')
    return acquire(controlIds, options, owner)
end

---Releases a control lease owned by the calling resource. Safe to call
---repeatedly during idempotent cleanup.
---@param leaseId integer
---@return boolean released False when the lease was unknown or already released.
function Kora.controls.release(leaseId)
    if not isInteger(leaseId) or leaseId < 1 then return false end
    if leaseRegistry.owner(leaseId) ~= (GetInvokingResource() or GetCurrentResourceName()) then
        return false
    end
    return releaseLease(leaseId)
end

---@param leaseId integer
---@param owner string
---@return boolean released
function Kora.compat.releaseControlLease(leaseId, owner)
    assert(type(owner) == 'string' and owner ~= '', 'Control lease owner must be a non-empty string.')
    if not isInteger(leaseId) or leaseId < 1 or leaseRegistry.owner(leaseId) ~= owner then return false end
    return releaseLease(leaseId)
end
