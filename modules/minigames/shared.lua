-- Shared set for validating minigame type strings. A table, not a function, so build/finalise.lua's export walk skips it.
Kora.minigames.GAME_TYPES = {
    lockpick = true,
    skillbar = true,
    circuit = true,
    mash = true,
    fishing = true,
    pinpad = true,
    quiz = true,
    wordguess = true,
    wordscramble = true,
    keys = true,
    hacking = true,
}

---Deterministic triangle-wave motion the lockpick/skillbar puzzles animate by.
---Attached to Kora.minigames because the server recomputes the client's rendered position from elapsed time, so both must agree.
---@param elapsedMs number Milliseconds since the round started.
---@param speedHz number Full back-and-forth cycles per second.
---@return number position 0..1
function Kora.minigames.triangleWave(elapsedMs, speedHz)
    local phase = (elapsedMs / 1000 * speedHz) % 1
    return phase < 0.5 and phase * 2 or 2 - phase * 2
end
