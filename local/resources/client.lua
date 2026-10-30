---@class QBResourcesRegistry
---@field track fun(resource: string, id: any) Marks `id` as owned by `resource`.
---@field untrack fun(id: any): string? resource The resource `id` was tracked under, if any; drops the tracking either way.
---@field owner fun(id: any): string? resource The resource currently tracking `id`, without dropping it.

-- One `AddEventHandler("onClientResourceStop", ...)` per registry (not one
-- shared handler for every registry) -- each registry owns its own id space
-- and its own onDispose behavior, so there is nothing to gain by merging the
-- sweeps, and keeping them separate means a registry is fully self-contained.

local function assertId(id)
    assert(id ~= nil, 'Registry id must not be nil.')
end

local function assertResourceName(resource)
    assert(type(resource) == 'string' and resource ~= '' and #resource <= 256,
        'Registry resource must be a non-empty string up to 256 bytes.')
end

---Creates an isolated ownership registry: a `resource -> {id set}` forward
---index for bulk cleanup plus an `id -> resource` reverse lookup for O(1)
---manual untracking, matching the shape every client-side owned-state module
---(entities, zones, cache, ...) already hand-rolls for itself. `onDispose(id)`
---runs once for every id still tracked under a resource when that resource
---stops, so callers only have to say how to release one id -- not how to
---track or sweep.
---
---A single registry is scoped to one id space (e.g. one module's handles).
---Sharing one registry across id spaces that can collide (e.g. entity handles
---and blip handles) would corrupt the reverse lookup, so each consuming
---module should create its own registry once at load time.
---@param onDispose fun(id: any) Called for each id still owned when its resource stops.
---@return QBResourcesRegistry
function QB.resources.registry(onDispose)
    assert(QB.compat.isCallable(onDispose), 'QB.resources.registry requires a callable disposer.')
    local byResource = {}
    local ownerOf = {}
    local sweeping = {}
    local function track(resource, id)
        assertResourceName(resource)
        assertId(id)
        assert(not sweeping[resource], 'Cannot track an id for a resource while it is stopping.')
        local previousOwner = ownerOf[id]

        -- Re-tracking an id already owned by a DIFFERENT resource (e.g. a
        -- name-keyed registry where a second resource overwrites the first's
        -- registration) must move it, not just add it to the new owner's set
        -- -- otherwise the old owner's set keeps a stale entry, and that old
        -- owner stopping would incorrectly dispose an id it no longer owns.
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
