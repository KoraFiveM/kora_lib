-- Seeded ONCE at load, not per session: reseeding from a time-derived value
-- on every call would hand two same-millisecond sessions identical RNG state
-- -- and therefore identical "secret" solutions. Same idiom local/callback/server.lua
-- uses for its own token generator.
math.randomseed(GetGameTimer() + math.floor(os.clock() * 1000000))

local sessions = {}
local sessionCountBySrc = {}
local nextSessionId = 0

local function randomFloat(min, max)
    return min + math.random() * (max - min)
end

local function clampNumber(value, fallback, min, max)
    if type(value) ~= "number" then return fallback end
    return math.max(min, math.min(max, value))
end

local function clampInt(value, fallback, min, max)
    if type(value) ~= "number" then return fallback end
    return math.floor(math.max(min, math.min(max, value)))
end

------------------------------------------------------------------------------
-- Per-type difficulty resolution. `opts` arrives over the network from the
-- CLIENT (QB.minigames.play's second argument, forwarded verbatim by
-- QB.callback.trigger) -- a modified client could send anything, so every
-- field is clamped against a hard, non-client-adjustable range rather than
-- trusted outright. The anti-cheat timing floors (minTimePerPin, etc.) are
-- NOT exposed here at all -- they stay fixed at their Config.minigames value,
-- read directly from Config by the matching validate.* function below.
------------------------------------------------------------------------------

local resolveConfig = {}

function resolveConfig.lockpick(opts)
    local cfg = Config.minigames.lockpick
    return {
        attempts = clampInt(opts and opts.attempts, cfg.attempts, 1, Config.minigames.maxAttemptsCap),
        pinCount = clampInt(opts and opts.pinCount, cfg.pinCount, 1, 12),
        tolerance = clampNumber(opts and opts.tolerance, cfg.tolerance, 0.03, 0.35),
        speed = clampNumber(opts and opts.speed, cfg.speed, 0.3, 4.0),
        timeLimit = clampNumber(opts and opts.timeLimit, cfg.timeLimit, 2000, 60000),
    }
end

function resolveConfig.skillbar(opts)
    local cfg = Config.minigames.skillbar
    return {
        attempts = clampInt(opts and opts.attempts, cfg.attempts, 1, Config.minigames.maxAttemptsCap),
        zoneSize = clampNumber(opts and opts.zoneSize, cfg.zoneSize, 0.05, 0.6),
        speed = clampNumber(opts and opts.speed, cfg.speed, 0.3, 4.0),
        timeLimit = clampNumber(opts and opts.timeLimit, cfg.timeLimit, 1500, 30000),
    }
end

function resolveConfig.circuit(opts)
    local cfg = Config.minigames.circuit
    return {
        attempts = clampInt(opts and opts.attempts, cfg.attempts, 1, Config.minigames.maxAttemptsCap),
        nodeCount = clampInt(opts and opts.nodeCount, cfg.nodeCount, 2, 8),
        timeLimit = clampNumber(opts and opts.timeLimit, cfg.timeLimit, 3000, 60000),
    }
end

function resolveConfig.mash(opts)
    local cfg = Config.minigames.mash
    return {
        attempts = clampInt(opts and opts.attempts, cfg.attempts, 1, Config.minigames.maxAttemptsCap),
        requiredPresses = clampInt(opts and opts.requiredPresses, cfg.requiredPresses, 3, 100),
        timeLimit = clampNumber(opts and opts.timeLimit, cfg.timeLimit, 1000, 30000),
    }
end

------------------------------------------------------------------------------
-- Per-type generation/validation. `generate` returns solution (kept
-- server-side only, never sent to the client) and public (exactly what's
-- sent to the NUI to render the round). `validate` recomputes correctness
-- from solution and the client's reported attempt -- raw input timestamps
-- (and, for circuit, which nodes were connected), never a client-computed
-- position or pass/fail. A validate function may `assert` on a malformed
-- attempt shape; the submit handler below pcalls it and treats that the same
-- as a legitimate failed attempt, not a protocol error.
------------------------------------------------------------------------------

local generate = {}
local validate = {}

-- One random target in [tolerance, 1 - tolerance] per pin (kept off the
-- extreme edges of the wave so every pin has a reachable window on both
-- sides of the target) plus a shared movement speed. The target zone is
-- exactly what the player sees rendered -- that IS the game -- so sending it
-- isn't a leak; what's never sent is a computed position at any given
-- instant, which is what a forged attempt would need.
function generate.lockpick(cfg)
    local pins = {}
    for i = 1, cfg.pinCount do
        pins[i] = { index = i, target = randomFloat(cfg.tolerance, 1 - cfg.tolerance) }
    end

    local solution = { pins = pins, speed = cfg.speed, tolerance = cfg.tolerance }
    local public = { pinCount = cfg.pinCount, tolerance = cfg.tolerance, speed = cfg.speed, pins = pins }

    return solution, public
end

function validate.lockpick(session, attempt)
    assert(type(attempt) == "table" and type(attempt.presses) == "table", "malformed lockpick attempt.")

    local solution = session.solution
    assert(#attempt.presses == #solution.pins, "lockpick attempt must press every pin exactly once.")

    local floor = Config.minigames.lockpick.minTimePerPin
    local lastElapsed = -floor

    for i, press in ipairs(attempt.presses) do
        assert(type(press.index) == "number" and type(press.elapsed) == "number", "malformed lockpick press.")
        assert(press.index == i, "lockpick pins must be pressed in order.")
        assert(press.elapsed >= 0 and press.elapsed <= session.timeLimit, "lockpick press outside the round's time limit.")
        assert(press.elapsed >= lastElapsed + floor, "lockpick presses are too close together to be human.")

        local pin = solution.pins[press.index]
        local position = QB.minigames.triangleWave(press.elapsed, solution.speed)

        if math.abs(position - pin.target) > solution.tolerance then
            return false
        end

        lastElapsed = press.elapsed
    end

    return true
end

function generate.skillbar(cfg)
    local zoneStart = randomFloat(0, 1 - cfg.zoneSize)
    local solution = { zoneStart = zoneStart, zoneEnd = zoneStart + cfg.zoneSize, speed = cfg.speed }
    local public = { zoneStart = solution.zoneStart, zoneEnd = solution.zoneEnd, speed = cfg.speed }

    return solution, public
end

function validate.skillbar(session, attempt)
    assert(type(attempt) == "table" and type(attempt.elapsed) == "number", "malformed skillbar attempt.")
    assert(attempt.elapsed >= 0 and attempt.elapsed <= session.timeLimit, "skillbar press outside the round's time limit.")
    assert(attempt.elapsed >= Config.minigames.skillbar.minReactionTime, "skillbar press too fast to be human.")

    local solution = session.solution
    local position = QB.minigames.triangleWave(attempt.elapsed, solution.speed)

    return position >= solution.zoneStart and position <= solution.zoneEnd
end

-- Colors double as the puzzle's own answer key: inputs and outputs share the
-- same random color set one-to-one, so correctness is visually inherent
-- (connect matching colors) instead of needing a separately-communicated
-- mapping the client would have to keep secret (and couldn't, since it's the
-- client rendering the puzzle).
local CIRCUIT_COLORS = { "red", "blue", "green", "yellow", "purple", "orange", "cyan", "pink" }

function generate.circuit(cfg)
    local count = cfg.nodeCount
    assert(count <= #CIRCUIT_COLORS, "circuit nodeCount exceeds the available color palette.")

    local colors = {}
    for i = 1, count do colors[i] = CIRCUIT_COLORS[i] end
    -- Fisher-Yates: which color lands on which input/output pair is what's
    -- actually randomized per round, not just which colors are in play.
    for i = count, 2, -1 do
        local j = math.random(1, i)
        colors[i], colors[j] = colors[j], colors[i]
    end

    local nodes = {}
    local colorByInput, colorByOutput = {}, {}

    for i = 1, count do
        local inputId, outputId = "in" .. i, "out" .. i
        colorByInput[inputId] = colors[i]
        colorByOutput[outputId] = colors[i]
        nodes[#nodes + 1] = { id = inputId, color = colors[i], side = "input" }
        nodes[#nodes + 1] = { id = outputId, color = colors[i], side = "output" }
    end

    local solution = { colorByInput = colorByInput, colorByOutput = colorByOutput, inputCount = count }
    local public = { nodes = nodes }

    return solution, public
end

function validate.circuit(session, attempt)
    assert(type(attempt) == "table" and type(attempt.connections) == "table", "malformed circuit attempt.")

    local solution = session.solution
    assert(#attempt.connections == solution.inputCount, "circuit attempt must connect every input exactly once.")

    local floor = Config.minigames.circuit.minTimePerConnection
    local lastElapsed = -floor
    local usedInputs, usedOutputs = {}, {}

    for _, conn in ipairs(attempt.connections) do
        assert(type(conn.from) == "string" and type(conn.to) == "string" and type(conn.elapsed) == "number",
            "malformed circuit connection.")
        assert(conn.elapsed >= 0 and conn.elapsed <= session.timeLimit, "circuit connection outside the round's time limit.")
        assert(conn.elapsed >= lastElapsed + floor, "circuit connections are too close together to be human.")
        assert(not usedInputs[conn.from], "circuit input connected more than once.")
        assert(not usedOutputs[conn.to], "circuit output connected more than once.")

        usedInputs[conn.from] = true
        usedOutputs[conn.to] = true
        lastElapsed = conn.elapsed

        local fromColor = solution.colorByInput[conn.from]
        local toColor = solution.colorByOutput[conn.to]

        if fromColor == nil or toColor == nil or fromColor ~= toColor then
            return false
        end
    end

    return true
end

function generate.mash(cfg)
    local solution = { requiredPresses = cfg.requiredPresses, timeLimit = cfg.timeLimit }
    local public = { requiredPresses = cfg.requiredPresses, timeLimit = cfg.timeLimit }

    return solution, public
end

function validate.mash(session, attempt)
    assert(type(attempt) == "table" and type(attempt.pressTimestamps) == "table", "malformed mash attempt.")

    local solution = session.solution
    local floor = Config.minigames.mash.minPressInterval
    local last = -floor

    for _, t in ipairs(attempt.pressTimestamps) do
        assert(type(t) == "number", "malformed mash press timestamp.")
        assert(t >= 0 and t <= solution.timeLimit, "mash press outside the round's time limit.")
        assert(t >= last + floor, "mash presses are too close together to be human.")
        last = t
    end

    return #attempt.pressTimestamps >= solution.requiredPresses
end

------------------------------------------------------------------------------
-- Session lifecycle
------------------------------------------------------------------------------

local function endSession(session)
    if session.ended then return end
    session.ended = true

    sessions[session.id] = nil

    local count = sessionCountBySrc[session.src]
    if count then
        sessionCountBySrc[session.src] = count - 1
        if sessionCountBySrc[session.src] <= 0 then sessionCountBySrc[session.src] = nil end
    end
end

-- A minigame session is player state, not resource-owned state: unlike
-- QB.zones.box() or QB.callback.register(), QB.minigames.play() is called
-- from the CLIENT and reaches this server-side handler over a network event
-- (see local/callback/server.lua's events.invoke), not via a direct
-- cross-resource Lua call -- so GetInvokingResource() would be meaningless
-- here (nil, every time). Cleanup is tied to the PLAYER instead, exactly
-- like local/callback/server.lua's own token cleanup.
AddEventHandler("playerDropped", function()
    local src = source
    for _, session in pairs(sessions) do
        if session.src == src then endSession(session) end
    end
end)

-- Backstop for a session nobody ever submits against again (the owning
-- client gave up, crashed, or the calling resource stopped without the
-- player disconnecting) -- expiresAt is already checked on every submit, but
-- without this an abandoned session would otherwise sit in `sessions`
-- forever. 30s is coarse on purpose: this only needs to reclaim memory
-- eventually, not the moment a session goes stale.
CreateThread(function()
    while true do
        Wait(30000)

        local now = GetGameTimer()
        for _, session in pairs(sessions) do
            if now > session.expiresAt then endSession(session) end
        end
    end
end)

QB.callback.register("qblib:minigames:start", function(src, gameType, opts)
    assert(QB.minigames.GAME_TYPES[gameType], "invalid minigame type.")
    assert(opts == nil or type(opts) == "table", "minigame opts must be a table.")

    local activeCount = sessionCountBySrc[src] or 0
    if activeCount >= Config.minigames.maxConcurrentPerPlayer then
        error("A minigame is already in progress for this player.")
    end

    local cfg = resolveConfig[gameType](opts)
    local solution, public = generate[gameType](cfg)

    nextSessionId = nextSessionId + 1
    local sessionId = nextSessionId
    local now = GetGameTimer()

    sessions[sessionId] = {
        id = sessionId,
        src = src,
        gameType = gameType,
        cfg = cfg,
        solution = solution,
        maxAttempts = cfg.attempts,
        attemptsUsed = 0,
        timeLimit = cfg.timeLimit,
        createdAt = now,
        expiresAt = now + Config.minigames.sessionTTL,
        ended = false,
    }
    sessionCountBySrc[src] = activeCount + 1

    return { sessionId = sessionId, attempt = 1, attempts = cfg.attempts, timeLimit = cfg.timeLimit, public = public }
end)

QB.callback.register("qblib:minigames:submit", function(src, sessionId, attempt)
    local session = sessions[sessionId]
    if session == nil or session.src ~= src then
        error("No active minigame session.")
    end

    if GetGameTimer() > session.expiresAt then
        local attemptsUsed = session.attemptsUsed
        endSession(session)
        return { done = true, success = false, attemptsUsed = attemptsUsed }
    end

    local ok, passed = pcall(validate[session.gameType], session, attempt)
    session.attemptsUsed = session.attemptsUsed + 1

    if ok and passed == true then
        local attemptsUsed = session.attemptsUsed
        endSession(session)
        return { done = true, success = true, attemptsUsed = attemptsUsed }
    end

    if session.attemptsUsed >= session.maxAttempts then
        local attemptsUsed = session.attemptsUsed
        endSession(session)
        return { done = true, success = false, attemptsUsed = attemptsUsed }
    end

    -- Anti-farming: every failed attempt (including a malformed/short one)
    -- regenerates a fresh solution/public payload before the next round --
    -- otherwise a player who fails once could simply memorize and repeat the
    -- same target.
    local solution, public = generate[session.gameType](session.cfg)
    session.solution = solution

    return {
        done = false,
        sessionId = sessionId,
        attempt = session.attemptsUsed + 1,
        attempts = session.maxAttempts,
        timeLimit = session.timeLimit,
        public = public,
    }
end)

-- Player-initiated early exit (Escape in the NUI, see client.lua's beginPlay)
-- -- distinct from letting the round's own timeLimit lapse, which is still a
-- normal failed attempt via submit above. Ending the session here immediately
-- rather than leaving it for expiresAt/the 30s sweep matters for
-- maxConcurrentPerPlayer: without this, a player who cancels and immediately
-- retries would spuriously hit "already in progress" for up to sessionTTL.
-- Does NOT consume an attempt -- a cancel isn't a failed guess at the puzzle.
QB.callback.register("qblib:minigames:cancel", function(src, sessionId)
    local session = sessions[sessionId]
    if session == nil or session.src ~= src then return false end
    endSession(session)
    return true
end)
