local isServer = IsDuplicityVersion()
local realm = isServer and 'server' or 'client'
local selectedProviders = {}
local loadedMethods = {}
local resourceAreas = {}
local resourceStates = {}

-- Map each provider folder to its resource so auto mode can select a started provider.
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
    banking = { server = { 'addSocietyMoney', 'removeSocietyMoney', 'getSocietyAccountBalance', 'executeSocietyTransaction', 'createSocietyBankStatement' } },
    bossmenu = {
        client = { 'openBossMenu', 'openApplication', 'addBossMenuItem', 'removeBossMenuItem', 'addGangMenuItem', 'removeGangMenuItem' },
        server = { 'addBusinessMoney', 'removeBusinessMoney', 'getBusinessBalance', 'bossmenuAddMoney', 'bossmenuRemoveMoney', 'addGangMoney', 'removeGangMoney', 'getGangBalance' },
    },
    clothing = {
        client = { 'openWardrobe', 'openClothingRoom', 'applyAppearanceToPed', 'applyStarterAppearance', 'reloadSkin' },
        server = { 'openAdminSession' },
    },
    dispatch = { server = { 'createCall', 'updateCall', 'closeCall', 'getCalls', 'registerPlayerAlert', 'createPlayerCall' } },
    doorlock = {
        client = { 'getClosestDoor', 'getDoorState', 'pickClosestDoor' },
        server = { 'getDoorState', 'setDoorState', 'createDoor', 'registerDoorPolicy' },
    },
    fuel = { client = { 'getFuel', 'setFuel', 'isElectricVehicle' } },
    helptext = { client = { 'showHelpText', 'updateHelpText', 'hideHelpText' } },
    notify = { client = { 'sendNotification' } },
    vehiclekeys = { server = { 'giveKeys', 'removeKeys', 'hasKeys' } },
}

for area, catalog in pairs(providerCatalog) do
    for _, resourceName in pairs(catalog) do
        resourceAreas[resourceName] = resourceAreas[resourceName] or {}
        resourceAreas[resourceName][area] = true
    end
end

local function getResourceState(resource)
    if resourceStates[resource] == nil then
        local ok, state = pcall(GetResourceState, resource)
        resourceStates[resource] = ok and state or 'missing'
    end
    return resourceStates[resource]
end

local function chooseProvider(area)
    local configured = type(Config) == 'table' and type(Config.bridge) == 'table' and Config.bridge[area] or 'auto'
    local catalog = providerCatalog[area] or {}
    if type(configured) ~= 'string' or configured == '' then return nil end

    if configured ~= 'auto' then
        local resourceName = catalog[configured]
        if resourceName and getResourceState(resourceName) == 'started' then return configured end
        return nil
    end

    local candidates = {}
    for providerName, resourceName in pairs(catalog) do
        if getResourceState(resourceName) == 'started' then
            candidates[#candidates + 1] = { name = providerName, resource = resourceName }
        end
    end
    table.sort(candidates, function(left, right)
        local leftKora = left.name:match('^kora_') ~= nil
        local rightKora = right.name:match('^kora_') ~= nil
        if leftKora ~= rightKora then return leftKora end
        return left.name < right.name
    end)
    return candidates[1] and candidates[1].name or nil
end

local function reportLoadError(area, provider, err)
    pcall(Kora.logging.error, 'bridge.provider_load_failed', 'A bridge provider module could not be loaded.', {
        area = area,
        provider = provider,
        error = tostring(err),
    })
end

local function loadProvider(area, providerName)
    local required = contracts[area] and contracts[area][realm]
    if not required then return false end

    local pathRoot = ('modules/bridge/modules/%s/%s/'):format(area, providerName)
    local staged = {}
    local loadedAny = false
    for _, fileName in ipairs({ 'shared.lua', realm .. '.lua' }) do
        local path = pathRoot .. fileName
        local ok, source = pcall(LoadResourceFile, 'kora_lib', path)
        if not ok then
            reportLoadError(area, providerName, source)
            return false
        end
        if source then
            local chunk, compileError = load(source, ('@@kora_lib/%s'):format(path), 't', _ENV)
            if not chunk then
                reportLoadError(area, providerName, compileError)
                return false
            end
            local bridge = Kora.bridge
            Kora.bridge = setmetatable(staged, { __index = bridge })
            local ran, runError = pcall(chunk)
            Kora.bridge = bridge
            if not ran then
                reportLoadError(area, providerName, runError)
                return false
            end
            loadedAny = true
        end
    end

    if not loadedAny then
        reportLoadError(area, providerName, 'Provider files were not found.')
        return false
    end
    for _, method in ipairs(required) do
        if type(rawget(staged, method)) ~= 'function' then
            reportLoadError(area, providerName, ('Missing function Kora.bridge.%s.'):format(method))
            return false
        end
    end

    for _, method in ipairs(loadedMethods[area] or {}) do Kora.bridge[method] = nil end
    loadedMethods[area] = {}
    for method, callback in pairs(staged) do
        if type(callback) == 'function' then
            Kora.bridge[method] = callback
            loadedMethods[area][#loadedMethods[area] + 1] = method
        end
    end
    selectedProviders[area] = providerName
    return true
end

local function refreshArea(area)
    local providerName = chooseProvider(area)
    if providerName == selectedProviders[area] then return end
    for _, method in ipairs(loadedMethods[area] or {}) do Kora.bridge[method] = nil end
    loadedMethods[area] = nil
    selectedProviders[area] = nil
    if providerName then loadProvider(area, providerName) end
end

---Returns the provider folder selected for an area, or nil when unavailable.
---@param area KoraBridgeArea
---@return string|nil providerName
function Kora.bridge.getProvider(area)
    assert(type(area) == 'string' and providerCatalog[area], ('Unknown bridge area %q.'):format(tostring(area)))
    return selectedProviders[area]
end
exports("bridge_getProvider", Kora.bridge.getProvider)

local function resourceChanged(resource)
    resourceStates[resource] = nil
    for area in pairs(resourceAreas[resource] or {}) do refreshArea(area) end
end

if type(AddEventHandler) == 'function' then
    AddEventHandler('onResourceStart', resourceChanged)
    AddEventHandler('onResourceStop', resourceChanged)
    AddEventHandler('onClientResourceStart', resourceChanged)
    AddEventHandler('onClientResourceStop', resourceChanged)
end

for area in pairs(providerCatalog) do refreshArea(area) end
