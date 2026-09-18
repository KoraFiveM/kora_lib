local sessions = {}
local sessionCountBySrc = {}
local nextSessionId = 0
local authorizations = {}
local proofs = {}
local endSession
local expirySweepRunning = false
local ensureExpirySweep

local function roundExpiry(now, cfg, overallExpiresAt)
    local roundWindow = math.max(
        Config.minigames.sessionTTL,
        cfg.timeLimit + Config.minigames.roundTimeoutBuffer
    )
    return math.min(overallExpiresAt, now + roundWindow)
end

local authorizationOwnership = QB.resources.serverRegistry(function(token)
    authorizations[token] = nil
end)

local proofOwnership = QB.resources.serverRegistry(function(token)
    proofs[token] = nil
end)

-- Only authorized sessions have a resource owner. Legacy sessions are still
-- player-scoped and cleaned up on cancel, expiry, or playerDropped.
local authorizedSessionOwnership = QB.resources.serverRegistry(function(sessionId)
    local session = sessions[sessionId]
    if session then endSession(session) end
end)

local function generateOpaqueToken()
    while true do
        local token = QB.compat.generateToken()
        if authorizations[token] == nil and proofs[token] == nil then return token end
    end
end

local function removeAuthorization(token)
    authorizations[token] = nil
    authorizationOwnership.untrack(token)
end

local function removeProof(token)
    proofs[token] = nil
    proofOwnership.untrack(token)
end

local function randomFloat(min, max)
    return min + math.random() * (max - min)
end

local isFiniteNumber = QB.util.isFiniteNumber

local function isInteger(value)
    return isFiniteNumber(value) and value % 1 == 0
end

local function clampNumber(value, fallback, min, max)
    if not isFiniteNumber(value) then return fallback end
    return math.max(min, math.min(max, value))
end

local function clampInt(value, fallback, min, max)
    if not isFiniteNumber(value) then return fallback end
    return math.floor(math.max(min, math.min(max, value)))
end

local function boundedString(value, label, maxBytes, allowEmpty)
    assert(type(value) == "string", label .. " must be a string.")
    assert(allowEmpty or #value > 0, label .. " must not be empty.")
    assert(#value <= maxBytes, label .. " exceeds the byte limit.")
    return value
end

-- `#`/ipairs alone can silently ignore sparse, hash-keyed, or very large
-- attacker-provided tables. Count keys with a hard ceiling, require every key
-- to be a positive array index, then verify the sequence is gap-free.
local function denseArrayLength(value, label, maxLength, minLength)
    assert(type(value) == "table", label .. " must be an array.")
    local count = 0
    for key in pairs(value) do
        count = count + 1
        assert(count <= maxLength, label .. " exceeds the item limit.")
        assert(isInteger(key) and key >= 1 and key <= maxLength, label .. " must be a dense array.")
    end
    assert(count >= (minLength or 0), label .. " does not contain enough items.")
    for i = 1, count do
        assert(rawget(value, i) ~= nil, label .. " must be a dense array.")
    end
    return count
end

local function assertElapsed(value, timeLimit, label)
    assert(isFiniteNumber(value), label .. " must be a finite number.")
    assert(value >= 0 and value <= timeLimit, label .. " is outside the round's time limit.")
end

------------------------------------------------------------------------------
-- Per-type difficulty resolution. Legacy `opts` arrives over the network
-- from the client; trusted `opts` arrives from authorizeProof's server caller.
-- Both paths use the same finite numeric clamps and content/array bounds, and
-- authorized start uses only the already-resolved trusted copy. Anti-cheat
-- timing floors are never exposed through either option table.
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
    local input = opts and opts.input
    assert(input == nil or (type(input) == 'string' and #input > 0 and #input <= 16),
        'skillbar input must be a non-empty string up to 16 characters.')
    return {
        attempts = clampInt(opts and opts.attempts, cfg.attempts, 1, Config.minigames.maxAttemptsCap),
        zoneSize = clampNumber(opts and opts.zoneSize, cfg.zoneSize, 0.05, 0.6),
        speed = clampNumber(opts and opts.speed, cfg.speed, 0.3, 4.0),
        timeLimit = clampNumber(opts and opts.timeLimit, cfg.timeLimit, 1500, 30000),
        input = input,
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

function resolveConfig.fishing(opts)
    local cfg = Config.minigames.fishing
    return {
        attempts = clampInt(opts and opts.attempts, cfg.attempts, 1, Config.minigames.maxAttemptsCap),
        bites = clampInt(opts and opts.bites, cfg.bites, 1, 8),
        zoneSize = clampNumber(opts and opts.zoneSize, cfg.zoneSize, 0.08, 0.45),
        speed = clampNumber(opts and opts.speed, cfg.speed, 0.3, 2.5),
        timeLimit = clampNumber(opts and opts.timeLimit, cfg.timeLimit, 3000, 30000),
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
    local maxDigits = Config.minigames.inputLimits.pinDigits
    local digits = clampInt(opts and opts.digits, cfg.digits, 3, maxDigits)
    if numbers ~= nil then
        assert(type(numbers) == "string" or isFiniteNumber(numbers), "pinpad numbers must be a finite number or string.")
        local source = tostring(numbers)
        boundedString(source, "pinpad numbers", Config.minigames.inputLimits.pinSourceBytes, false)

        local normalized = {}
        for digit in source:gmatch("%d") do
            assert(#normalized < Config.minigames.inputLimits.pinDigits, "pinpad numbers contains too many digits.")
            normalized[#normalized + 1] = digit
        end
        assert(#normalized > 0, "pinpad numbers must contain at least one digit.")
        numbers = table.concat(normalized)
        digits = #normalized
    end

    return {
        attempts = clampInt(opts and opts.attempts, cfg.attempts, 1, Config.minigames.maxAttemptsCap),
        numbers = numbers,
        digits = clampInt(digits, cfg.digits, 3, maxDigits),
        timeLimit = clampNumber(opts and opts.timeLimit, cfg.timeLimit, 3000, 60000),
    }
end

function resolveConfig.quiz(opts)
    local cfg = Config.minigames.quiz
    assert(opts and type(opts.questions) == "table", "quiz requires a non-empty questions list.")
    local questionCount = denseArrayLength(opts.questions, "quiz questions", Config.minigames.inputLimits.quizQuestions, 1)

    local questions = {}
    for i = 1, questionCount do
        local q = opts.questions[i]
        assert(type(q.question) == "string" and type(q.answer) == "string" and type(q.options) == "table",
            "malformed quiz question.")
        boundedString(q.question, "quiz question", Config.minigames.inputLimits.quizQuestionBytes, true)
        boundedString(q.answer, "quiz answer", Config.minigames.inputLimits.quizOptionBytes, true)

        local optionCount = denseArrayLength(q.options, "quiz options", Config.minigames.inputLimits.quizOptionsPerQuestion, 1)
        local options = {}
        for optionIndex = 1, optionCount do
            options[optionIndex] = boundedString(q.options[optionIndex], "quiz option",
                Config.minigames.inputLimits.quizOptionBytes, true)
        end
        questions[i] = { question = q.question, answer = q.answer, options = options }
    end

    local requestedTimer = isFiniteNumber(opts.timer) and opts.timer * 1000 or nil
    local timePerQuestion = clampNumber(requestedTimer, cfg.timePerQuestion, 2000, 120000)

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
    boundedString(opts.word, "wordguess word", Config.minigames.inputLimits.wordGuessBytes, false)
    assert(opts.word:match("^[A-Za-z]+$") ~= nil, "wordguess word must contain only ASCII letters.")
    local hint = opts.hint == nil and "" or boundedString(opts.hint, "wordguess hint",
        Config.minigames.inputLimits.hintBytes, true)

    return {
        attempts = clampInt(opts.attempts, cfg.attempts, 1, Config.minigames.maxAttemptsCap),
        word = opts.word:lower(),
        hint = hint,
        guesses = clampInt(opts.guesses, cfg.guesses, 1, 26),
        timeLimit = clampNumber(opts.timeLimit, cfg.timeLimit, 5000, 300000),
    }
end

function resolveConfig.wordscramble(opts)
    local cfg = Config.minigames.wordscramble
    assert(opts and type(opts.word) == "string" and opts.word ~= "", "wordscramble requires a non-empty word.")
    boundedString(opts.word, "wordscramble word", Config.minigames.inputLimits.wordScrambleBytes, false)
    local hint = opts.hint == nil and "" or boundedString(opts.hint, "wordscramble hint",
        Config.minigames.inputLimits.hintBytes, true)
    local requestedTimer = isFiniteNumber(opts.timer) and opts.timer * 1000 or nil

    return {
        attempts = clampInt(opts.attempts, cfg.attempts, 1, Config.minigames.maxAttemptsCap),
        word = opts.word:lower(),
        hint = hint,
        timeLimit = clampNumber(requestedTimer, cfg.timeLimit, 3000, 300000),
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

local function issueAuthorization(src, gameType, cfg)
    local issuer = GetInvokingResource() or GetCurrentResourceName()
    local token = generateOpaqueToken()
    ensureExpirySweep()
    authorizations[token] = {
        src = src,
        gameType = gameType,
        cfg = cfg,
        issuer = issuer,
        expiresAt = GetGameTimer() + Config.minigames.authorizationTTL,
    }
    authorizationOwnership.track(issuer, token)
    return token
end

---Issues one opaque authorization for a proof-producing minigame session.
---This must be called by the server gameplay resource that will later consume
---the proof. The trusted options are resolved and copied now; the client may
---still send an opts table to play(), but it is ignored for this session.
---@param src integer
---@param gameType string
---@param trustedOpts? table
---@return string authorization
function QB.minigames.authorizeProof(src, gameType, trustedOpts)
    assert(isInteger(src) and src >= 1, "src must be a positive player server ID.")
    assert(type(gameType) == "string" and QB.minigames.GAME_TYPES[gameType], "invalid minigame type.")
    assert(trustedOpts == nil or type(trustedOpts) == "table", "trusted minigame opts must be a table.")

    return issueAuthorization(src, gameType, resolveConfig[gameType](trustedOpts))
end

---Issues a proof authorization after applying the player's qbskills bonus to
---the trusted, server-resolved minigame configuration. If qbskills is absent,
---the configuration is left unchanged. The resulting difficulty is captured
---in the authorization, so the client cannot weaken it before starting.
---@param src integer
---@param skill string
---@param gameType string
---@param trustedOpts? table
---@return string authorization
function QB.minigames.authorizeSkillCheck(src, skill, gameType, trustedOpts)
    assert(isInteger(src) and src >= 1, 'src must be a positive player server ID.')
    assert(type(skill) == 'string' and skill ~= '', 'skill must be a non-empty string.')
    assert(type(gameType) == 'string' and QB.minigames.GAME_TYPES[gameType], 'invalid minigame type.')
    assert(trustedOpts == nil or type(trustedOpts) == 'table', 'trusted minigame opts must be a table.')

    local cfg = resolveConfig[gameType](trustedOpts)
    local adjusted = QB.skills.adjustMinigame(src, skill, gameType, cfg)
    return issueAuthorization(src, gameType, adjusted)
end

local function createProof(session)
    if session.authorization == nil then return nil end

    local token = generateOpaqueToken()
    ensureExpirySweep()
    proofs[token] = {
        src = session.src,
        gameType = session.gameType,
        authorization = session.authorization,
        issuer = session.issuer,
        expiresAt = GetGameTimer() + Config.minigames.proofTTL,
    }
    proofOwnership.track(session.issuer, token)
    return token
end

---Consumes a successful authorized minigame proof exactly once. Every binding
---must match; a mismatch returns false without burning a valid proof.
---@param src integer
---@param token string
---@param gameType string
---@param authorization string
---@return boolean
function QB.minigames.consumeProof(src, token, gameType, authorization)
    if not isInteger(src) or src < 1 or type(token) ~= "string" or
        type(gameType) ~= "string" or type(authorization) ~= "string" then
        return false
    end

    local proof = proofs[token]
    if not proof then return false end
    if proof.expiresAt < GetGameTimer() then
        removeProof(token)
        return false
    end

    local issuer = GetInvokingResource() or GetCurrentResourceName()
    if proof.src ~= src or proof.gameType ~= gameType or
        proof.authorization ~= authorization or proof.issuer ~= issuer then
        return false
    end

    removeProof(token)
    return true
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
    local pressCount = denseArrayLength(attempt.presses, "lockpick presses", #solution.pins, #solution.pins)
    assert(pressCount == #solution.pins, "lockpick attempt must press every pin exactly once.")

    local floor = Config.minigames.lockpick.minTimePerPin
    local lastElapsed = -floor

    for i = 1, pressCount do
        local press = attempt.presses[i]
        assert(type(press) == "table" and isInteger(press.index), "malformed lockpick press.")
        assert(press.index == i, "lockpick pins must be pressed in order.")
        assertElapsed(press.elapsed, session.timeLimit, "lockpick press")
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
    local public = { zoneStart = solution.zoneStart, zoneEnd = solution.zoneEnd, speed = cfg.speed, input = cfg.input }

    return solution, public
end

function validate.skillbar(session, attempt)
    assert(type(attempt) == "table", "malformed skillbar attempt.")
    assertElapsed(attempt.elapsed, session.timeLimit, "skillbar press")
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
    local connectionCount = denseArrayLength(attempt.connections, "circuit connections",
        solution.inputCount, solution.inputCount)
    assert(connectionCount == solution.inputCount, "circuit attempt must connect every input exactly once.")

    local floor = Config.minigames.circuit.minTimePerConnection
    local lastElapsed = -floor
    local usedInputs, usedOutputs = {}, {}

    for i = 1, connectionCount do
        local conn = attempt.connections[i]
        assert(type(conn) == "table" and type(conn.from) == "string" and type(conn.to) == "string",
            "malformed circuit connection.")
        boundedString(conn.from, "circuit input id", 16, false)
        boundedString(conn.to, "circuit output id", 16, false)
        assertElapsed(conn.elapsed, session.timeLimit, "circuit connection")
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
    local pressCount = denseArrayLength(attempt.pressTimestamps, "mash press timestamps",
        solution.requiredPresses, 0)
    local floor = Config.minigames.mash.minPressInterval
    local last = -floor

    for i = 1, pressCount do
        local t = attempt.pressTimestamps[i]
        assertElapsed(t, solution.timeLimit, "mash press")
        assert(t >= last + floor, "mash presses are too close together to be human.")
        last = t
    end

    return pressCount >= solution.requiredPresses
end

function generate.fishing(cfg)
    local targets = {}
    for i = 1, cfg.bites do
        targets[i] = randomFloat(cfg.zoneSize / 2, 1 - cfg.zoneSize / 2)
    end

    local solution = { targets = targets, speed = cfg.speed, zoneSize = cfg.zoneSize }
    local public = { biteCount = cfg.bites, speed = cfg.speed, zoneSize = cfg.zoneSize, targets = targets }
    return solution, public
end

function validate.fishing(session, attempt)
    assert(type(attempt) == "table" and type(attempt.reels) == "table", "malformed fishing attempt.")

    local solution = session.solution
    local reelCount = denseArrayLength(attempt.reels, "fishing reels", #solution.targets, #solution.targets)
    assert(reelCount == #solution.targets, "fishing attempt must reel every bite exactly once.")

    local floor = Config.minigames.fishing.minReelInterval
    local lastElapsed = -floor
    for i = 1, reelCount do
        local reel = attempt.reels[i]
        assert(type(reel) == "table" and isInteger(reel.index), "malformed fishing reel.")
        assert(reel.index == i, "fishing bites must be reeled in order.")
        assertElapsed(reel.elapsed, session.timeLimit, "fishing reel")
        assert(reel.elapsed >= lastElapsed + floor, "fishing reels are too close together to be human.")

        local position = QB.minigames.triangleWave(reel.elapsed, solution.speed)
        if math.abs(position - solution.targets[i]) > solution.zoneSize / 2 then return false end
        lastElapsed = reel.elapsed
    end

    return true
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
    local digitCount = denseArrayLength(attempt.digits, "pinpad digits", #solution.digits, #solution.digits)
    assert(digitCount == #solution.digits, "pinpad attempt must submit every digit exactly once.")

    local floor = Config.minigames.pinpad.minTimePerDigit
    local lastElapsed = -floor
    local allMatch = true

    for i = 1, digitCount do
        local entry = attempt.digits[i]
        assert(type(entry) == "table" and isInteger(entry.value) and entry.value >= 0 and entry.value <= 9,
            "malformed pinpad digit.")
        assertElapsed(entry.elapsed, session.timeLimit, "pinpad digit")
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
    for i = 1, #cfg.questions do
        local q = cfg.questions[i]
        publicQuestions[i] = { numb = i, question = q.question, options = q.options }
    end

    local solution = { questions = cfg.questions, correctRequired = cfg.correctRequired }
    local public = { questions = publicQuestions, correctRequired = cfg.correctRequired, timePerQuestion = cfg.timePerQuestion }

    return solution, public
end

function validate.quiz(session, attempt)
    assert(type(attempt) == "table" and type(attempt.answers) == "table", "malformed quiz attempt.")

    local solution = session.solution
    local answerCount = denseArrayLength(attempt.answers, "quiz answers", #solution.questions, #solution.questions)
    assert(answerCount == #solution.questions, "quiz attempt must answer every question exactly once.")

    local floor = Config.minigames.quiz.minTimePerAnswer
    local lastElapsed = -floor
    local correct = 0

    for i = 1, answerCount do
        local entry = attempt.answers[i]
        assert(type(entry) == "table" and type(entry.choice) == "string", "malformed quiz answer.")
        boundedString(entry.choice, "quiz answer choice", Config.minigames.inputLimits.quizOptionBytes, true)
        assertElapsed(entry.elapsed, session.timeLimit, "quiz answer")
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
    local guessCount = denseArrayLength(attempt.guesses, "wordguess guesses", 26, 0)
    local floor = Config.minigames.wordguess.minTimePerGuess
    local lastElapsed = -floor
    local wrong = {}
    local found = {}
    for i = 1, #solution.word do found[i] = false end

    for i = 1, guessCount do
        local g = attempt.guesses[i]
        assert(type(g) == "table" and type(g.letter) == "string" and #g.letter == 1 and
            g.letter:match("^[A-Za-z]$") ~= nil,
            "malformed wordguess letter.")
        assertElapsed(g.elapsed, session.timeLimit, "wordguess letter")
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
    assert(type(attempt) == "table" and type(attempt.guess) == "string",
        "malformed wordscramble attempt.")
    boundedString(attempt.guess, "wordscramble guess", Config.minigames.inputLimits.wordScrambleBytes, true)
    assertElapsed(attempt.elapsed, session.timeLimit, "wordscramble submit")
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
    denseArrayLength(attempt.presses, "keys presses", #solution.pattern, 0)
    local floor = Config.minigames.keys.minTimePerPress
    local lastElapsed = -floor
    local faults = 0

    for i = 1, #solution.pattern do
        local key = solution.pattern[i]
        local press = attempt.presses[i]
        if press == nil or type(press) ~= "table" or type(press.key) ~= "string" or
            #press.key == 0 or #press.key > 5 or not isFiniteNumber(press.elapsed) then
            faults = faults + 1
        else
            assertElapsed(press.elapsed, session.timeLimit, "keys press")
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
    assert(type(attempt) == "table" and type(attempt.submitted) == "string",
        "malformed hacking attempt.")
    boundedString(attempt.submitted, "hacking submission", 10, true)
    assertElapsed(attempt.elapsed, session.timeLimit, "hacking submit")
    assert(attempt.elapsed >= Config.minigames.hacking.minTimePerFind, "hacking submitted too fast to be human.")

    return attempt.submitted == session.solution.code
end

------------------------------------------------------------------------------
-- Session lifecycle
------------------------------------------------------------------------------

endSession = function(session)
    if session.ended then return end
    session.ended = true

    sessions[session.id] = nil
    if session.authorization then authorizedSessionOwnership.untrack(session.id) end

    local count = sessionCountBySrc[session.src]
    if count then
        sessionCountBySrc[session.src] = count - 1
        if sessionCountBySrc[session.src] <= 0 then sessionCountBySrc[session.src] = nil end
    end
end

-- Legacy sessions are player-owned. Authorized sessions additionally retain
-- the issuing server resource as owner, so stopping that resource invalidates
-- pending authorizations, live authorized sessions, and unconsumed proofs.
AddEventHandler("playerDropped", function()
    local src = source
    for _, session in pairs(sessions) do
        if session.src == src then endSession(session) end
    end
    for token, authorization in pairs(authorizations) do
        if authorization.src == src then removeAuthorization(token) end
    end
    for token, proof in pairs(proofs) do
        if proof.src == src then removeProof(token) end
    end
end)

-- Backstop for a session nobody ever submits against again (the owning
-- client gave up, crashed, or the calling resource stopped without the
-- player disconnecting) -- expiresAt is already checked on every submit, but
-- without this an abandoned session would otherwise sit in `sessions`
-- forever. 30s is coarse on purpose: this only needs to reclaim memory
-- eventually, not the moment a session goes stale.
local function hasExpiringState()
    return next(sessions) ~= nil or next(authorizations) ~= nil or next(proofs) ~= nil
end

ensureExpirySweep = function()
    if expirySweepRunning then return end
    expirySweepRunning = true

    CreateThread(function()
        while true do
            Wait(30000)

            local now = GetGameTimer()
            for _, session in pairs(sessions) do
                if now > session.expiresAt then endSession(session) end
            end
            for token, authorization in pairs(authorizations) do
                if now > authorization.expiresAt then removeAuthorization(token) end
            end
            for token, proof in pairs(proofs) do
                if now > proof.expiresAt then removeProof(token) end
            end

            if not hasExpiringState() then break end
        end

        expirySweepRunning = false
    end)
end

QB.callback.register("qblib:minigames:start", function(src, gameType, opts, authorizationToken)
    assert(type(gameType) == "string" and QB.minigames.GAME_TYPES[gameType], "invalid minigame type.")

    -- A coarse sweep may not have run since a player's last abandoned round.
    -- Reclaim that player's expired session synchronously before enforcing the
    -- concurrency ceiling so a valid retry is never rejected by stale state.
    local current = GetGameTimer()
    for _, session in pairs(sessions) do
        if session.src == src and current > session.expiresAt then endSession(session) end
    end
    local activeCount = sessionCountBySrc[src] or 0
    if activeCount >= Config.minigames.maxConcurrentPerPlayer then
        error("A minigame is already in progress for this player.")
    end

    local authorization
    local cfg
    if authorizationToken ~= nil then
        assert(type(authorizationToken) == "string", "minigame authorization must be a string.")
        authorization = authorizations[authorizationToken]
        assert(authorization ~= nil, "Invalid or already-used minigame authorization.")
        if authorization.expiresAt < GetGameTimer() then
            removeAuthorization(authorizationToken)
            error("Minigame authorization expired.")
        end
        assert(authorization.src == src and authorization.gameType == gameType,
            "Minigame authorization does not match this player and game type.")
        cfg = authorization.cfg
    else
        assert(opts == nil or type(opts) == "table", "minigame opts must be a table.")
        cfg = resolveConfig[gameType](opts)
    end

    local solution, public = generate[gameType](cfg)

    nextSessionId = nextSessionId + 1
    local sessionId = nextSessionId
    ensureExpirySweep()
    local now = GetGameTimer()
    -- `sessionTTL` remains the minimum abandoned-round lifetime. A legitimate
    -- long round (or a later retry) receives its own bounded window, while the
    -- absolute cap prevents repeated retries from keeping a session alive
    -- forever.
    local overallExpiresAt = now + Config.minigames.sessionTTL
        + (cfg.timeLimit + Config.minigames.roundTimeoutBuffer) * cfg.attempts

    -- Consume only once every check and generation step has succeeded. A
    -- mismatched request cannot burn another player's valid authorization.
    if authorization then removeAuthorization(authorizationToken) end

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
        overallExpiresAt = overallExpiresAt,
        expiresAt = roundExpiry(now, cfg, overallExpiresAt),
        authorization = authorizationToken,
        issuer = authorization and authorization.issuer or nil,
        ended = false,
    }
    sessionCountBySrc[src] = activeCount + 1
    if authorization then authorizedSessionOwnership.track(authorization.issuer, sessionId) end

    return { sessionId = sessionId, attempt = 1, attempts = cfg.attempts, timeLimit = cfg.timeLimit, public = public }
end, { rateLimit = Config.minigames.callbackRateLimits.start })

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
    session.expiresAt = roundExpiry(GetGameTimer(), session.cfg, session.overallExpiresAt)

    return {
        done = false,
        sessionId = sessionId,
        attempt = session.attemptsUsed + 1,
        attempts = session.maxAttempts,
        timeLimit = session.timeLimit,
        public = public,
    }
end, { rateLimit = Config.minigames.callbackRateLimits.submit })

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
end, { rateLimit = Config.minigames.callbackRateLimits.cancel })
