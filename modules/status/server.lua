---@class QBStatusApplyOptions
---@field duration? integer Overrides the effect def's own default duration for this application.
---@field severity? integer 1..def.severityLevels. Ignored if the def has no `severityLevels`.

-- active[target][name] = {expiresAt: integer?, severity: integer?}
local active = {}

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
function QB.status.apply(target, name, opts)
    assert(type(target) == "number", "QB.status.apply requires a numeric target server id.")

    local def = QB.status.getEffectDef(name)
    if not def then
        return false, ("Unknown status effect: %s"):format(name)
    end

    opts = opts or {}

    if opts.severity ~= nil then
        assert(def.severityLevels and opts.severity >= 1 and opts.severity <= def.severityLevels,
            ("severity must be between 1 and %s for '%s'."):format(tostring(def.severityLevels), name))
    end

    local bucket = bucketFor(target)
    local existing = bucket[name]
    local stacking = def.stacking or "replace"
    local duration = opts.duration or def.duration
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

    local severity = opts.severity
    if severity == nil then
        severity = (existing and existing.severity)
    elseif stacking == "stack" and existing and existing.severity then
        severity = math.min(def.severityLevels or severity, existing.severity + severity)
    end

    bucket[name] = { expiresAt = expiresAt, severity = severity }

    local remainingDuration = expiresAt and math.max(0, expiresAt - now) or nil
    QB.events.push(target, "qblib:status:apply", name, { duration = remainingDuration, severity = severity })

    return true
end

---@param target integer
---@param name string
---@return boolean removed False if `name` wasn't active for `target`.
function QB.status.remove(target, name)
    local bucket = active[target]
    if not bucket or not bucket[name] then return false end

    bucket[name] = nil
    QB.events.push(target, "qblib:status:remove", name)

    return true
end

---@param target integer
---@param name string
---@return boolean
function QB.status.isActive(target, name)
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
function QB.status.getActive(target)
    local bucket = active[target]
    if not bucket then return {} end

    local now = GetGameTimer()
    local result = {}

    for name, entry in pairs(bucket) do
        if not entry.expiresAt or entry.expiresAt > now then
            result[#result + 1] = { name = name, severity = entry.severity, expiresAt = entry.expiresAt }
        end
    end

    return result
end

AddEventHandler("playerDropped", function()
    active[source] = nil
end)

-- Periodic sweep so an effect nobody ever polls isActive/getActive for still
-- gets dropped from memory once it expires, instead of sitting in `active`
-- indefinitely. 30s matches modules/minigames' own session-sweep cadence.
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
    end
end)
