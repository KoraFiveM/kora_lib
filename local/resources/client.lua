---@class QBResourcesRegistry
---@field track fun(resource: string, id: any) Marks `id` as owned by `resource`.
---@field untrack fun(id: any): string? resource The resource `id` was tracked under, if any; drops the tracking either way.
---@field owner fun(id: any): string? resource The resource currently tracking `id`, without dropping it.

-- One `AddEventHandler("onClientResourceStop", ...)` per registry (not one
-- shared handler for every registry) -- each registry owns its own id space
-- and its own onDispose behavior, so there is nothing to gain by merging the
-- sweeps, and keeping them separate means a registry is fully self-contained.

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
    local byResource = {}
    local ownerOf = {}

    local function track(resource, id)
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
        local resource = ownerOf[id]

        if resource then
            local owned = byResource[resource]
            if owned then owned[id] = nil end
            ownerOf[id] = nil
        end

        return resource
    end

    local function owner(id)
        return ownerOf[id]
    end

    AddEventHandler("onClientResourceStop", function(resource)
        local owned = byResource[resource]
        if not owned then return end

        byResource[resource] = nil

        for id in pairs(owned) do
            ownerOf[id] = nil
            onDispose(id)
        end
    end)

    return { track = track, untrack = untrack, owner = owner }
end
