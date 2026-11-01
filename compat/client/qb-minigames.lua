-- Compat bridge: translates exports['qb-minigames'] (Hacking/KeyMinigame/Lockpick/StartPinpad/Quiz/Skillbar/
-- WordGuess/WordScramble) onto Kora.minigames.play. Unlike upstream's client-trust model every call is
-- validated server-side; see the "Divergences" notes below and modules/minigames/docs.md "Legacy compat".

-- Registers the hidden CFX export event under the legacy `qb-minigames` identity; `provide` alone only satisfies dependency checks.

-- Kora.minigames.play errors (never returns plain falsy) on an in-progress game, bad gameType or a failed
-- round trip; upstream always resolves, so pcall and treat failure as a losing round. Capture the invoking
-- context before anything can yield (play already awaits for external export callers).
local function playSafely(gameType, opts)
    local calledFromExport = GetInvokingResource() ~= nil
    local ok, result = pcall(function()
        local response = Kora.minigames.play(gameType, opts)
        if not calledFromExport then return Citizen.Await(response) end
        return response
    end)
    if not ok then return { success = false, cancelled = true, attempts = 0 } end
    return result
end

local warnedSkillbarKeys = false

local function playHacking(solutionsize, timeout)
    local result = playSafely('hacking', { solutionsize = solutionsize, timeout = timeout })
    return result.success
end

local function playKeyMinigame(amount)
    local result = playSafely('keys', { amount = amount })
    return { quit = result.cancelled or false, faults = result.faults or 0 }
end

-- Divergence: upstream's Lockpick(pins) is a different tumbler mechanic (`pins` = number of tries);
-- it is mapped onto pinCount (more pins = harder) without claiming mechanic parity.
local function playLockpick(pins)
    local result = playSafely('lockpick', { pinCount = pins })
    return result.success
end

local function startPinpad(numbers)
    local result = playSafely('pinpad', { numbers = numbers })
    return { quit = result.cancelled or false, correct = result.success }
end

local function playQuiz(questions, correctRequired, timer)
    local result = playSafely('quiz', { questions = questions, correctRequired = correctRequired, timer = timer })
    return result.success
end

-- Divergence: upstream's Skillbar(difficulty, validKeys) is a key-sequence game; `validKeys` has no analogue
-- in kora_lib's triangle-wave skillbar and is dropped (warned once). `difficulty` maps to zoneSize (smaller = harder).
local SKILLBAR_ZONE_SIZE = { easy = 0.20, medium = 0.14, hard = 0.08 }

local function playSkillbar(difficulty, validKeys)
    if validKeys ~= nil and not warnedSkillbarKeys then
        warnedSkillbarKeys = true
        print("^3[qb-minigames compat]^7 Skillbar's validKeys has no equivalent in kora_lib's skillbar minigame -- ignored.")
    end

    local zoneSize = SKILLBAR_ZONE_SIZE[difficulty] or SKILLBAR_ZONE_SIZE.easy
    local result = playSafely('skillbar', { zoneSize = zoneSize })
    return result.success
end

local function playWordGuess(word, hint, guesses)
    local result = playSafely('wordguess', { word = word, hint = hint, guesses = guesses })
    return result.success
end

local function playWordScramble(word, hint, timer)
    local result = playSafely('wordscramble', { word = word, hint = hint, timer = timer })
    return result.success
end

Kora.compat.provideExport("qb-minigames", "Hacking", playHacking)
Kora.compat.provideExport("qb-minigames", "KeyMinigame", playKeyMinigame)
Kora.compat.provideExport("qb-minigames", "Lockpick", playLockpick)
Kora.compat.provideExport("qb-minigames", "StartPinpad", startPinpad)
Kora.compat.provideExport("qb-minigames", "Quiz", playQuiz)
Kora.compat.provideExport("qb-minigames", "Skillbar", playSkillbar)
Kora.compat.provideExport("qb-minigames", "WordGuess", playWordGuess)
Kora.compat.provideExport("qb-minigames", "WordScramble", playWordScramble)
