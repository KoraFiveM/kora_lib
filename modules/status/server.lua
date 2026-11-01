---@class QBStatusApplyOptions
---@field duration? integer Overrides the effect def's own default duration for this application.
---@field severity? integer 1..def.severityLevels. Ignored if the def has no `severityLevels`.

-- active[target][name] = {expiresAt: integer?, severity: integer?}
local active = {}
local expirySweepRunning = false
local ensureExpirySweep
local isInteger = Kora.util.isInteger

local function assertPlayerTarget(target, operation)
    assert(isInteger(target) and target >= 1,
        ("Kora.status.%s requires a positive integer target server id."):format(operation))
end

local function bucketFor(target)
    local bucket = active[target]
    if not bucket then
        bucket = {}
        active[target] = bucket
    end
    return bucket
end

---@param target integer
---@param name string
---@param opts? QBStatusApplyOptions
---@return boolean success
---@return string? error
function Kora.status.apply(target, name, opts)
    assertPlayerTarget(target, "apply")
    Kora.status.assertName(name)
    assert(opts == nil or type(opts) == "table", "Kora.status.apply options must be a table.")
    opts = opts or {}
    assert(opts.duration == nil or (isInteger(opts.duration) and opts.duration >= 0),
        "duration must be a non-negative integer.")
    assert(opts.severity == nil or (isInteger(opts.severity) and opts.severity >= 1),
        "severity must be a positive integer.")

    local def = Kora.status.getEffectDef(name)
    if not def then
        return false, ("Unknown status effect: %s"):format(name)
    end

    if def.severityLevels and opts.severity ~= nil then
        assert(opts.severity <= def.severityLevels,
            ("severity must be between 1 and %s for '%s'."):format(tostring(def.severityLevels), name))
    end

    local bucket = bucketFor(target)
    local existing = bucket[name]
    local stacking = def.stacking or "replace"
    local duration = opts.duration or def.duration
    if duration then ensureExpirySweep() end
    local now = GetGameTimer()

    if existing and existing.expiresAt and existing.expiresAt <= now then
        existing = nil
    end

    local expiresAt
    if duration then
        if stacking == "extend" and existing and existing.expiresAt then
            expiresAt = existing.expiresAt + duration
        else
            expiresAt = now + duration
        end
    end

    local severity = def.severityLevels and opts.severity or nil
    if severity == nil then
        severity = (existing and existing.severity)
    elseif stacking == "stack" and existing and existing.severity then
        severity = math.min(def.severityLevels or severity, existing.severity + severity)
    end

    bucket[name] = { expiresAt = expiresAt, severity = severity }

    local remainingDuration = expiresAt and math.max(0, expiresAt - now) or nil
    Kora.events.push(target, "kora_lib:status:apply", name, { duration = remainingDuration, severity = severity })

    return true
end

---@param target integer
---@param name string
---@return boolean removed False if `name` wasn't active for `target`.
function Kora.status.remove(target, name)
    assertPlayerTarget(target, "remove")
    Kora.status.assertName(name)

    local bucket = active[target]
    if not bucket or not bucket[name] then return false end

    bucket[name] = nil
    Kora.events.push(target, "kora_lib:status:remove", name)

    return true
end

---@param target integer
---@param name string
---@return boolean
function Kora.status.isActive(target, name)
    assertPlayerTarget(target, "isActive")
    Kora.status.assertName(name)

    local bucket = active[target]
    local entry = bucket and bucket[name]
    if not entry then return false end

    if entry.expiresAt and entry.expiresAt <= GetGameTimer() then
        bucket[name] = nil
        return false
    end

    return true
end

---@class QBStatusActiveEntry
---@field name string
---@field severity? integer
---@field expiresAt? integer

---@param target integer
---@return QBStatusActiveEntry[]
function Kora.status.getActive(target)
    assertPlayerTarget(target, "getActive")

    local bucket = active[target]
    if not bucket then return {} end

    local now = GetGameTimer()
    local result = {}

    for name, entry in pairs(bucket) do
        if not entry.expiresAt or entry.expiresAt > now then
            result[#result + 1] = { name = name, severity = entry.severity, expiresAt = entry.expiresAt }
        else
            bucket[name] = nil
        end
    end

    if next(bucket) == nil then active[target] = nil end

    return result
end

AddEventHandler("playerDropped", function()
    active[source] = nil
end)

-- Periodic sweep drops expired effects nobody polls; 30s matches modules/minigames' session sweep.
local function hasExpiringEntries()
    for _, bucket in pairs(active) do
        for _, entry in pairs(bucket) do
            if entry.expiresAt then return true end
        end
    end
    return false
end

ensureExpirySweep = function()
    if expirySweepRunning then return end
    expirySweepRunning = true

    CreateThread(function()
        while true do
            Wait(30000)

            local now = GetGameTimer()
            for target, bucket in pairs(active) do
                for name, entry in pairs(bucket) do
                    if entry.expiresAt and entry.expiresAt <= now then
                        bucket[name] = nil
                    end
                end
                if next(bucket) == nil then
                    active[target] = nil
                end
            end

            if not hasExpiringEntries() then break end
        end

        expirySweepRunning = false
    end)
end
