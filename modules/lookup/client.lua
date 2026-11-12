local state = Kora.lookup._state
local SYNC_REQUEST = 'kora_lib:lookup:sync'
local SYNC_PUSH = 'kora_lib:lookup:syncBatch'
local COMMON_FIELDS = { 'label', 'labelKey', 'category', 'dlc' }

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
    for entryIndex = 1, #value do
        local entry = value[entryIndex]
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
    for i = 1, #COMMON_FIELDS do
        local field = COMMON_FIELDS[i]
        if current[field] == nil then current[field] = incoming[field] end
    end
    current.metadata = current.metadata or {}
    for field, value in pairs(incoming.metadata or {}) do
        if current.metadata[field] == nil then current.metadata[field] = value end
    end
    if next(current.metadata) == nil then current.metadata = nil end

    local seen = {}
    local currentResources = current.resources or {}
    for resourceIndex = 1, #currentResources do seen[currentResources[resourceIndex]] = true end
    local incomingResources = incoming.resources or {}
    for resourceIndex = 1, #incomingResources do
        local resource = incomingResources[resourceIndex]
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
    for namespaceIndex = 1, #state.namespaceOrder do
        local namespace = state.namespaceOrder[namespaceIndex]
        overlay[namespace] = {}
        working[namespace] = {}
    end

    for index = 1, assembly.total do
        local batch = assembly.batches[index]
        for recordIndex = 1, #batch do
            local rawRecord = batch[recordIndex]
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

    for namespaceIndex = 1, #state.namespaceOrder do
        local namespace = state.namespaceOrder[namespaceIndex]
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
        assemblies[version] = nil
        return
    end

    if assembly.batches[index] ~= nil then return end
    assembly.batches[index] = records
    assembly.received = assembly.received + 1
    if assembly.received == assembly.total then publish(version, assembly) end
end

state.receiveBatch = receiveBatch
Kora.events.onPush(SYNC_PUSH, receiveBatch)

CreateThread(function()
    while not state.overlayReady do
        Kora.events.trigger(SYNC_REQUEST)
        if not state.overlayReady then Wait(4000) end
    end
end)
