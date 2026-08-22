---@class QBDrawingText3DOptions
---@field font? integer
---@field scale? number
---@field color? {r: integer, g: integer, b: integer, a: integer}
---@field maxDistance? number Meters from PlayerPedId(); beyond this, every native call is skipped.
---@field outline? boolean

-- Plain { x, y, z } table, not glm.vec3 -- see the identical note in
-- modules/raycast/client.lua, modules/world/client.lua, and modules/zones/client.lua.
local function toVec3(v)
    assert(type(v.x) == "number" and type(v.y) == "number" and type(v.z) == "number",
        "Coordinates must be a vector3, glm.vec3, or {x=,y=,z=} table.")
    return { x = v.x, y = v.y, z = v.z }
end

local function distance(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

---Draws one frame of world-space 3D text via the standard SetDrawOrigin
---idiom -- not a persistent registration, same contract as a raw DrawMarker
---call: call it again every frame it should stay visible.
---@param coords any World position to anchor the text to.
---@param text string Multi-line via GTA's own "~n~" token, not "\n".
---@param options? QBDrawingText3DOptions Any field omitted falls back to Config.drawing.text3d.
function QB.drawing.text3d(coords, text, options)
    assert(type(text) == "string" and #text > 0, "text must be a non-empty string.")

    options = options or {}

    local defaults = Config.drawing.text3d
    local point = toVec3(coords)
    local maxDistance = options.maxDistance or defaults.maxDistance

    -- Distance-culled before any native call, not after -- the whole reason
    -- this belongs in the primitive rather than being re-derived by every
    -- caller is so a caller drawing dozens of prompts a frame doesn't pay for
    -- the ones nowhere near the player.
    if distance(toVec3(GetEntityCoords(PlayerPedId())), point) > maxDistance then
        return
    end

    local color = options.color or defaults.color
    local outline = options.outline
    if outline == nil then outline = defaults.outline end

    SetTextScale(options.scale or defaults.scale, options.scale or defaults.scale)
    SetTextFont(options.font or defaults.font)
    SetTextProportional(true)
    SetTextColour(color.r, color.g, color.b, color.a)
    SetTextCentre(true)
    if outline then SetTextOutline() end

    SetTextEntry("STRING")
    AddTextComponentString(text)

    SetDrawOrigin(point.x, point.y, point.z, 0)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end
