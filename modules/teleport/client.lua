---@class QBTeleportOptions
---@field fade? boolean|number Fade around the move. `false` disables it; `true` and omitted use 500ms.

local function assertCoords(coords)
    assert(type(coords) == 'table' or type(coords) == 'vector3' or type(coords) == 'vector4',
        'Teleport coordinates must be vector-like.')
    assert(type(coords.x) == 'number' and type(coords.y) == 'number' and type(coords.z) == 'number',
        'Teleport coordinates require numeric x, y, and z.')
end

---Moves an existing local entity to coordinates, optionally fading around the move.
---@param entity number
---@param coords vector3|vector4|{x:number,y:number,z:number,w?:number,heading?:number}
---@param opts? QBTeleportOptions
---@return boolean success
function QB.teleport.entity(entity, coords, opts)
    assert(type(entity) == 'number' and entity ~= 0 and DoesEntityExist(entity), ('Invalid entity: %s'):format(entity))
    assertCoords(coords)
    opts = opts or {}

    local function move()
        SetEntityCoords(entity, coords.x, coords.y, coords.z)
        local heading = type(coords.w) == 'number' and coords.w or coords.heading
        if type(heading) == 'number' then SetEntityHeading(entity, heading) end
    end

    local fade = opts.fade
    if fade ~= false then
        QB.visuals.fade(type(fade) == 'number' and fade or 500, move)
    else
        move()
    end
    return true
end

---Moves the local player ped. Equivalent to `QB.teleport.entity(QB.cache.ped(), ...)`.
---@param coords vector3|vector4|{x:number,y:number,z:number,w?:number,heading?:number}
---@param opts? QBTeleportOptions
---@return boolean success
function QB.teleport.player(coords, opts)
    return QB.teleport.entity(QB.cache.ped(), coords, opts)
end
