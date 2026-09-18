-- Every place that validates a minigame type string shares this set, rather
-- than each repeating its own "lockpick or skillbar or circuit or mash"
-- chain. A plain table, not a function, so build/finalise.lua's `pairs(QB.minigames)`
-- export walk (which only exports function values) leaves it alone.
QB.minigames.GAME_TYPES = {
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

---Deterministic back-and-forth motion every lockpick/skillbar puzzle animates
---by. Attached to QB.minigames (not left as a shared.lua local) because
---client.lua and server.lua are separate Lua chunks within the same realm --
---this is the one piece of game logic both genuinely need, since the server
---validates a submitted attempt by independently recomputing the exact
---position the client was rendering at a given elapsed time. The two must
---never drift out of sync with each other, which is also why this is a plain,
---cheap formula rather than anything stateful: same reasoning
---modules/loops/shared.lua's QB.loops.controlled is attached to QB rather
---than kept as a shared.lua local.
---
---A triangle wave, not a sine: constant angular velocity reads as perfectly
---linear back-and-forth motion, which is both easy for a player to judge by
---eye and trivial to recompute server-side from nothing but elapsed time.
---@param elapsedMs number Milliseconds since the round started.
---@param speedHz number Full back-and-forth cycles per second.
---@return number position 0..1
function QB.minigames.triangleWave(elapsedMs, speedHz)
    local phase = (elapsedMs / 1000 * speedHz) % 1
    return phase < 0.5 and phase * 2 or 2 - phase * 2
end
