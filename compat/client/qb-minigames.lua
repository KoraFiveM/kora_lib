-- Drop-in compatibility bridge: translates the real, public qb-minigames API
-- (github.com/qbcore-fivem/qb-minigames -- exports['qb-minigames']:Hacking/
-- KeyMinigame/Lockpick/StartPinpad/Quiz/Skillbar/WordGuess/WordScramble) onto
-- Kora.minigames.play, kora_lib's own server-authoritative replacement. Unlike
-- upstream (pure client-trust: the NUI itself decides pass/fail and just
-- posts the result), every call here is validated server-side -- see
-- modules/minigames/AGENTS.md and this file's "Divergences" note below for
-- the two spots where that changes what a caller gets back. Same shape of
-- shim as compat/client/qb-menu.lua/qb-input.lua/qb-radialmenu.lua.
--
-- See modules/minigames/docs.md's "Legacy compat" section for the full
-- export-by-export mapping table and the caveats flagged below.

-- Kora.compat.provideExport registers the hidden CFX export event under the
-- legacy `qb-minigames` identity; `provide 'qb-minigames'` alone only
-- satisfies dependency checks.

-- Kora.minigames.play rejects/errors (never returns a plain falsy value) when
-- a minigame is already in progress, gameType is invalid, or the round trip
-- fails outright -- upstream has no equivalent failure mode (its exports
-- always resolve). pcall here so a caller written only against upstream's
-- "always get a result" contract doesn't crash on the one new failure path;
-- treated the same as a losing round. Kora.minigames.play already awaits for an
-- external compatibility-export caller, while an in-resource caller receives
-- its promise directly. Capture that context before the operation can yield.
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

-- Divergence: upstream's Lockpick(pins) is a different mechanic (a
-- standalone tumbler minigame whose `pins` argument its own README calls
-- "number of tries") from kora_lib's pin-target-on-a-triangle-wave lockpick.
-- Rather than build a second, upstream-faithful lockpick alongside kora_lib's
-- existing one, `pins` is mapped onto pinCount -- close enough in spirit
-- (more pins = harder) without claiming pixel/mechanic parity.
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

-- Divergence: upstream's Skillbar(difficulty, validKeys) is a key-sequence
-- minigame -- `validKeys` (e.g. "wasdfgh") has no analogue in kora_lib's
-- existing triangle-wave skillbar, so it's dropped rather than guessed at,
-- same "drop what can't be faithfully translated, warn once" precedent
-- compat/client/qb-menu.lua's imageFor sets for icons it can't map.
-- `difficulty` is translated into a zoneSize (smaller = harder), the closest
-- kora_lib equivalent to upstream's easy/medium/hard levels.
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
