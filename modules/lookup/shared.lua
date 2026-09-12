---@alias QBLookupNamespace 'vehicle'|'ped'|'object'|'weapon'|'weapon_component'|'pickup'

local UINT32 = 4294967296
local INT32_MIN = -2147483648
local UINT32_MAX = 4294967295
local COMMON_FIELDS = { 'label', 'labelKey', 'category', 'dlc' }
local MODEL_NAMESPACES = { 'vehicle', 'ped', 'object' }

local NAMESPACE_ORDER = {
    'vehicle',
    'ped',
    'object',
    'weapon',
    'weapon_component',
    'pickup',
}

local NAMESPACES = {}
for i = 1, #NAMESPACE_ORDER do NAMESPACES[NAMESPACE_ORDER[i]] = true end

local state = {
    base = {},
    materialized = {},
    resolved = {},
    overlay = {},
    overlayReady = false,
    overlayVersion = 0,
    namespaceOrder = NAMESPACE_ORDER,
    namespaces = NAMESPACES,
}

for namespaceIndex = 1, #NAMESPACE_ORDER do
    local namespace = NAMESPACE_ORDER[namespaceIndex]
    state.materialized[namespace] = {}
    state.resolved[namespace] = {}
    state.overlay[namespace] = {}
end

-- Realm-specific lookup files share state through this deliberately non-exported
-- table. build/finalise.lua only exports direct function values, so consumers
-- cannot reach it through the QB proxy.
QB.lookup._state = state

local function trim(value)
    return value:match('^%s*(.-)%s*$')
end

---@param value integer|string
---@return integer hash
local function normalize(value)
    local valueType = type(value)

    if valueType == 'number' then
        assert(QB.util.isFiniteNumber(value),
            'Lookup hash must be a finite number.')
        assert(value % 1 == 0, 'Lookup hash must be an integer.')
        assert(value >= INT32_MIN and value <= UINT32_MAX,
            'Lookup hash must fit a signed or unsigned 32-bit integer.')
        return value < 0 and value + UINT32 or value
    end

    assert(valueType == 'string', 'Lookup value must be a hash or canonical name.')
    value = trim(value)
    assert(value ~= '', 'Lookup value must not be empty.')

    local parsed
    if value:match('^0[xX]') then
        assert(value:match('^0[xX][%da-fA-F]+$'), 'Lookup hexadecimal hash is malformed.')
        parsed = tonumber(value:sub(3), 16)
    elseif value:match('^[+-]?%d+$') then
        parsed = tonumber(value, 10)
    elseif value:match('^[+-]?[%d%.]+$') then
        error('Lookup decimal hash is malformed.', 2)
    end

    if parsed ~= nil then
        assert(parsed % 1 == 0 and parsed >= INT32_MIN and parsed <= UINT32_MAX,
            'Lookup hash must fit a signed or unsigned 32-bit integer.')
        return parsed < 0 and parsed + UINT32 or parsed
    end

    return joaat(value:lower()) % UINT32
end

local function signedHash(hash)
    return hash >= 2147483648 and hash - UINT32 or hash
end

local function shallowCopy(value)
    local copy = {}
    for key, entry in pairs(value or {}) do copy[key] = entry end
    return copy
end

local function copyArray(value)
    if type(value) ~= 'table' then return nil end
    local copy = {}
    for index = 1, #value do copy[index] = value[index] end
    return copy
end

local function materialize(namespace, hash, compact)
    local record = {
        namespace = namespace,
        hash = hash,
        signedHash = signedHash(hash),
        hexHash = ('0x%08X'):format(hash),
        name = compact[1],
        label = compact[2],
        labelKey = compact[3],
        category = compact[4],
        dlc = compact[5],
        source = 'base',
    }

    local metadata = {}
    if namespace == 'vehicle' then
        metadata.class = compact[4]
        metadata.manufacturer = compact[6]
        metadata.type = compact[7]
        metadata.seats = compact[8]
    elseif namespace == 'ped' then
        metadata.pedType = compact[6]
    elseif namespace == 'weapon' then
        metadata.modelName = compact[6]
        metadata.damageType = compact[7]
    elseif namespace == 'weapon_component' then
        metadata.weaponNames = copyArray(compact[6])
        metadata.componentType = compact[7]
        metadata.attachBone = compact[8]
    elseif namespace == 'pickup' then
        metadata.modelName = compact[6]
    end

    if next(metadata) ~= nil then record.metadata = metadata end
    return record
end

local function loadNamespace(namespace)
    local loaded = state.base[namespace]
    if loaded ~= nil then return loaded end

    local path = ('modules/lookup/data/%s.lua'):format(namespace)
    local raw = LoadResourceFile(GetCurrentResourceName(), path)
    assert(type(raw) == 'string', ('Lookup bundle is missing: %s'):format(path))

    local chunk, compileError = load(raw, ('@@%s/%s'):format(GetCurrentResourceName(), path), 't', {})
    assert(chunk, ('Lookup bundle failed to compile: %s'):format(tostring(compileError)))

    local ok, entries = pcall(chunk)
    assert(ok and type(entries) == 'table', ('Lookup bundle is invalid: %s'):format(path))
    state.base[namespace] = entries
    return entries
end

local function baseCandidates(namespace, hash)
    local cached = state.materialized[namespace][hash]
    if cached ~= nil then return cached end

    local compact = loadNamespace(namespace)[hash]
    local candidates = {}
    if type(compact) == 'table' then
        if type(compact[1]) == 'table' then
            for entryIndex = 1, #compact do
                local entry = compact[entryIndex]
                candidates[#candidates + 1] = materialize(namespace, hash, entry)
            end
        else
            candidates[1] = materialize(namespace, hash, compact)
        end
    end

    state.materialized[namespace][hash] = candidates
    return candidates
end

local function mergeResources(left, right)
    local seen, merged = {}, {}
    local function append(values)
        values = values or {}
        for resourceIndex = 1, #values do
            local resource = values[resourceIndex]
            if type(resource) == 'string' and not seen[resource] then
                seen[resource] = true
                merged[#merged + 1] = resource
            end
        end
    end
    append(left)
    append(right)
    table.sort(merged)
    return #merged > 0 and merged or nil
end

local function mergeRecords(base, custom)
    local merged = shallowCopy(base or custom)

    if base and custom then
        for i = 1, #COMMON_FIELDS do
            local field = COMMON_FIELDS[i]
            if custom[field] ~= nil then merged[field] = custom[field] end
        end
        merged.source = 'base+custom'
    elseif custom then
        merged.source = 'custom'
    end

    merged.resources = mergeResources(base and base.resources, custom and custom.resources)
    if base and custom and (base.metadata or custom.metadata) then
        merged.metadata = shallowCopy(base.metadata)
        for key, value in pairs(custom.metadata or {}) do merged.metadata[key] = value end
    elseif custom and custom.metadata then
        merged.metadata = shallowCopy(custom.metadata)
    end

    return merged
end

local function resolvedCandidates(namespace, hash)
    local cached = state.resolved[namespace][hash]
    if cached ~= nil then return cached end

    local byName = {}
    local baseRecords = baseCandidates(namespace, hash)
    for recordIndex = 1, #baseRecords do
        local record = baseRecords[recordIndex]
        byName[record.name:lower()] = record
    end

    local customRecords = state.overlay[namespace][hash] or {}
    for customIndex = 1, #customRecords do
        local custom = customRecords[customIndex]
        local key = custom.name:lower()
        byName[key] = mergeRecords(byName[key], custom)
    end

    local candidates = {}
    for _, record in pairs(byName) do candidates[#candidates + 1] = record end
    table.sort(candidates, function(left, right)
        local leftName, rightName = left.name:lower(), right.name:lower()
        if leftName == rightName then return left.name < right.name end
        return leftName < rightName
    end)

    state.resolved[namespace][hash] = candidates
    return candidates
end

local function lookupHash(namespace, hash)
    local candidates = resolvedCandidates(namespace, hash)
    if #candidates == 1 then return candidates[1] end
    if #candidates > 1 then return nil, 'ambiguous', candidates end
    if not state.overlayReady then return nil, 'catalog_pending' end
    return nil, 'not_found'
end

local function setOverlay(overlay, version)
    local normalized = {}
    for i = 1, #NAMESPACE_ORDER do
        local namespace = NAMESPACE_ORDER[i]
        normalized[namespace] = overlay[namespace] or {}
    end
    state.overlay = normalized
    state.overlayReady = true
    state.overlayVersion = version or (state.overlayVersion + 1)
    state.resolved = {}
    for i = 1, #NAMESPACE_ORDER do state.resolved[NAMESPACE_ORDER[i]] = {} end
end

state.normalize = normalize
state.setOverlay = setOverlay

---Returns a rich record for a hash or canonical name in one lookup namespace.
---@param namespace QBLookupNamespace
---@param value integer|string
---@return table? record
---@return string? reason
---@return table[]? candidates
function QB.lookup.get(namespace, value)
    assert(NAMESPACES[namespace], ('Unknown lookup namespace: %s'):format(tostring(namespace)))
    return lookupHash(namespace, normalize(value))
end

---Looks up a vehicle, ped, or object model. Without `kind`, all three model
---namespaces are considered and a cross-namespace collision is ambiguous.
---@param value integer|string
---@param kind? 'vehicle'|'ped'|'object'
---@return table? record
---@return string? reason
---@return table[]? candidates
function QB.lookup.model(value, kind)
    if kind ~= nil then
        assert(kind == 'vehicle' or kind == 'ped' or kind == 'object',
            'Model lookup kind must be vehicle, ped, or object.')
        return QB.lookup.get(kind, value)
    end

    local hash = normalize(value)
    local candidates = {}
    for i = 1, #MODEL_NAMESPACES do
        local namespace = MODEL_NAMESPACES[i]
        local records = resolvedCandidates(namespace, hash)
        for recordIndex = 1, #records do
            local record = records[recordIndex]
            candidates[#candidates + 1] = record
        end
    end

    if #candidates == 1 then return candidates[1] end
    if #candidates > 1 then return nil, 'ambiguous', candidates end
    if not state.overlayReady then return nil, 'catalog_pending' end
    return nil, 'not_found'
end

---@param value integer|string
---@return table? record
---@return string? reason
---@return table[]? candidates
function QB.lookup.weapon(value)
    return QB.lookup.get('weapon', value)
end

---@param value integer|string
---@return table? record
---@return string? reason
---@return table[]? candidates
function QB.lookup.weaponComponent(value)
    return QB.lookup.get('weapon_component', value)
end

---@param value integer|string
---@return table? record
---@return string? reason
---@return table[]? candidates
function QB.lookup.pickup(value)
    return QB.lookup.get('pickup', value)
end

---Loads selected base namespaces, or all namespaces when omitted.
---@param selected? QBLookupNamespace|QBLookupNamespace[]
---@return boolean
function QB.lookup.preload(selected)
    if selected == nil then
        selected = NAMESPACE_ORDER
    elseif type(selected) == 'string' then
        selected = { selected }
    else
        assert(type(selected) == 'table', 'Lookup preload expects a namespace or array of namespaces.')
    end

    for namespaceIndex = 1, #selected do
        local namespace = selected[namespaceIndex]
        assert(NAMESPACES[namespace], ('Unknown lookup namespace: %s'):format(tostring(namespace)))
        loadNamespace(namespace)
    end
    return true
end

---@return boolean
function QB.lookup.ready()
    return state.overlayReady
end

---@param timeout? integer Defaults to 10000ms.
---@return boolean ready
---@return string? error
function QB.lookup.awaitReady(timeout)
    timeout = timeout or 10000
    assert(type(timeout) == 'number' and timeout >= 0 and timeout % 1 == 0,
        'Lookup readiness timeout must be a non-negative integer.')
    if state.overlayReady then return true end

    local ready = QB.loops.controlled(function() return state.overlayReady end, false, timeout, 25)
    if ready then return true end
    return false, 'Lookup catalog synchronization timed out.'
end
