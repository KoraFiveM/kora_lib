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
-- keeps these private except for the explicitly published `provideExport` API.
-- Cfx funcrefs may arrive as functions, callable proxy tables,
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
-- event, NUI, screenshot and minigame tokens cannot drift into subtly
-- different formats.
--
-- math.random is not a secure source on its own: its state is fully
-- determined by the seed, so a seed that is only a sum of timers can be
-- brute-forced from one observed token, after which every later token (and
-- every minigame solution drawn from the same generator) is predictable. FiveM
-- exposes no secure random source (`io` cannot be relied on), so the generator
-- is re-stirred with fresh timing noise before AND after each token: what a
-- player can observe never reveals the state later draws start from.
-- `os` exists only on the server and `GetGameTimer` is the one clock both
-- realms share, so every source is optional.
local TOKEN_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
local tokenStirCount = 0

local function timingNoise()
    tokenStirCount = tokenStirCount + 1
    local timer = type(GetGameTimer) == 'function' and GetGameTimer() or 0
    local hasOs = type(os) == 'table'
    local processClock = hasOs and type(os.clock) == 'function' and os.clock() or 0
    local wallClock = hasOs and type(os.time) == 'function' and os.time() or 0
    -- os.clock is CPU time with sub-microsecond jitter; its low digits are the
    -- least predictable part, so scale it up and keep them.
    local clockDigits = math.floor(processClock * 1000000000)
    return clockDigits ~ (timer << 24) ~ (wallClock << 8) ~ tokenStirCount
end

local function stirTokenRandom()
    -- Fold the generator's own output in too, so the new state depends on the
    -- old one as well as on the noise.
    local carried = math.random(0, 0x7fffffff)
    math.randomseed(carried ~ timingNoise(), math.random(0, 0x7fffffff) ~ (timingNoise() << 1))
end

---@param length? integer
---@return string token
function QB.compat.generateToken(length)
    length = length or 32
    assert(type(length) == 'number' and length >= 1 and length % 1 == 0,
        'Token length must be a positive integer.')

    stirTokenRandom()
    local parts = {}
    for index = 1, length do
        local charIndex = math.random(1, #TOKEN_CHARS)
        parts[index] = TOKEN_CHARS:sub(charIndex, charIndex)
    end
    stirTokenRandom()
    return table.concat(parts)
end
