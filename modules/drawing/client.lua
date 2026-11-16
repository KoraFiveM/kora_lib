local function toVec3(v)
    assert(v and Kora.util.isFiniteNumber(v.x) and Kora.util.isFiniteNumber(v.y) and Kora.util.isFiniteNumber(v.z),
        KoraLang('Modules.Drawing.coords_invalid'))
    return { x = v.x, y = v.y, z = v.z }
end

local function withinDistance(a, b, maximum)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return dx * dx + dy * dy + dz * dz <= maximum * maximum
end

---Draws one frame of world-space 3D text (SetDrawOrigin); call it every frame it should stay visible.
---@param coords any World position to anchor the text to.
---@param text string Multi-line via GTA's own "~n~" token, not "\n".
---@param options? KoraDrawingText3DOptions Any field omitted falls back to Config.drawing.text3d.
function Kora.drawing.text3d(coords, text, options)
    assert(type(text) == "string" and #text > 0, KoraLang('Modules.Drawing.text_invalid'))

    if options == nil then options = {} end
    assert(type(options) == 'table', KoraLang('Modules.Drawing.options_invalid'))

    local defaults = Config.drawing.text3d
    local point = toVec3(coords)
    local maxDistance = options.maxDistance
    if maxDistance == nil then maxDistance = defaults.maxDistance end
    assert(Kora.util.isFiniteNumber(maxDistance) and maxDistance >= 0,
        KoraLang('Modules.Drawing.max_distance_invalid'))
    local font = options.font
    if font == nil then font = defaults.font end
    local scale = options.scale
    if scale == nil then scale = defaults.scale end
    local color = options.color
    if color == nil then color = defaults.color end
    local outline = options.outline
    if outline == nil then outline = defaults.outline end

    assert(Kora.util.isInteger(font) and font >= 0, KoraLang('Modules.Drawing.font_invalid'))
    assert(Kora.util.isFiniteNumber(scale) and scale > 0, KoraLang('Modules.Drawing.scale_invalid'))
    assert(type(color) == 'table' and Kora.util.isInteger(color.r) and color.r >= 0 and color.r <= 255
        and Kora.util.isInteger(color.g) and color.g >= 0 and color.g <= 255
        and Kora.util.isInteger(color.b) and color.b >= 0 and color.b <= 255
        and Kora.util.isInteger(color.a) and color.a >= 0 and color.a <= 255,
        KoraLang('Modules.Drawing.color_invalid'))
    assert(type(outline) == 'boolean', KoraLang('Modules.Drawing.outline_invalid'))

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
