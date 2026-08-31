local state = QB.lookup._state
local SYNC_REQUEST = 'qblib:lookup:sync'
local SYNC_PUSH = 'qblib:lookup:syncBatch'
-- Leave framing headroom so the complete encoded event payload remains below
-- the requested 24 KiB boundary, not merely the JSON array within it.
local MAX_BATCH_BYTES = 23 * 1024
local MAX_SCANNED_FILE_BYTES = 16 * 1024 * 1024
local MAX_OVERRIDE_BYTES = 1024 * 1024

local pendingClients = {}
local snapshotBatches = nil
local MAX_RESOURCES_PER_WIRE_RECORD = 16

local function warn(message)
    print(('[qblib:lookup] %s'):format(message))
end

local function sortedKeys(values)
    local keys = {}
    for key in pairs(values) do keys[#keys + 1] = key end
    table.sort(keys, function(left, right)
        if type(left) == type(right) then return left < right end
        return tostring(left) < tostring(right)
    end)
    return keys
end

local function copyTable(value)
    if type(value) ~= 'table' then return nil end
    local copy = {}
    for key, entry in pairs(value) do copy[key] = entry end
    return copy
end

local function readResourceFile(resource, relativePath, maxBytes)
    local raw = LoadResourceFile(resource, relativePath)
    if type(raw) == 'string' then
        if #raw <= maxBytes then return raw end
        return nil, 'file is too large'
    end

    local ok, handle = pcall(io.open, ('@%s/%s'):format(resource, relativePath), 'rb')
    if not ok or handle == nil then return nil, 'file is unreadable' end
    local readOk, contents = pcall(function() return handle:read(maxBytes + 1) end)
    pcall(function() handle:close() end)
    if not readOk or type(contents) ~= 'string' then return nil, 'file is unreadable' end
    if #contents > maxBytes then return nil, 'file is too large' end
    return contents
end

local function readDirectory(path)
    if type(io.readdir) ~= 'function' then return nil end
    local ok, handle = pcall(io.readdir, path)
    if not ok or handle == nil then return nil end

    local entries = {}
    local iterOk, iterError = pcall(function()
        for name in handle:lines() do
            if name ~= '.' and name ~= '..' then entries[#entries + 1] = name end
        end
    end)
    pcall(function() handle:close() end)
    if not iterOk then
        warn(('could not list %s: %s'):format(path, tostring(iterError)))
        return nil
    end
    table.sort(entries)
    return entries
end

local skippedDirectories = {
    ['.git'] = true,
    ['node_modules'] = true,
    ['web'] = true,
    ['html'] = true,
    ['dist'] = true,
    ['build'] = true,
}

local function collectFiles(resource, mountPath, relativePath, includeAll, output, depth)
    if depth > 12 then return end
    local entries = readDirectory(mountPath)
    if entries == nil then return end

    for _, name in ipairs(entries) do
        local childMount = mountPath:gsub('/$', '') .. '/' .. name
        local childRelative = relativePath == '' and name or (relativePath .. '/' .. name)
        local childEntries = readDirectory(childMount)

        if childEntries ~= nil then
            if includeAll or not skippedDirectories[name:lower()] then
                collectFiles(resource, childMount, childRelative, includeAll, output, depth + 1)
            end
        else
            local lower = name:lower()
            if includeAll then
                if lower:match('%.ydr$') or lower:match('%.yft$') or lower:match('%.ytyp$')
                    or lower:match('%.meta$') or lower:match('%.xml$') then
                    output[#output + 1] = childRelative
                end
            elseif lower:match('%.meta$') or lower:match('%.xml$') or lower:match('%.ytyp$') then
                output[#output + 1] = childRelative
            end
        end
    end
end

local function resourceFiles(resource)
    local files, seen = {}, {}
    local streamMount = ('@%s/stream'):format(resource)
    if readDirectory(streamMount) ~= nil then
        collectFiles(resource, streamMount, 'stream', true, files, 0)
    end
    collectFiles(resource, ('@%s/'):format(resource), '', false, files, 0)

    local unique = {}
    for _, path in ipairs(files) do
        if not seen[path] then
            seen[path] = true
            unique[#unique + 1] = path
        end
    end
    table.sort(unique)
    return unique
end

local function xmlValue(value)
    if type(value) ~= 'string' then return nil end
    value = value:gsub('&lt;', '<'):gsub('&gt;', '>'):gsub('&quot;', '"')
        :gsub('&apos;', "'"):gsub('&amp;', '&')
    value = value:match('^%s*(.-)%s*$')
    return value ~= '' and value or nil
end

local function tag(block, name)
    return xmlValue(block:match('<' .. name .. '[^>]*>(.-)</' .. name .. '>'))
end

local function boundedString(value, maxLength)
    if type(value) ~= 'string' then return nil end
    value = value:match('^%s*(.-)%s*$')
    if value == '' or #value > (maxLength or 256) then return nil end
    return value
end

local function inferredRecord(namespace, name, resource, fields)
    name = boundedString(name, 128)
    if name == nil then return nil end

    local metadata = fields and copyTable(fields.metadata) or nil
    for key, value in pairs(metadata or {}) do
        if type(value) == 'string' then metadata[key] = boundedString(value) end
    end
    local hash = state.normalize(name)
    local record = {
        namespace = namespace,
        hash = hash,
        signedHash = hash >= 2147483648 and hash - 4294967296 or hash,
        hexHash = ('0x%08X'):format(hash),
        name = name,
        label = fields and boundedString(fields.label) or nil,
        labelKey = fields and boundedString(fields.labelKey) or nil,
        category = fields and boundedString(fields.category) or nil,
        dlc = fields and boundedString(fields.dlc) or nil,
        source = 'custom',
        resources = { resource },
        metadata = metadata,
        _priority = fields and fields.priority or 1,
    }
    if record.metadata and next(record.metadata) == nil then record.metadata = nil end
    return record
end

local function parseVehicleMetadata(raw, resource, records)
    for item in raw:gmatch('<Item[^>]*>(.-)</Item>') do
        local name = tag(item, 'modelName')
        if name then
            local class = tag(item, 'vehicleClass')
            if class then class = class:gsub('^VC_', ''):lower() end
            local vehicleType = tag(item, 'type')
            if vehicleType then vehicleType = vehicleType:gsub('^VEHICLE_TYPE_', ''):lower() end
            local labelKey = tag(item, 'gameName')
            records[#records + 1] = inferredRecord('vehicle', name, resource, {
                label = labelKey,
                labelKey = labelKey,
                category = class,
                metadata = {
                    class = class,
                    manufacturer = tag(item, 'vehicleMakeName'),
                    type = vehicleType,
                },
            })
        end
    end
end

local function parsePedMetadata(raw, resource, records)
    for item in raw:gmatch('<Item[^>]*>(.-)</Item>') do
        local name = tag(item, 'Name')
        if name and not name:match('^WEAPON_') and not name:match('^COMPONENT_') then
            local pedType = tag(item, 'Pedtype')
            records[#records + 1] = inferredRecord('ped', name, resource, {
                category = pedType and pedType:lower() or nil,
                metadata = { pedType = pedType },
            })
        end
    end
end

local function parseWeaponMetadata(raw, resource, records)
    local seen = {}
    for name in raw:gmatch('<Name[^>]*>%s*(WEAPON_[%w_]+)%s*</Name>') do
        local key = name:lower()
        if not seen['weapon:' .. key] then
            seen['weapon:' .. key] = true
            records[#records + 1] = inferredRecord('weapon', name, resource)
        end
    end
    for name in raw:gmatch('<Name[^>]*>%s*(COMPONENT_[%w_]+)%s*</Name>') do
        local key = name:lower()
        if not seen['component:' .. key] then
            seen['component:' .. key] = true
            records[#records + 1] = inferredRecord('weapon_component', name, resource)
        end
    end
end

local function parseTextYtyp(raw, resource, records)
    if raw:find('\0', 1, true) then return false end
    local found = false
    for name in raw:gmatch('<name[^>]*>%s*([^<]-)%s*</name>') do
        name = xmlValue(name)
        if name then
            found = true
            records[#records + 1] = inferredRecord('object', name, resource, { category = 'object' })
        end
    end
    return found
end

local function decodeOverride(resource)
    local raw, readError = readResourceFile(resource, 'qblib.lookup.json', MAX_OVERRIDE_BYTES)
    if raw == nil then
        if readError == 'file is too large' then
            warn(('%s/qblib.lookup.json is too large and was ignored'):format(resource))
        end
        return nil
    end
    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' then
        warn(('%s/qblib.lookup.json is not valid JSON and was ignored'):format(resource))
        return nil
    end
    return decoded
end


local metadataFields = {
    vehicle = { class = 'string', manufacturer = 'string', type = 'string', seats = 'integer' },
    ped = { pedType = 'string' },
    weapon = { modelName = 'string', damageType = 'string' },
    weapon_component = { weaponNames = 'strings', componentType = 'string', attachBone = 'string' },
    pickup = { modelName = 'string' },
    object = {},
}

local function validateMetadata(namespace, value)
    if value == nil then return nil end
    if type(value) ~= 'table' then return false end

    local accepted, definition = {}, metadataFields[namespace]
    for field in pairs(value) do
        if definition[field] == nil then return false end
    end
    for field, fieldType in pairs(definition) do
        local entry = value[field]
        if entry ~= nil then
            if fieldType == 'string' then
                entry = boundedString(entry)
                if entry == nil then return false end
                accepted[field] = entry
            elseif fieldType == 'integer' then
                if type(entry) ~= 'number' or entry % 1 ~= 0 or entry < 0 or entry > 64 then return false end
                accepted[field] = entry
            elseif fieldType == 'strings' then
                if type(entry) ~= 'table' or #entry > 64 then return false end
                local seen, values, count = {}, {}, 0
                for key in pairs(entry) do
                    count = count + 1
                    if type(key) ~= 'number' or key % 1 ~= 0 or key < 1 or key > #entry then return false end
                end
                if count ~= #entry then return false end
                for _, item in ipairs(entry) do
                    item = boundedString(item, 128)
                    if item == nil then return false end
                    if not seen[item] then
                        seen[item] = true
                        values[#values + 1] = item
                    end
                end
                table.sort(values)
                accepted[field] = values
            end
        end
    end
    return next(accepted) and accepted or nil
end

local function validateOverrideEntry(resource, entry)
    local name = type(entry) == 'table' and boundedString(entry.name, 128) or nil
    if type(entry) ~= 'table' or not state.namespaces[entry.namespace] or name == nil then
        warn(('%s has an invalid qblib.lookup.json entry'):format(resource))
        return nil
    end

    local computed = state.normalize(name)
    if entry.hash ~= nil then
        local ok, supplied = pcall(state.normalize, entry.hash)
        if not ok or supplied ~= computed then
            warn(('%s lookup override for %s has a hash that does not match its name'):format(resource, name))
            return nil
        end
    end

    local metadata = validateMetadata(entry.namespace, entry.metadata)
    if metadata == false then
        warn(('%s lookup override for %s has invalid metadata'):format(resource, name))
        return nil
    end

    local common = {}
    for _, field in ipairs({ 'label', 'labelKey', 'category', 'dlc' }) do
        if entry[field] ~= nil then
            common[field] = boundedString(entry[field])
            if common[field] == nil then
                warn(('%s lookup override for %s has an invalid %s'):format(resource, name, field))
                return nil
            end
        end
    end

    return inferredRecord(entry.namespace, name, resource, {
        label = common.label,
        labelKey = common.labelKey,
        category = common.category,
        dlc = common.dlc,
        metadata = metadata,
        priority = 2,
    })
end

local function scanResource(resource)
    local inferred, unresolvedYft, binaryYtyp = {}, 0, 0

    for _, path in ipairs(resourceFiles(resource)) do
        local lower = path:lower()
        local name = path:match('([^/]+)$') or path

        if lower:match('%.ydr$') then
            inferred[#inferred + 1] = inferredRecord('object', name:sub(1, -5), resource, { category = 'object' })
        elseif lower:match('%.yft$') then
            unresolvedYft = unresolvedYft + 1
        else
            local raw, readError = readResourceFile(resource, path, MAX_SCANNED_FILE_BYTES)
            if type(raw) == 'string' then
                if lower:match('%.ytyp$') then
                    if not parseTextYtyp(raw, resource, inferred) and raw:find('\0', 1, true) then
                        binaryYtyp = binaryYtyp + 1
                    end
                elseif raw:find('CVehicleModelInfo', 1, true) or lower:match('vehicles[^/]*%.meta$') then
                    parseVehicleMetadata(raw, resource, inferred)
                elseif raw:find('CPedModelInfo', 1, true) or lower:match('peds[^/]*%.meta$') then
                    parsePedMetadata(raw, resource, inferred)
                elseif raw:find('WEAPON_', 1, true) or raw:find('COMPONENT_', 1, true) then
                    parseWeaponMetadata(raw, resource, inferred)
                end
            elseif readError then
                warn(('%s/%s %s and was ignored'):format(resource, path, readError))
            end
        end
    end

    local override = decodeOverride(resource) or {}
    local overrideEntries = override.entries
    local overrideExclusions = override.exclude
    if overrideEntries ~= nil and type(overrideEntries) ~= 'table' then
        warn(('%s qblib.lookup.json entries must be an array and were ignored'):format(resource))
        overrideEntries = {}
    end
    if overrideExclusions ~= nil and type(overrideExclusions) ~= 'table' then
        warn(('%s qblib.lookup.json exclude must be an array and was ignored'):format(resource))
        overrideExclusions = {}
    end

    local excluded = {}
    for _, entry in ipairs(overrideExclusions or {}) do
        local name = type(entry) == 'table' and boundedString(entry.name, 128) or nil
        if type(entry) == 'table' and state.namespaces[entry.namespace] and name then
            excluded[entry.namespace .. ':' .. name:lower()] = true
        else
            warn(('%s has an invalid qblib.lookup.json exclusion'):format(resource))
        end
    end

    local records = {}
    for _, record in ipairs(inferred) do
        if not excluded[record.namespace .. ':' .. record.name:lower()] then
            records[#records + 1] = record
        end
    end
    for _, entry in ipairs(overrideEntries or {}) do
        local record = validateOverrideEntry(resource, entry)
        if record then records[#records + 1] = record end
    end

    if unresolvedYft > 0 or binaryYtyp > 0 then
        warn(('%s left %d .yft and %d binary .ytyp files unclassified; add qblib.lookup.json entries if needed')
            :format(resource, unresolvedYft, binaryYtyp))
    end
    return records
end

local function mergeResourceNames(left, right)
    local seen, values = {}, {}
    for _, list in ipairs({ left, right }) do
        for _, resource in ipairs(list or {}) do
            if not seen[resource] then
                seen[resource] = true
                values[#values + 1] = resource
            end
        end
    end
    table.sort(values)
    return values
end

local function addWorking(working, record)
    local byHash = working[record.namespace]
    local bucket = byHash[record.hash]
    if bucket == nil then bucket = {}; byHash[record.hash] = bucket end

    local key = record.name:lower()
    local current = bucket[key]
    if current == nil then
        bucket[key] = record
        return
    end

    local resources = mergeResourceNames(current.resources, record.resources)
    if (record._priority or 1) > (current._priority or 1) then
        record.resources = resources
        for _, field in ipairs({ 'label', 'labelKey', 'category', 'dlc' }) do
            if record[field] == nil then record[field] = current[field] end
        end
        local metadata = copyTable(current.metadata) or {}
        for field, value in pairs(record.metadata or {}) do metadata[field] = value end
        record.metadata = next(metadata) and metadata or nil
        bucket[key] = record
        return
    end

    current.resources = resources
    for _, field in ipairs({ 'label', 'labelKey', 'category', 'dlc' }) do
        if current[field] == nil then current[field] = record[field] end
    end
    current.metadata = current.metadata or {}
    for field, value in pairs(record.metadata or {}) do
        if current.metadata[field] == nil then current.metadata[field] = value end
    end
    if next(current.metadata) == nil then current.metadata = nil end
end

local function finalizeOverlay(working)
    local overlay, total = {}, 0
    for _, namespace in ipairs(state.namespaceOrder) do
        overlay[namespace] = {}
        for hash, byName in pairs(working[namespace]) do
            local candidates = {}
            for _, name in ipairs(sortedKeys(byName)) do
                local record = byName[name]
                record._priority = nil
                candidates[#candidates + 1] = record
                total = total + 1
            end
            overlay[namespace][hash] = candidates
        end
    end
    return overlay, total
end

local function scanAll()
    local working = {}
    for _, namespace in ipairs(state.namespaceOrder) do working[namespace] = {} end

    local resources = {}
    for index = 0, GetNumResources() - 1 do
        local resource = GetResourceByFindIndex(index)
        if resource and resource ~= GetCurrentResourceName() then resources[#resources + 1] = resource end
    end
    table.sort(resources)

    for _, resource in ipairs(resources) do
        local ok, records = pcall(scanResource, resource)
        if ok then
            for _, record in ipairs(records) do addWorking(working, record) end
        else
            warn(('%s could not be scanned and was skipped: %s'):format(resource, tostring(records)))
        end
        Wait(0)
    end

    return finalizeOverlay(working)
end

state.scanResource = scanResource
state.scanAll = scanAll

local function flattenOverlay()
    local records = {}
    for _, namespace in ipairs(state.namespaceOrder) do
        for _, hash in ipairs(sortedKeys(state.overlay[namespace])) do
            for _, record in ipairs(state.overlay[namespace][hash]) do
                local resources = record.resources or {}
                if #resources <= MAX_RESOURCES_PER_WIRE_RECORD then
                    records[#records + 1] = record
                else
                    -- One popular model can be contributed by many resources.
                    -- Split only its attribution list on the wire so no single
                    -- record can defeat the bounded batch size; the client
                    -- merges these identical name/hash fragments again.
                    for first = 1, #resources, MAX_RESOURCES_PER_WIRE_RECORD do
                        local fragment = copyTable(record)
                        fragment.resources = {}
                        for index = first, math.min(#resources, first + MAX_RESOURCES_PER_WIRE_RECORD - 1) do
                            fragment.resources[#fragment.resources + 1] = resources[index]
                        end
                        records[#records + 1] = fragment
                    end
                end
            end
        end
    end
    return records
end

local function recordSize(record)
    local ok, encoded = pcall(json.encode, record)
    return ok and (#encoded + 1) or 1024
end

local function buildBatches()
    local batches, batch, size = {}, {}, 2
    for _, record in ipairs(flattenOverlay()) do
        local bytes = recordSize(record)
        if #batch > 0 and size + bytes > MAX_BATCH_BYTES then
            batches[#batches + 1] = batch
            batch, size = {}, 2
        end
        batch[#batch + 1] = record
        size = size + bytes
    end
    if #batch > 0 or #batches == 0 then batches[#batches + 1] = batch end
    return batches
end

state.buildBatches = buildBatches

local function sendSnapshot(target)
    snapshotBatches = snapshotBatches or buildBatches()
    for index, batch in ipairs(snapshotBatches) do
        QB.events.push(target, SYNC_PUSH, state.overlayVersion, index, #snapshotBatches, batch)
    end
end

QB.events.register(SYNC_REQUEST, function(src)
    if not state.overlayReady then
        pendingClients[src] = true
        return
    end
    sendSnapshot(src)
end, { rateLimit = { max = 3, window = 10000 } })

AddEventHandler('playerDropped', function()
    pendingClients[source] = nil
end)

CreateThread(function()
    local overlay, total = scanAll()
    state.setOverlay(overlay, 1)
    snapshotBatches = buildBatches()
    warn(('custom catalog ready: %d records across %d client batches'):format(total, #snapshotBatches))

    for src in pairs(pendingClients) do sendSnapshot(src) end
    pendingClients = {}
end)
