---Waits until a GlobalState key has a non-nil value or the bounded timeout expires. `false` is a valid value.
---@param key string
---@param timeoutMs? integer Defaults to 5000.
---@param pollIntervalMs? integer Defaults to 50.
---@return any value
---@return string|nil reason
function Kora.state.awaitGlobal(key, timeoutMs, pollIntervalMs)
    assert(type(key) == "string" and key ~= "", "Kora.state.awaitGlobal requires a state key.")
    if timeoutMs == nil then timeoutMs = 5000 end
    if pollIntervalMs == nil then pollIntervalMs = 50 end
    assert(Kora.util.isInteger(timeoutMs) and timeoutMs >= 0,
        "timeoutMs must be a non-negative integer.")
    assert(Kora.util.isInteger(pollIntervalMs) and pollIntervalMs >= 0,
        "pollIntervalMs must be a non-negative integer.")

    local startedAt = GetGameTimer()
    repeat
        local value = GlobalState[key]
        if value ~= nil then return value end
        if GetGameTimer() - startedAt >= timeoutMs then return nil, "timeout" end
        Wait(pollIntervalMs)
    until false
end

-- globalMap: one GlobalState key per entry ('<name>:<key>') plus a key index ('<name>:__keys')
-- that is only rewritten when a key is added or removed. Server-side key sets are shared per
-- name and seeded from GlobalState, which outlives a kora_lib restart.
local INDEX_SUFFIX = "__keys"
local serverMapKeys = {}

local function assertMapName(name)
    assert(type(name) == "string" and name ~= "" and #name <= 64 and not name:find(":", 1, true),
        "Kora.state.globalMap name must be 1-64 bytes without ':'.")
end

local function mapKey(key)
    local keyType = type(key)
    assert((keyType == "string" and key ~= "" and #key <= 128 and key ~= INDEX_SUFFIX)
        or (keyType == "number" and Kora.util.isInteger(key)),
        "Kora.state.globalMap keys must be integers or 1-128 byte strings other than '__keys'.")
    -- math.tointeger: 5 and 5.0 must name the same entry.
    return keyType == "number" and tostring(math.tointeger(key)) or key
end

local function readAll(prefix)
    local all = {}
    local keys = GlobalState[prefix .. INDEX_SUFFIX]
    if type(keys) ~= "table" then return all end
    for index = 1, #keys do
        local key = keys[index]
        all[key] = GlobalState[prefix .. key]
    end
    return all
end

local function serverMap(name, prefix)
    local keys = serverMapKeys[name]
    if not keys then
        keys = {}
        local existing = GlobalState[prefix .. INDEX_SUFFIX]
        if type(existing) == "table" then
            for index = 1, #existing do keys[existing[index]] = true end
        else
            GlobalState[prefix .. INDEX_SUFFIX] = {}
        end
        serverMapKeys[name] = keys
    end

    local function publishIndex()
        local list = {}
        for key in pairs(keys) do list[#list + 1] = key end
        table.sort(list)
        GlobalState[prefix .. INDEX_SUFFIX] = list
    end

    local map = {}

    ---Writes one entry; `nil` removes it. Only an added or removed key resends the index.
    function map.set(key, value)
        key = mapKey(key)
        GlobalState[prefix .. key] = value
        local known = keys[key] == true
        if value == nil and known then
            keys[key] = nil
            publishIndex()
        elseif value ~= nil and not known then
            keys[key] = true
            publishIndex()
        end
    end

    function map.remove(key)
        map.set(key, nil)
    end

    function map.get(key)
        return GlobalState[prefix .. mapKey(key)]
    end

    function map.all()
        return readAll(prefix)
    end

    return map
end

local function clientMap(prefix)
    local map = {}

    function map.get(key)
        return GlobalState[prefix .. mapKey(key)]
    end

    ---Every entry, read through the key index.
    function map.all()
        return readAll(prefix)
    end

    ---Waits until the server has created the map (its index exists).
    ---@param timeoutMs? integer Defaults to 5000.
    ---@return boolean ready
    function map.ready(timeoutMs)
        return Kora.state.awaitGlobal(prefix .. INDEX_SUFFIX, timeoutMs) ~= nil
    end

    ---Runs `fn(key, value, old)` for every entry change in this map: one global state-bag
    ---handler filtered by prefix. Returns a Kora.state.offChange listener id.
    function map.onChange(fn)
        assert(Kora.compat.isCallable(fn), "Kora.state.globalMap onChange requires a callable.")
        local indexKey = prefix .. INDEX_SUFFIX
        return Kora.state.onChange(nil, "global", function(change)
            local stateKey = change.key
            if type(stateKey) ~= "string" or stateKey == indexKey or stateKey:sub(1, #prefix) ~= prefix then return end
            -- Change handlers run before the bag is updated, so GlobalState still holds the old value.
            fn(stateKey:sub(#prefix + 1), change.value, GlobalState[stateKey])
        end)
    end

    return map
end

---Replicates a keyed table through GlobalState one entry at a time instead of re-sending the
---whole table on every change. The server writes (`set`, `remove`, `get`, `all`); clients read
---(`get`, `all`, `ready`, `onChange`).
---@param name string 1-64 bytes, no ':'.
---@return table map
function Kora.state.globalMap(name)
    assertMapName(name)
    local prefix = name .. ":"
    if IsDuplicityVersion() then return serverMap(name, prefix) end
    return clientMap(prefix)
end
