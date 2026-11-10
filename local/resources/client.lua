local function assertId(id)
    assert(id ~= nil, 'Registry id must not be nil.')
end

local function assertResourceName(resource)
    assert(type(resource) == 'string' and resource ~= '' and #resource <= 256,
        'Registry resource must be a non-empty string up to 256 bytes.')
end

---Creates an isolated ownership registry: a `resource -> {id set}` index for bulk cleanup plus an `id -> resource` reverse lookup.
---`onDispose(id)` runs for every id still tracked under a resource when it stops.
---Scope one registry to one id space; sharing across colliding id spaces corrupts the reverse lookup.
---@param onDispose fun(id: any) Called for each id still owned when its resource stops.
---@return KoraResourcesRegistry
function Kora.resources.registry(onDispose)
    assert(Kora.compat.isCallable(onDispose), 'Kora.resources.registry requires a callable disposer.')
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

    AddEventHandler("onClientResourceStop", function(resource)
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
