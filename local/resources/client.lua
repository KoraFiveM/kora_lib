local function assertId(id)
    assert(id ~= nil, KoraLang('Local.Resources.id_must_not_be_nil'))
end

local function assertResourceName(resource)
    assert(type(resource) == 'string' and resource ~= '' and #resource <= 256,
        KoraLang('Local.Resources.resource_name_invalid'))
end

---Creates an isolated ownership registry: a `resource -> {id set}` index for bulk cleanup plus an `id -> resource` reverse lookup.
---`onDispose(id)` runs for every id still tracked under a resource when it stops.
---Scope one registry to one id space; sharing across colliding id spaces corrupts the reverse lookup.
---@param onDispose fun(id: any) Called for each id still owned when its resource stops.
---@return KoraResourcesRegistry
function Kora.resources.registry(onDispose)
    assert(Kora.compat.isCallable(onDispose), KoraLang('Local.Resources.client_registry_requires_callable'))
    local byResource = {}
    local ownerOf = {}
    local sweeping = {}
    local function track(resource, id)
        assertResourceName(resource)
        assertId(id)
        assert(not sweeping[resource], KoraLang('Local.Resources.cannot_track_while_stopping'))
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
                Kora.logging.error('lib.client.cleanup_for_id_failed', KoraLang(
                    'Local.Resources.client_cleanup_failed', resource, tostring(id), tostring(err)))
            end
        end
        sweeping[resource] = nil
    end)

    return { track = track, untrack = untrack, owner = owner }
end
