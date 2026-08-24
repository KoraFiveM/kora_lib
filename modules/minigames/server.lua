-- Seeded ONCE at load, not per session: reseeding from a time-derived value
-- on every call would hand two same-millisecond sessions identical RNG state
-- -- and therefore identical "secret" solutions. Same idiom local/callback/server.lua
-- uses for its own token generator.
math.randomseed(GetGameTimer() + math.floor(os.clock() * 1000000))

local sessions = {}
local sessionCountBySrc = {}
local nextSessionId = 0
local proofs = {}
local nextProofId = 0

local function createProof(session)
    nextProofId = nextProofId + 1
    local token = ('%s:%s:%s:%s'):format(session.src, session.id, nextProofId, math.random(100000, 999999))
    proofs[token] = {
        src = session.src,
        gameType = session.gameType,
        expiresAt = GetGameTimer() + Config.minigames.proofTTL,
    }
    return token
end

---Consumes a successful minigame proof exactly once. Gameplay resources call
---this on the server instead of accepting a client-computed success boolean.
---@param src integer
---@param token string
---@param gameType string
---@return boolean
function QB.minigames.consumeProof(src, token, gameType)
    if type(token) ~= 'string' or type(gameType) ~= 'string' then return false end
    local proof = proofs[token]
    if not proof then return false end
    proofs[token] = nil
    return proof.src == src and proof.gameType == gameType and proof.expiresAt >= GetGameTimer()
end

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
-- The six types below back compat/client/qb-minigames.lua. Unlike
-- lockpick/skillbar/circuit/mash, their puzzle CONTENT (the PIN, the word,
-- the quiz questions) is supplied by the calling script via opts, exactly
-- like the real qb-minigames exports it's standing in for -- so resolveConfig
-- here validates/carries that content through in addition to clamping the
-- usual difficulty/timing numbers.
------------------------------------------------------------------------------

function resolveConfig.pinpad(opts)
    local cfg = Config.minigames.pinpad
    local numbers = opts and opts.numbers
    local digits = clampInt(opts and opts.digits, cfg.digits, 3, 8)
    if type(numbers) == "number" or type(numbers) == "string" then
        digits = #tostring(numbers)
    end

    return {
        attempts = clampInt(opts and opts.attempts, cfg.attempts, 1, Config.minigames.maxAttemptsCap),
        numbers = numbers,
        digits = clampInt(digits, cfg.digits, 3, 8),
        timeLimit = clampNumber(opts and opts.timeLimit, cfg.timeLimit, 3000, 60000),
    }
end

function resolveConfig.quiz(opts)
    local cfg = Config.minigames.quiz
    assert(opts and type(opts.questions) == "table" and #opts.questions > 0, "quiz requires a non-empty questions list.")

    local questions = {}
    for i, q in ipairs(opts.questions) do
        assert(type(q.question) == "string" and type(q.answer) == "string" and type(q.options) == "table",
            "malformed quiz question.")
        questions[i] = { question = q.question, answer = q.answer, options = q.options }
    end

    local timePerQuestion = clampNumber(opts.timer and opts.timer * 1000, cfg.timePerQuestion, 2000, 120000)

    return {
        attempts = clampInt(opts.attempts, cfg.attempts, 1, Config.minigames.maxAttemptsCap),
        questions = questions,
        correctRequired = clampInt(opts.correctRequired, cfg.correctRequired, 1, #questions),
        timePerQuestion = timePerQuestion,
        timeLimit = clampNumber(timePerQuestion * #questions, cfg.timePerQuestion * #questions, 2000, 600000),
    }
end

function resolveConfig.wordguess(opts)
    local cfg = Config.minigames.wordguess
    assert(opts and type(opts.word) == "string" and opts.word ~= "", "wordguess requires a non-empty word.")

    return {
        attempts = clampInt(opts.attempts, cfg.attempts, 1, Config.minigames.maxAttemptsCap),
        word = opts.word:lower(),
        hint = type(opts.hint) == "string" and opts.hint or "",
        guesses = clampInt(opts.guesses, cfg.guesses, 1, 26),
        timeLimit = clampNumber(opts.timeLimit, cfg.timeLimit, 5000, 300000),
    }
end

function resolveConfig.wordscramble(opts)
    local cfg = Config.minigames.wordscramble
    assert(opts and type(opts.word) == "string" and opts.word ~= "", "wordscramble requires a non-empty word.")

    return {
        attempts = clampInt(opts.attempts, cfg.attempts, 1, Config.minigames.maxAttemptsCap),
        word = opts.word:lower(),
        hint = type(opts.hint) == "string" and opts.hint or "",
        timeLimit = clampNumber(opts.timer and opts.timer * 1000, cfg.timeLimit, 3000, 300000),
    }
end

function resolveConfig.keys(opts)
    local cfg = Config.minigames.keys
    local amount = clampInt(opts and opts.amount, cfg.amount, 1, 30)
    return {
        attempts = 1, -- upstream's KeyMinigame always runs to completion once, never retries
        amount = amount,
        timeLimit = amount * cfg.perKeyWindow,
    }
end

function resolveConfig.hacking(opts)
    local cfg = Config.minigames.hacking
    local timeout = clampNumber(opts and opts.timeout, cfg.timeout, 5, 120)
    return {
        attempts = 1, -- upstream's Hacking is a single pass/fail against a countdown, not a multi-attempt puzzle
        solutionsize = clampInt(opts and opts.solutionsize, cfg.solutionsize, 2, 10),
        timeLimit = timeout * 1000,
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

-- The PIN's digits are exactly what a real keypad shows the player (there's
-- no "hidden" pinpad face) -- what's never sent is which digits the player
-- has already entered, so a forged submission still has to reproduce the
-- correct sequence with human-plausible spacing.
function generate.pinpad(cfg)
    local digits = {}
    if cfg.numbers ~= nil then
        for ch in tostring(cfg.numbers):gmatch("%d") do
            digits[#digits + 1] = tonumber(ch)
        end
    end
    if #digits == 0 then
        for i = 1, cfg.digits do digits[i] = math.random(0, 9) end
    end

    local solution = { digits = digits }
    local public = { digitCount = #digits }

    return solution, public
end

function validate.pinpad(session, attempt)
    assert(type(attempt) == "table" and type(attempt.digits) == "table", "malformed pinpad attempt.")

    local solution = session.solution
    assert(#attempt.digits == #solution.digits, "pinpad attempt must submit every digit exactly once.")

    local floor = Config.minigames.pinpad.minTimePerDigit
    local lastElapsed = -floor
    local allMatch = true

    for i, entry in ipairs(attempt.digits) do
        assert(type(entry.value) == "number" and type(entry.elapsed) == "number", "malformed pinpad digit.")
        assert(entry.elapsed >= 0 and entry.elapsed <= session.timeLimit, "pinpad digit outside the round's time limit.")
        assert(entry.elapsed >= lastElapsed + floor, "pinpad digits are too close together to be human.")
        lastElapsed = entry.elapsed

        if entry.value ~= solution.digits[i] then allMatch = false end
    end

    return allMatch
end

-- The questions/options ARE the puzzle the client renders (same reasoning as
-- circuit's colors); what's stripped out of `public` and kept only in
-- `solution` is each question's `answer`, which is what the client must
-- never be trusted to grade itself.
function generate.quiz(cfg)
    local publicQuestions = {}
    for i, q in ipairs(cfg.questions) do
        publicQuestions[i] = { numb = i, question = q.question, options = q.options }
    end

    local solution = { questions = cfg.questions, correctRequired = cfg.correctRequired }
    local public = { questions = publicQuestions, correctRequired = cfg.correctRequired, timePerQuestion = cfg.timePerQuestion }

    return solution, public
end

function validate.quiz(session, attempt)
    assert(type(attempt) == "table" and type(attempt.answers) == "table", "malformed quiz attempt.")

    local solution = session.solution
    assert(#attempt.answers == #solution.questions, "quiz attempt must answer every question exactly once.")

    local floor = Config.minigames.quiz.minTimePerAnswer
    local lastElapsed = -floor
    local correct = 0

    for i, entry in ipairs(attempt.answers) do
        assert(type(entry.choice) == "string" and type(entry.elapsed) == "number", "malformed quiz answer.")
        assert(entry.elapsed >= 0 and entry.elapsed <= session.timeLimit, "quiz answer outside the round's time limit.")
        assert(entry.elapsed >= lastElapsed + floor, "quiz answers are too close together to be human.")
        lastElapsed = entry.elapsed

        if entry.choice == solution.questions[i].answer then correct = correct + 1 end
    end

    return correct >= solution.correctRequired
end

-- Only `hint` and the word's length are sent to the client -- the word
-- itself stays server-side in `solution` and is only ever revealed one
-- letter at a time, as the player's own correct guesses accumulate.
function generate.wordguess(cfg)
    local solution = { word = cfg.word, guesses = cfg.guesses }
    local public = { hint = cfg.hint, length = #cfg.word, guesses = cfg.guesses }

    return solution, public
end

function validate.wordguess(session, attempt)
    assert(type(attempt) == "table" and type(attempt.guesses) == "table", "malformed wordguess attempt.")

    local solution = session.solution
    local floor = Config.minigames.wordguess.minTimePerGuess
    local lastElapsed = -floor
    local wrong = {}
    local found = {}
    for i = 1, #solution.word do found[i] = false end

    for _, g in ipairs(attempt.guesses) do
        assert(type(g.letter) == "string" and #g.letter == 1 and type(g.elapsed) == "number", "malformed wordguess letter.")
        assert(g.elapsed >= 0 and g.elapsed <= session.timeLimit, "wordguess letter outside the round's time limit.")
        assert(g.elapsed >= lastElapsed + floor, "wordguess letters are too close together to be human.")
        lastElapsed = g.elapsed

        local letter = g.letter:lower()
        local hitAny = false
        for i = 1, #solution.word do
            if solution.word:sub(i, i) == letter then
                found[i] = true
                hitAny = true
            end
        end
        if not hitAny then wrong[letter] = true end
    end

    local wrongCount = 0
    for _ in pairs(wrong) do wrongCount = wrongCount + 1 end
    if wrongCount > solution.guesses then return false end

    for i = 1, #solution.word do
        if not found[i] then return false end
    end

    return true
end

-- The scramble is generated server-side (never trust a client-provided
-- shuffle) so the answer stays hidden until the player actually solves it --
-- only the scrambled form + hint are sent as `public`.
function generate.wordscramble(cfg)
    local letters = {}
    for i = 1, #cfg.word do letters[i] = cfg.word:sub(i, i) end
    for i = #letters, 2, -1 do
        local j = math.random(1, i)
        letters[i], letters[j] = letters[j], letters[i]
    end

    local solution = { word = cfg.word }
    local public = { scrambled = table.concat(letters), hint = cfg.hint }

    return solution, public
end

function validate.wordscramble(session, attempt)
    assert(type(attempt) == "table" and type(attempt.guess) == "string" and type(attempt.elapsed) == "number",
        "malformed wordscramble attempt.")
    assert(attempt.elapsed >= 0 and attempt.elapsed <= session.timeLimit, "wordscramble submit outside the round's time limit.")
    assert(attempt.elapsed >= Config.minigames.wordscramble.minSubmitTime, "wordscramble submitted too fast to be human.")

    return attempt.guess:lower() == session.solution.word
end

local ARROW_KEYS = { "up", "down", "left", "right" }

-- The prompt sequence is revealed in full up front (public.pattern ==
-- solution.pattern) -- the player has to SEE which key is being asked for
-- next, same reasoning lockpick reveals each pin's target zone. What can't
-- be forged is reacting to each prompt with human-plausible timing.
function generate.keys(cfg)
    local pattern = {}
    for i = 1, cfg.amount do pattern[i] = ARROW_KEYS[math.random(1, #ARROW_KEYS)] end

    local solution = { pattern = pattern }
    local public = { pattern = pattern }

    return solution, public
end

-- Unlike every other type here, this always "passes" (mirrors upstream
-- KeyMinigame, which has no pass/fail concept of its own -- the calling
-- script decides what `faults` count is acceptable, per the real
-- resource's README example `if result.faults > 3 then ...`). `faults`
-- rides back to the caller as the submit handler's `extra` return value.
function validate.keys(session, attempt)
    assert(type(attempt) == "table" and type(attempt.presses) == "table", "malformed keys attempt.")

    local solution = session.solution
    local floor = Config.minigames.keys.minTimePerPress
    local lastElapsed = -floor
    local faults = 0

    for i, key in ipairs(solution.pattern) do
        local press = attempt.presses[i]
        if press == nil or type(press.key) ~= "string" or type(press.elapsed) ~= "number" then
            faults = faults + 1
        else
            assert(press.elapsed >= 0 and press.elapsed <= session.timeLimit, "keys press outside the round's time limit.")
            assert(press.elapsed >= lastElapsed + floor, "keys presses are too close together to be human.")
            lastElapsed = press.elapsed
            if press.key ~= key then faults = faults + 1 end
        end
    end

    return true, faults
end

local HEX_CHARS = "0123456789ABCDEF"

local function randomHex(length)
    local chars = {}
    for i = 1, length do
        local idx = math.random(1, #HEX_CHARS)
        chars[i] = HEX_CHARS:sub(idx, idx)
    end
    return table.concat(chars)
end

-- Simplified relative to upstream's dual hex-grid panel (two simultaneous
-- codes to find in a big noise grid): one code, revealed directly in
-- `public` exactly like lockpick's target zone or keys' pattern -- the skill
-- is submitting it before the countdown, not decrypting a hidden value.
function generate.hacking(cfg)
    local code = randomHex(cfg.solutionsize)

    local solution = { code = code }
    local public = { code = code, solutionsize = cfg.solutionsize }

    return solution, public
end

function validate.hacking(session, attempt)
    assert(type(attempt) == "table" and type(attempt.submitted) == "string" and type(attempt.elapsed) == "number",
        "malformed hacking attempt.")
    assert(attempt.elapsed >= 0 and attempt.elapsed <= session.timeLimit, "hacking submit outside the round's time limit.")
    assert(attempt.elapsed >= Config.minigames.hacking.minTimePerFind, "hacking submitted too fast to be human.")

    return attempt.submitted == session.solution.code
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
    for token, proof in pairs(proofs) do
        if proof.src == src then proofs[token] = nil end
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
        for token, proof in pairs(proofs) do
            if now > proof.expiresAt then proofs[token] = nil end
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

    -- `extra` is only ever set by validate.keys (its faults count) -- every
    -- other type's validate returns just the boolean, so `extra` is nil for
    -- them and this field is simply absent from their result.
    local ok, passed, extra = pcall(validate[session.gameType], session, attempt)
    session.attemptsUsed = session.attemptsUsed + 1

    if ok and passed == true then
        local attemptsUsed = session.attemptsUsed
        local proof = createProof(session)
        endSession(session)
        return { done = true, success = true, attemptsUsed = attemptsUsed, proof = proof, faults = extra }
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
