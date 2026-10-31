---@class QBDrawingText3DOptions
---@field font? integer
---@field scale? number
---@field color? {r: integer, g: integer, b: integer, a: integer}
---@field maxDistance? number Meters from PlayerPedId(); beyond this, every native call is skipped.
---@field outline? boolean

-- Plain { x, y, z } table, not glm.vec3 -- see the identical note in
-- modules/raycast/client.lua, modules/world/client.lua, and modules/zones/client.lua.
local function toVec3(v)
    assert(v and Kora.util.isFiniteNumber(v.x) and Kora.util.isFiniteNumber(v.y) and Kora.util.isFiniteNumber(v.z),
        "Coordinates must be a vector3, glm.vec3, or {x=,y=,z=} table.")
    return { x = v.x, y = v.y, z = v.z }
end

local function withinDistance(a, b, maximum)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return dx * dx + dy * dy + dz * dz <= maximum * maximum
end

---Draws one frame of world-space 3D text via the standard SetDrawOrigin
---idiom -- not a persistent registration, same contract as a raw DrawMarker
---call: call it again every frame it should stay visible.
---@param coords any World position to anchor the text to.
---@param text string Multi-line via GTA's own "~n~" token, not "\n".
---@param options? QBDrawingText3DOptions Any field omitted falls back to Config.drawing.text3d.
function Kora.drawing.text3d(coords, text, options)
    assert(type(text) == "string" and #text > 0, "text must be a non-empty string.")

    if options == nil then options = {} end
    assert(type(options) == 'table', 'text3d options must be a table.')

    local defaults = Config.drawing.text3d
    local point = toVec3(coords)
    local maxDistance = options.maxDistance
    if maxDistance == nil then maxDistance = defaults.maxDistance end
    assert(Kora.util.isFiniteNumber(maxDistance) and maxDistance >= 0,
        'text3d maxDistance must be a finite non-negative number.')
    local font = options.font
    if font == nil then font = defaults.font end
    local scale = options.scale
    if scale == nil then scale = defaults.scale end
    local color = options.color
    if color == nil then color = defaults.color end
    local outline = options.outline
    if outline == nil then outline = defaults.outline end

    assert(Kora.util.isInteger(font) and font >= 0, 'text3d font must be a non-negative integer.')
    assert(Kora.util.isFiniteNumber(scale) and scale > 0, 'text3d scale must be a positive finite number.')
    assert(type(color) == 'table' and Kora.util.isInteger(color.r) and color.r >= 0 and color.r <= 255
        and Kora.util.isInteger(color.g) and color.g >= 0 and color.g <= 255
        and Kora.util.isInteger(color.b) and color.b >= 0 and color.b <= 255
        and Kora.util.isInteger(color.a) and color.a >= 0 and color.a <= 255,
        'text3d color must have integer r, g, b, and a components from 0 to 255.')
    assert(type(outline) == 'boolean', 'text3d outline must be a boolean.')

    -- Distance-culled before any native call, not after -- the whole reason
    -- this belongs in the primitive rather than being re-derived by every
    -- caller is so a caller drawing dozens of prompts a frame doesn't pay for
    -- the ones nowhere near the player.
    if not withinDistance(toVec3(GetEntityCoords(PlayerPedId())), point, maxDistance) then
        return
    end

    SetTextScale(scale, scale)
    SetTextFont(font)
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
