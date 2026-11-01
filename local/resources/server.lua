---@class QBResourcesRegistry
---@field track fun(resource: string, id: any) Marks `id` as owned by `resource`.
---@field untrack fun(id: any): string? resource The resource `id` was tracked under, if any; drops the tracking either way.
---@field owner fun(id: any): string? resource The resource currently tracking `id`, without dropping it.

-- Server-side twin of registry() in client.lua, swept on 'onResourceStop'. Duplicated because client.lua and
-- server.lua are separate Lua chunks.

local function assertId(id)
    assert(id ~= nil, 'Registry id must not be nil.')
end

local function assertResourceName(resource)
    assert(type(resource) == 'string' and resource ~= '' and #resource <= 256,
        'Registry resource must be a non-empty string up to 256 bytes.')
end

---Creates an isolated ownership registry: a `resource -> {id set}` forward
---index for bulk cleanup plus an `id -> resource` reverse lookup for O(1)
---manual untracking. `onDispose(id)` runs once for every id still tracked
---under a resource when that resource stops.
---@param onDispose fun(id: any) Called for each id still owned when its resource stops.
---@return QBResourcesRegistry
function Kora.resources.serverRegistry(onDispose)
    assert(Kora.compat.isCallable(onDispose), 'Kora.resources.serverRegistry requires a callable disposer.')
    local byResource = {}
    local ownerOf = {}
    local sweeping = {}
    local function track(resource, id)
        assertResourceName(resource)
        assertId(id)
        assert(not sweeping[resource], 'Cannot track an id for a resource while it is stopping.')
        local previousOwner = ownerOf[id]

        if previousOwner and previousOwner ~= resource then
            local previouslyOwned = byResource[previousOwner]
            if previouslyOwned then previouslyOwned[id] = nil end
        end

        local owned = byResource[resource]

        if not owned then
            owned = {}
            byResource[resource] = owned
        end

        owned[id] = true
        ownerOf[id] = resource
    end

    local function untrack(id)
        assertId(id)
        local resource = ownerOf[id]

        if resource then
            local owned = byResource[resource]
            if owned then owned[id] = nil end
            ownerOf[id] = nil
        end

        return resource
    end

    local function owner(id)
        assertId(id)
        return ownerOf[id]
    end

    AddEventHandler("onResourceStop", function(resource)
        local owned = byResource[resource]
        if not owned then return end

        byResource[resource] = nil
        sweeping[resource] = true

        for id in pairs(owned) do
            ownerOf[id] = nil
            local ok, err = pcall(onDispose, id)
            if not ok then
                print(("^3[kora_lib:resources]^7 cleanup for %s id %s failed: %s")
                    :format(resource, tostring(id), tostring(err)))
            end
        end
        sweeping[resource] = nil
    end)

    return { track = track, untrack = untrack, owner = owner }
end
