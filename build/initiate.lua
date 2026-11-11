Kora = setmetatable({}, {
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

Kora.compat.isCallable = isCallable

-- Shared opaque-token generator (callback, event, NUI, screenshot and minigame tokens).
-- math.random alone is predictable from one observed token if seeded only by timers, and FiveM has
-- no secure random source, so the generator is re-stirred with timing noise before AND after each
-- token. `os` is server-only and GetGameTimer is the one shared clock, so every source is optional.
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
function Kora.compat.generateToken(length)
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
