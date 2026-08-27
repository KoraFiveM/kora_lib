---@class QBVehicleDeleteOptions
---@field timeout? integer Maximum time to acquire network control. Defaults to 1000ms.

---Requests control of a networked entity before mutating it.
---@param entity number
---@param timeout? integer
---@return boolean controlled
---@return string? error
function QB.vehicle.requestControl(entity, timeout)
    assert(type(entity) == 'number' and entity ~= 0, 'QB.vehicle.requestControl requires an entity.')
    if not DoesEntityExist(entity) then return false, 'Entity does not exist.' end
    if NetworkHasControlOfEntity(entity) then return true end

    local controlled, err = QB.loops.controlled(function()
        NetworkRequestControlOfEntity(entity)
        return NetworkHasControlOfEntity(entity)
    end, false, timeout or 1000, true)

    return controlled ~= false, err
end

---Safely deletes a vehicle after obtaining control. Call this only after the
---owning resource's server-side authorization has succeeded.
---@param vehicle number
---@param options? QBVehicleDeleteOptions
---@return boolean deleted
---@return string? error
function QB.vehicle.delete(vehicle, options)
    assert(type(vehicle) == 'number' and vehicle ~= 0, 'QB.vehicle.delete requires a vehicle.')
    options = options or {}
    if not DoesEntityExist(vehicle) then return false, 'Vehicle does not exist.' end
    if not IsEntityAVehicle(vehicle) then return false, 'Entity is not a vehicle.' end

    local controlled, err = QB.vehicle.requestControl(vehicle, options.timeout)
    if not controlled then return false, err or 'Could not acquire vehicle control.' end

    SetEntityAsMissionEntity(vehicle, true, true)
    DeleteVehicle(vehicle)
    return not DoesEntityExist(vehicle), DoesEntityExist(vehicle) and 'Vehicle deletion failed.' or nil
end

---@param vehicle number
---@return boolean
function QB.vehicle.isDriver(vehicle)
    return type(vehicle) == 'number' and vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == PlayerPedId()
end

---@param vehicle number
---@return number|false modelHash
function QB.vehicle.model(vehicle)
    if type(vehicle) ~= 'number' or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    return GetEntityModel(vehicle)
end
