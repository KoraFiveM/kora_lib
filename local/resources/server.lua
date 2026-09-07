---@class QBResourcesRegistry
---@field track fun(resource: string, id: any) Marks `id` as owned by `resource`.
---@field untrack fun(id: any): string? resource The resource `id` was tracked under, if any; drops the tracking either way.
---@field owner fun(id: any): string? resource The resource currently tracking `id`, without dropping it.

-- Server-side twin of registry() in client.lua -- same shape, but swept on
-- 'onResourceStop' instead of 'onClientResourceStop'. Duplicated rather than
-- shared: client.lua and server.lua are separate Lua chunks (same reasoning
-- local/callback and local/events already document for their own small
-- duplicated helpers), so there's no way for one file-local implementation
-- to serve both realms.

---Creates an isolated ownership registry: a `resource -> {id set}` forward
---index for bulk cleanup plus an `id -> resource` reverse lookup for O(1)
---manual untracking. `onDispose(id)` runs once for every id still tracked
---under a resource when that resource stops.
---@param onDispose fun(id: any) Called for each id still owned when its resource stops.
---@return QBResourcesRegistry
function QB.resources.serverRegistry(onDispose)
    local byResource = {}
    local ownerOf = {}
    local function track(resource, id)
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

    AddEventHandler("onResourceStop", function(resource)
        local owned = byResource[resource]
        if not owned then return end

        byResource[resource] = nil

        for id in pairs(owned) do
            ownerOf[id] = nil
            local ok, err = pcall(onDispose, id)
            if not ok then
                print(("^3[qblib:resources]^7 cleanup for %s id %s failed: %s")
                    :format(resource, tostring(id), tostring(err)))
            end
        end
    end)

    return { track = track, untrack = untrack, owner = owner }
end
