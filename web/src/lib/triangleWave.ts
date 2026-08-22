/**
 * JS mirror of QB.minigames.triangleWave (modules/minigames/shared.lua) --
 * MUST stay byte-for-byte identical to that formula. The server independently
 * recomputes a submitted attempt's position from the exact same formula, so
 * this is purely for rendering the moving indicator; it is never sent back
 * to Lua (lockpick/skillbar attempts report only elapsed timestamps).
 */
export function triangleWave(elapsedMs: number, speedHz: number): number {
    const phase = ((elapsedMs / 1000) * speedHz) % 1
    return phase < 0.5 ? phase * 2 : 2 - phase * 2
}
