---@class QBSitesValidateOptions
---@field maxDistance? number Player-to-child limit in metres. A child's own `radius` widens it.
---@field types? string[] Accepted child `type` values.
---@field vehicleNetId? integer Also resolve this vehicle (Kora.world.resolveNetworkEntity) near the child.
---@field vehicleDistance? number Vehicle-to-child limit in metres. Defaults to the player limit.

local function distanceSq(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return dx * dx + dy * dy + dz * dz
end

local function acceptsType(types, childType)
    for index = 1, #types do
        if types[index] == childType then return true end
    end
    return false
end

---Resolves a client-supplied site/child pair and checks it server-side: it exists, is not
---disabled, has an accepted type, and the player (and optionally a vehicle) is near that one
---child. One table lookup and one distance check, whatever the number of sites.
---@param src integer
---@param index QBSitesIndex
---@param siteId any Client data.
---@param childId any Client data.
---@param opts QBSitesValidateOptions
---@return table|nil child
---@return string|integer|nil reasonOrVehicle Failure reason, or the vehicle entity when `vehicleNetId` was given.
function Kora.sites.validate(src, index, siteId, childId, opts)
    assert(Kora.util.isInteger(src) and src > 0, 'Kora.sites.validate requires a player source.')
    assert(type(opts) == 'table', 'Kora.sites.validate requires an options table.')
    assert(opts.maxDistance == nil or (Kora.util.isFiniteNumber(opts.maxDistance) and opts.maxDistance >= 0),
        'Kora.sites.validate maxDistance must be a non-negative number.')
    assert(opts.types == nil or type(opts.types) == 'table', 'Kora.sites.validate types must be an array.')
    assert(opts.vehicleDistance == nil or (Kora.util.isFiniteNumber(opts.vehicleDistance) and opts.vehicleDistance >= 0),
        'Kora.sites.validate vehicleDistance must be a non-negative number.')

    if Kora.sites.get(index, siteId) == nil then return nil, 'unknown_site' end
    local child = Kora.sites.get(index, siteId, childId)
    if not child then return nil, 'unknown_child' end
    if child.disabled then return nil, 'disabled' end
    if opts.types and not acceptsType(opts.types, child.type) then return nil, 'wrong_type' end

    local limit = math.max(opts.maxDistance or 0, child.radius or 0)
    assert(limit > 0, ('Kora.sites.validate needs maxDistance or a radius on %s.'):format(child.key))

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil, 'player_unavailable' end
    if distanceSq(GetEntityCoords(ped), child.coords) > limit * limit then return nil, 'too_far' end

    if opts.vehicleNetId ~= nil then
        local vehicleLimit = opts.vehicleDistance or limit
        local vehicle, reason = Kora.world.resolveNetworkEntity(src, opts.vehicleNetId, {
            entityType = 'vehicle',
            near = { coords = { x = child.coords.x, y = child.coords.y, z = child.coords.z }, radius = vehicleLimit },
        })
        if not vehicle then return nil, reason end
        return child, vehicle
    end

    return child
end
