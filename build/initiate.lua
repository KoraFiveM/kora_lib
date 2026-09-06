---Annotation-only declaration of CfxLua's promise (the deferred library
---exposed via promise.new()), so `---@return promise` annotations across the
---modules resolve to a real class for LuaLS instead of an unknown name.
---@class promise
---@field state string
---@field resolve fun(self: promise, value: any)
---@field reject fun(self: promise, err: any)
---@field next fun(self: promise, onResolved: (fun(value: any): any), onRejected: (fun(err: any): any)?): promise

QB = setmetatable({}, {
    __index = function(self, key)
        local module = {}
        rawset(self, key, module)
        return module
    end
})

-- Internal cross-realm compatibility helpers. build/finalise.lua deliberately
-- skips QB.compat, so these are shared by qblib's own chunks without becoming
-- public exports. Cfx funcrefs may arrive as functions, callable proxy tables,
-- or raw __cfx_functionReference envelopes depending on the boundary crossed.
local function isCallable(value, seen)
    if type(value) == 'function' then return true end
    if type(value) ~= 'table' then return false end
    if type(rawget(value, '__cfx_functionReference')) == 'string' then return true end

    seen = seen or {}
    if seen[value] then return false end
    seen[value] = true
    local mt = getmetatable(value)
    return type(mt) == 'table' and isCallable(mt.__call, seen)
end

QB.compat.isCallable = isCallable

-- Opaque protocol/session identifiers are needed in several independent Lua
-- chunks and in both realms. Keep the byte generation here so callback,
-- event, NUI, and minigame tokens cannot drift into subtly different formats.
-- Seeding is realm-local and lazy because client Lua has no `os` library.
local TOKEN_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
local tokenRandomSeeded = false

local function seedTokenRandom()
    if tokenRandomSeeded then return end
    local timer = type(GetGameTimer) == 'function' and GetGameTimer() or 0
    local processClock = type(os) == 'table' and type(os.clock) == 'function' and os.clock() or 0
    local wallClock = type(os) == 'table' and type(os.time) == 'function' and os.time() or 0
    math.randomseed(timer + wallClock + math.floor(processClock * 1000000))
    tokenRandomSeeded = true
end

---@param length? integer
---@return string token
function QB.compat.generateToken(length)
    length = length or 32
    assert(type(length) == 'number' and length >= 1 and length % 1 == 0,
        'Token length must be a positive integer.')
    seedTokenRandom()

    local parts = {}
    for index = 1, length do
        local charIndex = math.random(1, #TOKEN_CHARS)
        parts[index] = TOKEN_CHARS:sub(charIndex, charIndex)
    end
    return table.concat(parts)
end
