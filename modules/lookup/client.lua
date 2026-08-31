local state = QB.lookup._state
local SYNC_REQUEST = 'qblib:lookup:sync'
local SYNC_PUSH = 'qblib:lookup:syncBatch'

local assemblies = {}

local function copyTable(value)
    if type(value) ~= 'table' then return nil end
    local copy = {}
    for key, entry in pairs(value) do copy[key] = entry end
    return copy
end

local function copyStringArray(value)
    if type(value) ~= 'table' then return nil end
    local copy, seen = {}, {}
    for _, entry in ipairs(value) do
        if type(entry) == 'string' and entry ~= '' and not seen[entry] then
            seen[entry] = true
            copy[#copy + 1] = entry
        end
    end
    table.sort(copy)
    return #copy > 0 and copy or nil
end

local function acceptRecord(record)
    if type(record) ~= 'table' or not state.namespaces[record.namespace]
        or type(record.name) ~= 'string' or record.name:match('^%s*$') then
        return nil
    end

    local ok, expectedHash = pcall(state.normalize, record.name)
    if not ok then return nil end

    local hash = expectedHash
    if record.hash ~= nil then
        local hashOk, suppliedHash = pcall(state.normalize, record.hash)
        if not hashOk or suppliedHash ~= expectedHash then return nil end
        hash = suppliedHash
    end

    local accepted = {
        namespace = record.namespace,
        hash = hash,
        signedHash = hash >= 2147483648 and hash - 4294967296 or hash,
        hexHash = ('0x%08X'):format(hash),
        name = record.name,
        label = type(record.label) == 'string' and record.label or nil,
        labelKey = type(record.labelKey) == 'string' and record.labelKey or nil,
        category = type(record.category) == 'string' and record.category or nil,
        dlc = type(record.dlc) == 'string' and record.dlc or nil,
        source = 'custom',
        resources = copyStringArray(record.resources),
        metadata = copyTable(record.metadata),
    }
    if accepted.metadata and next(accepted.metadata) == nil then accepted.metadata = nil end
    return accepted
end

local function mergeAccepted(current, incoming)
    if current == nil then return incoming end
    for _, field in ipairs({ 'label', 'labelKey', 'category', 'dlc' }) do
        if current[field] == nil then current[field] = incoming[field] end
    end
    current.metadata = current.metadata or {}
    for field, value in pairs(incoming.metadata or {}) do
        if current.metadata[field] == nil then current.metadata[field] = value end
    end
    if next(current.metadata) == nil then current.metadata = nil end

    local seen = {}
    for _, resource in ipairs(current.resources or {}) do seen[resource] = true end
    for _, resource in ipairs(incoming.resources or {}) do
        if not seen[resource] then
            seen[resource] = true
            current.resources = current.resources or {}
            current.resources[#current.resources + 1] = resource
        end
    end
    if current.resources then table.sort(current.resources) end
    return current
end

local function publish(version, assembly)
    local overlay, working = {}, {}
    for _, namespace in ipairs(state.namespaceOrder) do
        overlay[namespace] = {}
        working[namespace] = {}
    end

    for index = 1, assembly.total do
        for _, rawRecord in ipairs(assembly.batches[index]) do
            local record = acceptRecord(rawRecord)
            if record then
                local bucket = working[record.namespace][record.hash]
                if bucket == nil then
                    bucket = {}
                    working[record.namespace][record.hash] = bucket
                end
                local key = record.name:lower()
                bucket[key] = mergeAccepted(bucket[key], record)
            end
        end
    end

    for _, namespace in ipairs(state.namespaceOrder) do
        for hash, byName in pairs(working[namespace]) do
            local candidates = {}
            overlay[namespace][hash] = candidates
            for _, record in pairs(byName) do candidates[#candidates + 1] = record end
            table.sort(candidates, function(left, right)
                local leftName, rightName = left.name:lower(), right.name:lower()
                if leftName == rightName then return left.name < right.name end
                return leftName < rightName
            end)
        end
    end

    state.setOverlay(overlay, version)
    for pendingVersion in pairs(assemblies) do
        if pendingVersion <= version then assemblies[pendingVersion] = nil end
    end
end

local function receiveBatch(version, index, total, records)
    if type(version) ~= 'number' or version % 1 ~= 0 or version < 1
        or type(index) ~= 'number' or index % 1 ~= 0
        or type(total) ~= 'number' or total % 1 ~= 0 or total < 1
        or index < 1 or index > total or total > 10000 or type(records) ~= 'table' then
        return
    end
    if version <= state.overlayVersion then return end

    local assembly = assemblies[version]
    if assembly == nil then
        assembly = { total = total, received = 0, batches = {} }
        assemblies[version] = assembly
    elseif assembly.total ~= total then
        -- A version is immutable. Conflicting framing is discarded rather
        -- than risking publication of a mixed snapshot.
        assemblies[version] = nil
        return
    end

    if assembly.batches[index] ~= nil then return end
    assembly.batches[index] = records
    assembly.received = assembly.received + 1
    if assembly.received == assembly.total then publish(version, assembly) end
end

state.receiveBatch = receiveBatch
QB.events.onPush(SYNC_PUSH, receiveBatch)

-- QB.events.trigger waits for the secure handshake. If the server is still
-- scanning, request again periodically until an atomic snapshot is published.
CreateThread(function()
    while not state.overlayReady do
        QB.events.trigger(SYNC_REQUEST)
        if not state.overlayReady then Wait(4000) end
    end
end)
