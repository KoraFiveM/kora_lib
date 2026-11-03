---@alias QBSitesZoneOptions QBInteractTargetOptions|QBInteractOption[]|fun(child: table): (QBInteractTargetOptions|QBInteractOption[]|nil)

---Adds one Kora.interact circle zone per child whose `type` has an entry in `optionsByType`.
---An entry is either target options shared by every child of that type, or a function
---`fn(child)` returning per-child options (or nil to skip that child). The zone radius is
---the child's `radius`, else `opts.radius`, else 2.0 metres.
---@param index QBSitesIndex
---@param optionsByType table<string, QBSitesZoneOptions>
---@param opts? {radius?: number, debug?: boolean}
---@return {remove: fun(): integer} handle `remove()` deletes every zone it created and returns how many.
function Kora.sites.registerZones(index, optionsByType, opts)
    assert(type(index) == 'table' and type(index.list) == 'table', 'Kora.sites.registerZones requires a Kora.sites index.')
    assert(type(optionsByType) == 'table', 'Kora.sites.registerZones requires options by child type.')
    assert(opts == nil or type(opts) == 'table', 'Kora.sites.registerZones options must be a table.')
    opts = opts or {}
    assert(opts.radius == nil or (Kora.util.isFiniteNumber(opts.radius) and opts.radius > 0),
        'Kora.sites.registerZones radius must be a positive number.')

    -- Zone names are global in Kora.interact; prefix with this resource so two resources
    -- using the same site ids cannot collide.
    local prefix = ('%s:sites:'):format(GetCurrentResourceName())
    local names = {}

    for childIndex = 1, #index.list do
        local child = index.list[childIndex]
        local entry = child.type ~= nil and optionsByType[child.type] or nil
        local targetOptions = entry
        if type(entry) == 'function' then targetOptions = entry(child) end

        if targetOptions ~= nil and not child.disabled then
            local name = prefix .. child.key
            local zone = Kora.interact.addCircleZone(name, child.coords, child.radius or opts.radius or 2.0,
                targetOptions, opts.debug == true)
            if zone then names[#names + 1] = name end
        end
    end

    local handle = {}

    function handle.remove()
        local removed = 0
        for nameIndex = 1, #names do
            if Kora.interact.removeZone(names[nameIndex]) then removed = removed + 1 end
        end
        names = {}
        return removed
    end

    return handle
end
