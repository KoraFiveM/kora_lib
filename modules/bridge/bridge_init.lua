local isServer = IsDuplicityVersion()
local realm = isServer and 'server' or 'client'
local providers = {}
local resourceAreas = {}
local resourceStates = {}
local resolutions = {}
local failedProviders = {}
local unavailableLogged = {}

-- Adapter module names are also their resource names by convention. Add an entry
-- here when a provider module is added so auto mode can inspect its resource state.
local providerCatalog = {
    banking = { kora_banking = 'kora_banking' },
    bossmenu = { kora_bossmenu = 'kora_bossmenu' },
    clothing = { kora_clothing = 'kora_clothing' },
    dispatch = { kora_dispatch = 'kora_dispatch' },
    doorlock = { kora_doorlock = 'kora_doorlock' },
    fuel = { kora_fuel = 'kora_fuel' },
    helptext = { kora_lib = 'kora_lib' },
    notify = { kora_lib = 'kora_lib' },
    vehiclekeys = { kora_vehiclekeys = 'kora_vehiclekeys' },
}

local contracts = {
    banking = {
        server = {
            'addSocietyMoney', 'removeSocietyMoney', 'getSocietyAccountBalance', 'executeSocietyTransaction',
            'createSocietyBankStatement',
        },
    },
    bossmenu = {
        client = {
            'openBossMenu', 'openApplication', 'addBossMenuItem', 'removeBossMenuItem', 'addGangMenuItem',
            'removeGangMenuItem',
        },
        server = {
            'addBusinessMoney', 'removeBusinessMoney', 'getBusinessBalance', 'bossmenuAddMoney', 'bossmenuRemoveMoney',
            'addGangMoney', 'removeGangMoney', 'getGangBalance',
        },
    },
    clothing = {
        client = { 'openWardrobe', 'openClothingRoom', 'applyAppearanceToPed', 'applyStarterAppearance', 'reloadSkin' },
        server = { 'openAdminSession' },
    },
    dispatch = {
        server = { 'createCall', 'updateCall', 'closeCall', 'getCalls', 'registerPlayerAlert', 'createPlayerCall' },
    },
    doorlock = {
        client = { 'getClosestDoor', 'getDoorState', 'pickClosestDoor' },
        server = { 'getDoorState', 'setDoorState', 'createDoor', 'registerDoorPolicy' },
    },
    fuel = {
        client = { 'getFuel', 'setFuel', 'isElectricVehicle' },
    },
    helptext = {
        client = { 'showHelpText', 'updateHelpText', 'hideHelpText' },
    },
    notify = {
        client = { 'sendNotification' },
    },
    vehiclekeys = {
        server = { 'giveKeys', 'removeKeys', 'hasKeys' },
    },
}

local function clearResolution(area)
    resolutions[area] = nil
    unavailableLogged[area] = nil
end

local function resourceChanged(resource)
    local affected = resourceAreas[resource]
    if not affected then return end

    resourceStates[resource] = nil
    for area in pairs(affected) do clearResolution(area) end
end

if type(AddEventHandler) == 'function' then
    AddEventHandler('onResourceStart', resourceChanged)
    AddEventHandler('onResourceStop', resourceChanged)
    AddEventHandler('onClientResourceStart', resourceChanged)
    AddEventHandler('onClientResourceStop', resourceChanged)
end

for area, catalog in pairs(providerCatalog) do
    for _, resourceName in pairs(catalog) do
        resourceAreas[resourceName] = resourceAreas[resourceName] or {}
        resourceAreas[resourceName][area] = true
    end
end

local function isStarted(resource)
    local state = resourceStates[resource]
    if state == nil then
        local ok, result = pcall(GetResourceState, resource)
        state = ok and result or 'missing'
        resourceStates[resource] = state
    end
    return state == 'started'
end

local function getConfiguredProvider(area)
    local bridgeConfig = type(Config) == 'table' and Config.bridge or nil
    local configured = type(bridgeConfig) == 'table' and bridgeConfig[area] or nil
    if configured == nil then return 'auto' end
    if type(configured) ~= 'string' or configured == '' then return nil end
    return configured
end

local function getProviderCandidates(area)
    local candidates = {}
    local seen = {}
    for providerName, resourceName in pairs(providerCatalog[area] or {}) do
        candidates[#candidates + 1] = { name = providerName, resource = resourceName }
        seen[providerName] = true
    end
    for providerName in pairs(providers[area] or {}) do
        if not seen[providerName] then
            candidates[#candidates + 1] = { name = providerName, resource = providerName }
        end
    end
    return candidates
end

local function loadModuleFile(path, adapter)
    local readOk, source = pcall(LoadResourceFile, 'kora_lib', path)
    if not readOk then return false, source, false end
    if not source then return true, nil, false end

    local chunk, compileError = load(source, ('@@kora_lib/%s'):format(path), 't', _ENV)
    if not chunk then return false, compileError, true end

    local originalBridge = Kora.bridge
    local stagedBridge = setmetatable({}, { __index = originalBridge })
    Kora.bridge = stagedBridge
    local ok, loadError = pcall(chunk)
    Kora.bridge = originalBridge
    if not ok then return false, loadError, true end

    local loadedAny = false
    for method, callback in pairs(stagedBridge) do
        if type(callback) == 'function' then
            if adapter[method] then
                return false, ('Duplicate bridge method %q in %s.'):format(method, path), true
            end
            adapter[method] = callback
            loadedAny = true
        end
    end
    return true, nil, loadedAny
end

local function loadProvider(area, providerName)
    if providers[area] and providers[area][providerName] then return true end
    if failedProviders[area] and failedProviders[area][providerName] then return false end

    local resourceName = providerCatalog[area] and providerCatalog[area][providerName]
    if not resourceName then return false end

    local pathRoot = ('modules/bridge/modules/%s/%s/'):format(area, providerName)
    local adapter = {}
    local loadedAny = false
    for _, fileName in ipairs({ 'shared.lua', realm .. '.lua' }) do
        local ok, loadError, loadedFile = loadModuleFile(pathRoot .. fileName, adapter)
        if not ok then
            failedProviders[area] = failedProviders[area] or {}
            failedProviders[area][providerName] = true
            return false, loadError
        end
        loadedAny = loadedAny or loadedFile
    end

    if not loadedAny then
        failedProviders[area] = failedProviders[area] or {}
        failedProviders[area][providerName] = true
        return false, 'Provider module files were not found.'
    end

    local ok, result = pcall(Kora.bridge.register, area, providerName, adapter)
    if not ok then
        failedProviders[area] = failedProviders[area] or {}
        failedProviders[area][providerName] = true
        return false, result
    end

    return true
end

local function resolveProvider(area)
    local configured = getConfiguredProvider(area)
    if not configured then return nil end

    local cached = resolutions[area]
    if cached and cached.configured == configured then return cached.provider end

    local selected
    if configured == 'auto' then
        local candidates = getProviderCandidates(area)
        table.sort(candidates, function(left, right)
            local leftKora = left.name:match('^kora_') ~= nil
            local rightKora = right.name:match('^kora_') ~= nil
            if leftKora ~= rightKora then return leftKora end
            return left.name < right.name
        end)
        for _, candidate in ipairs(candidates) do
            if isStarted(candidate.resource) then
                selected = candidate.name
                break
            end
        end
    else
        local candidates = providerCatalog[area] or {}
        local resourceName = candidates[configured] or configured
        if (candidates[configured] or (providers[area] and providers[area][configured])) and isStarted(resourceName) then
            selected = configured
        end
    end

    resolutions[area] = { configured = configured, provider = selected }
    return selected
end

---Registers a provider adapter after validating its current-realm contract.
---@param area KoraBridgeArea
---@param providerName string Adapter module name and provider key.
---@param adapter table<string, function>
---@return boolean registered
function Kora.bridge.register(area, providerName, adapter)
    assert(type(area) == 'string' and contracts[area], ('Unknown bridge area %q.'):format(tostring(area)))
    assert(type(providerName) == 'string' and providerName ~= '' and not providerName:find('[@%c/\\]'),
        'Bridge provider name must be a module name.')
    assert(type(adapter) == 'table', 'Bridge adapter must be a table.')

    local required = contracts[area][realm]
    assert(required, ('Bridge area %q is not available in the %s realm.'):format(area, realm))
    for _, method in ipairs(required) do
        assert(type(adapter[method]) == 'function',
            ('Bridge adapter %q for %q is missing required function %q.'):format(providerName, area, method))
    end

    providers[area] = providers[area] or {}
    assert(not providers[area][providerName],
        ('Bridge provider %q is already registered for %q.'):format(providerName, area))
    providers[area][providerName] = adapter
    local resourceName = providerCatalog[area] and providerCatalog[area][providerName] or providerName
    resourceAreas[resourceName] = resourceAreas[resourceName] or {}
    resourceAreas[resourceName][area] = true
    resourceStates[resourceName] = nil
    clearResolution(area)
    return true
end

---Returns the selected started provider module name, or nil when unavailable.
---@param area KoraBridgeArea
---@return string|nil providerName
function Kora.bridge.getProvider(area)
    assert(type(area) == 'string' and contracts[area], ('Unknown bridge area %q.'):format(tostring(area)))
    return resolveProvider(area)
end

local function logUnavailable(area, providerName, method)
    if unavailableLogged[area] then return end
    unavailableLogged[area] = true
    pcall(Kora.logging.error, 'bridge.provider_unavailable', 'No started bridge provider is available.', {
        area = area,
        provider = providerName,
        method = method,
    })
end

local function logCallFailure(area, providerName, method)
    pcall(Kora.logging.error, 'bridge.provider_call_failed', 'A bridge provider call failed.', {
        area = area,
        provider = providerName,
        method = method,
    })
end

local function logLoadFailure(area, providerName, method)
    pcall(Kora.logging.error, 'bridge.provider_load_failed', 'A bridge provider module could not be loaded.', {
        area = area,
        provider = providerName,
        method = method,
    })
end

-- Internal dispatch lives under compat because build/finalise.lua intentionally
-- excludes that table from consumer exports.
Kora.compat.bridgeCall = function(area, method, fallback, ...)
    local providerName = resolveProvider(area)
    if not providerName then
        logUnavailable(area, getConfiguredProvider(area), method)
        return table.unpack(fallback, 1, fallback.n)
    end

    local loaded = loadProvider(area, providerName)
    local adapter = loaded and providers[area] and providers[area][providerName]
    local target = adapter and adapter[method]
    if not loaded or type(target) ~= 'function' then
        logLoadFailure(area, providerName, method)
        return table.unpack(fallback, 1, fallback.n)
    end

    local result = table.pack(pcall(target, ...))
    if not result[1] then
        logCallFailure(area, providerName, method)
        return table.unpack(fallback, 1, fallback.n)
    end
    return table.unpack(result, 2, result.n)
end

-- Select and load the configured adapter during initialization. If none is started yet,
-- the first bridge call after its resource starts will resolve and load it then.
for area in pairs(providerCatalog) do
    local providerName = resolveProvider(area)
    if providerName then loadProvider(area, providerName) end
end
