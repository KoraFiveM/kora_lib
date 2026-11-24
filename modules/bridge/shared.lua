local isServer = IsDuplicityVersion()
local providers = {}
local resourceAreas = {}
local resourceStates = {}
local resolutions = {}
local unavailableLogged = {}

local contracts = {
    banking = {
        server = { 'addMoney', 'removeMoney', 'getAccountBalance', 'executeTransaction', 'createBankStatement' },
    },
    bossmenu = {
        client = {
            'openBossMenu', 'openApplication', 'addBossMenuItem', 'removeBossMenuItem', 'addGangMenuItem',
            'removeGangMenuItem',
        },
        server = {
            'addBusinessMoney', 'removeBusinessMoney', 'getBusinessBalance', 'addMoney', 'removeMoney',
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
        client = { 'show', 'update', 'hide' },
    },
    notify = {
        client = { 'send' },
    },
    vehiclekeys = {
        server = { 'giveKeys', 'removeKeys', 'hasKeys' },
    },
}

local realm = isServer and 'server' or 'client'

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

local function resolveProvider(area)
    local configured = getConfiguredProvider(area)
    if not configured then return nil end

    local cached = resolutions[area]
    if cached and cached.configured == configured then return cached.provider end

    local registered = providers[area] or {}
    local selected
    if configured == 'auto' then
        local names = {}
        for providerName in pairs(registered) do names[#names + 1] = providerName end
        table.sort(names, function(left, right)
            local leftKora = left:match('^kora_') ~= nil
            local rightKora = right:match('^kora_') ~= nil
            if leftKora ~= rightKora then return leftKora end
            return left < right
        end)

        for _, providerName in ipairs(names) do
            if isStarted(providerName) then
                selected = providerName
                break
            end
        end
    elseif registered[configured] and isStarted(configured) then
        selected = configured
    end

    resolutions[area] = { configured = configured, provider = selected }
    return selected
end

---Registers a provider adapter after checking its functions against the realm contract.
---@param area KoraBridgeArea
---@param providerName string Resource name and provider key.
---@param adapter table<string, function>
---@return boolean registered
function Kora.bridge.register(area, providerName, adapter)
    assert(type(area) == 'string' and contracts[area], ('Unknown bridge area %q.'):format(tostring(area)))
    assert(type(providerName) == 'string' and providerName ~= '' and not providerName:find('[@%c/\\]'),
        'Bridge provider name must be a resource name.')
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
    resourceAreas[providerName] = resourceAreas[providerName] or {}
    resourceAreas[providerName][area] = true
    resourceStates[providerName] = nil
    clearResolution(area)
    return true
end

---Returns the selected, started provider name for an area, or nil when unavailable.
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

-- Internal dispatch lives under compat because build/finalise.lua intentionally
-- excludes that table from consumer exports.
Kora.compat.bridgeCall = function(area, method, fallback, ...)
    local providerName = resolveProvider(area)
    local adapter = providerName and providers[area] and providers[area][providerName]
    local target = adapter and adapter[method]
    if type(target) ~= 'function' then
        logUnavailable(area, providerName or getConfiguredProvider(area), method)
        return table.unpack(fallback, 1, fallback.n)
    end

    local result = table.pack(pcall(target, ...))
    if not result[1] then
        logCallFailure(area, providerName, method)
        return table.unpack(fallback, 1, fallback.n)
    end
    return table.unpack(result, 2, result.n)
end