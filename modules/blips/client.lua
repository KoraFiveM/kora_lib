---@class QBBlipsCreateOptions
---@field sprite? number Blip sprite id. Defaults to `Config.blips.defaultSprite`.
---@field color? number Blip color index. Defaults to `Config.blips.defaultColor`.
---@field scale? number Blip scale. Defaults to `Config.blips.defaultScale`.
---@field label? string Blip name shown on the map/legend. Left as the sprite's own default label when omitted.
---@field shortRange? boolean Whether the blip only shows near the player. Defaults to `Config.blips.defaultShortRange`.
---@field category? number Blip category, for legend grouping. Left unset (engine default) when omitted.
---@field route? boolean Draws a waypoint route line to the blip. Defaults to `false`.

-- blipRegistry tracks every blip this module has created, keyed by the
-- resource that invoked `create` -- see local/resources/AGENTS.md. Cleanup on
-- resource stop guards with DoesBlipExist since RemoveBlip on an
-- already-gone handle is undefined behavior, not a no-op.
local blipRegistry = QB.resources.registry(function(blip)
    if DoesBlipExist(blip) then RemoveBlip(blip) end
end)

---Applies `label` as the blip's display name via the text-command trio FiveM
---requires for setting blip names (there's no single-call native for it).
---@param blip number
---@param label string
local function applyLabel(blip, label)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandSetBlipName(blip)
end

---Creates a map blip at `coords`, visible only to the calling client, and
---tracks it against whichever resource invoked `create` (via
---`GetInvokingResource`, falling back to the current resource when called
---directly rather than through an export) so it is automatically removed if
---that resource stops.
---@param coords vector3 | vector4 | {x: number, y: number, z: number} World coordinates to place the blip at.
---@param options? QBBlipsCreateOptions
---@return number | false blip The created blip handle, or false if it failed to create.
---@return string? error
function QB.blips.create(coords, options)
    -- Must be captured before any native calls below -- the invoking-resource
    -- context is only valid at this call boundary, same reasoning as
    -- modules/entities.
    local invokingResource = GetInvokingResource() or GetCurrentResourceName()

    options = options or {}

    assert(coords and type(coords.x) == "number" and type(coords.y) == "number" and type(coords.z) == "number",
        "Invalid coords: expected a vector3/vector4 or {x, y, z} table.")

    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)

    if not blip or blip == 0 then
        return false, "Failed to create blip."
    end

    SetBlipSprite(blip, options.sprite or Config.blips.defaultSprite)
    SetBlipColour(blip, options.color or Config.blips.defaultColor)
    SetBlipScale(blip, options.scale or Config.blips.defaultScale)

    local shortRange = options.shortRange
    if shortRange == nil then shortRange = Config.blips.defaultShortRange end
    SetBlipAsShortRange(blip, shortRange)

    if options.category then SetBlipCategory(blip, options.category) end
    if options.label then applyLabel(blip, options.label) end

    if options.route then
        SetBlipRoute(blip, true)
        if options.color then SetBlipRouteColour(blip, options.color) end
    end

    blipRegistry.track(invokingResource, blip)

    return blip
end

---Removes one tracked blip created with QB.blips.create and drops it from
---tracking, without waiting for its owning resource to stop. Refuses blips
---this module didn't create -- exports.qblib:blips_remove is callable from
---any resource, and an untracked-handle gate is what stops it doubling as a
---remove-anything primitive against blips owned by other resources.
---@param blip number The blip handle to remove.
---@return boolean success
---@return string? error
function QB.blips.remove(blip)
    assert(type(blip) == "number", ("Invalid blip: %s"):format(blip))

    local owner = blipRegistry.untrack(blip)

    if not owner then
        return false, "Blip is not tracked by QB.blips."
    end

    if not DoesBlipExist(blip) then
        return false, "Blip does not exist."
    end

    RemoveBlip(blip)

    return true
end
