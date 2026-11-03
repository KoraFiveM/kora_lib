-- Kora.sites -- config sites (a fuel station, shop, garage, armoury) that own interaction
-- points (pumps, counters, spots, lockers). build() flattens them once into plain lookup
-- tables, so a purchase does one table lookup and one distance check instead of scanning
-- every site. Plain tables only: no metatables, no per-object closures.
--
-- Loaded into each consumer by init.lua (like Kora.util): the index stays in the caller's
-- Lua state, so validate() never re-serialises it across the exports boundary.

---@class QBSitesBuildOptions
---@field childKey? string Field on each site holding its children. Defaults to 'children'.
---@field inherit? string[] Child fields resolved child -> site -> globals.
---@field globals? table Fallback values for `inherit` fields.

---@class QBSitesIndex
---@field sites table<string, table> Site definitions by id.
---@field children table<string, table> Resolved children by 'siteId:childId'.
---@field list table[] Resolved children in definition order.

local function isId(value)
    return (type(value) == 'string' and value ~= '' and #value <= 64 and not value:find(':', 1, true))
        or Kora.util.isInteger(value)
end

-- 5 and 5.0 must name the same site or child.
local function idString(value)
    return type(value) == 'number' and tostring(math.tointeger(value)) or value
end

local function hasCoords(value)
    return value ~= nil and Kora.util.isFiniteNumber(value.x) and Kora.util.isFiniteNumber(value.y)
        and Kora.util.isFiniteNumber(value.z)
end

-- A site- or global-level value is either a plain value for every child, or a table keyed by
-- child `type` (`price = { pump = 1.55, charger = 0.45 }`).
local function levelValue(value, childType)
    if type(value) ~= 'table' then return value end
    if childType ~= nil then return value[childType] end
    return nil
end

---Flattens site definitions into an index. Each child gets `siteId`, `key` ('siteId:childId')
---and every `inherit` field resolved once (child, then site, then `globals`). Input tables are
---not modified.
---@param defs table[] Array of sites; each needs an `id` and an array of children under `childKey`.
---@param opts? QBSitesBuildOptions
---@return QBSitesIndex index
function Kora.sites.build(defs, opts)
    assert(type(defs) == 'table', 'Kora.sites.build requires an array of site definitions.')
    assert(opts == nil or type(opts) == 'table', 'Kora.sites.build options must be a table.')
    opts = opts or {}
    local childKey = opts.childKey or 'children'
    local inherit = opts.inherit or {}
    local globals = opts.globals or {}
    assert(type(childKey) == 'string' and childKey ~= '', 'Kora.sites.build childKey must be a string.')
    assert(type(inherit) == 'table' and type(globals) == 'table', 'Kora.sites.build inherit/globals must be tables.')

    local index = { sites = {}, children = {}, list = {} }
    for siteIndex = 1, #defs do
        local site = defs[siteIndex]
        assert(type(site) == 'table' and isId(site.id),
            ('Kora.sites.build site %d needs an id (string without ":" or integer).'):format(siteIndex))
        local siteId = idString(site.id)
        assert(index.sites[siteId] == nil, ('Kora.sites.build duplicate site id %s.'):format(siteId))
        index.sites[siteId] = site

        local children = site[childKey]
        assert(type(children) == 'table', ('Kora.sites.build site %s has no %s array.'):format(siteId, childKey))
        for childIndex = 1, #children do
            local def = children[childIndex]
            assert(type(def) == 'table' and isId(def.id),
                ('Kora.sites.build site %s child %d needs an id.'):format(siteId, childIndex))
            assert(hasCoords(def.coords), ('Kora.sites.build %s:%s needs finite coords.'):format(siteId, tostring(def.id)))
            assert(def.radius == nil or (Kora.util.isFiniteNumber(def.radius) and def.radius > 0),
                ('Kora.sites.build %s:%s radius must be a positive number.'):format(siteId, tostring(def.id)))

            local child = {}
            for field, value in pairs(def) do child[field] = value end
            child.id = idString(def.id)
            child.siteId = siteId
            child.key = siteId .. ':' .. child.id
            child.disabled = def.disabled == true or site.disabled == true
            for fieldIndex = 1, #inherit do
                local field = inherit[fieldIndex]
                local value = def[field]
                if value == nil then value = levelValue(site[field], def.type) end
                if value == nil then value = levelValue(globals[field], def.type) end
                child[field] = value
            end

            assert(index.children[child.key] == nil, ('Kora.sites.build duplicate child %s.'):format(child.key))
            index.children[child.key] = child
            index.list[#index.list + 1] = child
        end
    end

    return index
end

---Looks up a site (`childId` omitted) or one of its resolved children. Unknown or malformed
---ids return nil, so client-supplied ids can be passed straight in.
---@param index QBSitesIndex
---@param siteId string|integer
---@param childId? string|integer
---@return table|nil
function Kora.sites.get(index, siteId, childId)
    assert(type(index) == 'table' and type(index.sites) == 'table', 'Kora.sites.get requires a Kora.sites index.')
    if not isId(siteId) then return nil end
    if childId == nil then return index.sites[idString(siteId)] end
    if not isId(childId) then return nil end
    return index.children[idString(siteId) .. ':' .. idString(childId)]
end
