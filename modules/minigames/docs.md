# Minigames

## Overview
The minigames module gives you ten server-validated skill-check minigames -- lockpick, skillbar, circuit, mash-key, pinpad, quiz, wordguess, wordscramble, keys, and hacking -- for gating gameplay actions where a purely client-side pass/fail could be bypassed by a modified client. The server generates every round's solution and validates every submitted attempt; the client only renders the puzzle and reports raw input. The last six types back `compat/client/qb-minigames.lua`, a drop-in shim for the real `github.com/qbcore-fivem/qb-minigames` resource -- see "Legacy compat" below.

## API

### `QB.minigames.play(gameType, opts)`
Plays one round-based minigame session, opening a full-screen overlay and blocking (via the returned promise) until the player succeeds, runs out of attempts, or the round trip fails.

#### Parameters
- `gameType: "lockpick" | "skillbar" | "circuit" | "mash" | "pinpad" | "quiz" | "wordguess" | "wordscramble" | "keys" | "hacking"`
- `opts?: table` -- per-type overrides, merged over `Config.minigames.<type>` and clamped/validated server-side (a modified client sending extreme values can't trivialize the puzzle). Accepted fields per type:
  - `lockpick`: `attempts`, `pinCount`, `tolerance`, `speed`, `timeLimit`
  - `skillbar`: `attempts`, `zoneSize`, `speed`, `timeLimit`
  - `circuit`: `attempts`, `nodeCount`, `timeLimit`
  - `mash`: `attempts`, `requiredPresses`, `timeLimit`
  - `pinpad`: `numbers` (the PIN, e.g. `1234`; digit count randomized from `digits` if omitted), `digits`, `attempts`, `timeLimit`
  - `quiz`: `questions` (required -- `{ question, answer, options }[]`), `correctRequired`, `timer` (seconds per question), `attempts`
  - `wordguess`: `word` (required), `hint`, `guesses`, `attempts`, `timeLimit`
  - `wordscramble`: `word` (required), `hint`, `timer` (seconds), `attempts`
  - `keys`: `amount` (number of arrow-key prompts; `attempts` is always 1 -- see below)
  - `hacking`: `solutionsize` (hex characters), `timeout` (seconds; `attempts` is always 1 -- see below)

  For `pinpad`/`quiz`/`wordguess`/`wordscramble`, `opts` is where the caller supplies the puzzle's actual content, exactly like the real qb-minigames exports -- the server never invents a PIN/word/quiz on its own for these.

#### Behavior
Opens NUI focus once and keeps the same overlay mounted for every attempt -- a failed attempt with tries remaining re-renders a **freshly generated** puzzle in place (anti-farming: the target can't be memorized and repeated), it doesn't close and reopen. Each round is individually time-limited (`timeLimit`, per type); the overlay is expected to auto-submit whatever partial input it has once that time is up, which counts as a failed attempt like any other. `keys` and `hacking` always run with `attempts = 1`, matching upstream's single-pass shape (KeyMinigame never retries; Hacking is a single pass/fail against a countdown).

#### Returns
- `promise|any result` -- resolves/returns `{ success: boolean, attempts: integer, cancelled?: true, faults?: integer }` (`attempts` = how many tries it took before success/exhaustion/cancellation) for a same-VM caller (unchanged, awaitable as before) or a genuine cross-resource caller respectively. `cancelled` is present (and `success` false) when the player backed out early -- see "Cancelling" below. `faults` is present only for `"keys"` -- see its note below. Rejects/errors if a minigame is already active for this player (checked client- and server-side), `gameType` is invalid, or the round trip fails outright.

#### `keys` always succeeds
Unlike every other type, `keys` never fails -- `success` is always `true` (unless cancelled). It mirrors upstream `KeyMinigame`, which has no pass/fail concept of its own; the result's `faults` field (how many prompts were missed or mistimed) is what the calling script checks, e.g. `if result.faults > 3 then ... end`.

## Cancelling
Every minigame's dialog closes on Escape or a backdrop click, same as `QB.nui.openMenu`/`openInputDialog`. Cancelling ends the round immediately -- it does **not** consume an attempt, and the server session is freed right away (not left to its `sessionTTL`), so the player can start a fresh `QB.minigames.play()` call right after cancelling instead of hitting "already in progress" until the old session would have expired. A round that instead simply runs out of `timeLimit` still auto-submits and counts as a normal failed attempt, exactly as before.

#### Example
```lua
RegisterCommand('lockpick_door', function()
    local result = Citizen.Await(QB.minigames.play("lockpick", { pinCount = 5, timeLimit = 10000 }))

    if result.success then
        print(("unlocked in %d attempt(s)"):format(result.attempts))
    else
        print("failed to pick the lock")
    end
end, false)
```

Called from another resource:
```lua
local result = exports.qblib:minigames_play("skillbar", { attempts = 1 })
if result.success then
    -- proceed
end
```

## Notes
- **This is a floor, not full anti-cheat.** The client never computes or reports a pass/fail, and for lockpick/skillbar never reports a position -- only *when* an input happened. The server independently recomputes correctness from a solution it never sends to the client, and rejects timestamps that are too close together or outside the round's time limit to be human. A sufficiently sophisticated modified client that fabricates *plausible* timestamps can still forge a pass -- pair this with server-side checks on whatever real action it gates (e.g. re-verify proximity/interaction) rather than trusting `success = true` alone for anything high-value.
- Only one `QB.minigames.play()` session can be active per player at a time; a second concurrent call rejects immediately rather than queuing.
- A server-side session expires after `Config.minigames.sessionTTL` (60s by default) if abandoned -- an expired session's next submit (if any) fails cleanly, and an unclaimed session is swept automatically even if the client never submits again.

## Supporting APIs

`QB.minigames.consumeProof(src, token, gameType)` is the server-side one-use
proof consumer for a successful result. It returns `true` once, then rejects
reuse, expiry, a player mismatch, or a game-type mismatch.

`QB.minigames.triangleWave(elapsedMs, speedHz)` is the shared deterministic
0–1 motion formula used by both the renderer and server validation.

## Legacy compat
`compat/client/qb-minigames.lua` keeps scripts written against the real `github.com/qbcore-fivem/qb-minigames` resource working unmodified via `provide 'qb-minigames'` plus the same `__cfx_export_` identity-hijack `compat/client/qb-menu.lua` uses. Mapping table:

| `exports['qb-minigames']:...` | Maps to | Notes |
|---|---|---|
| `Hacking(solutionsize, timeout)` | `play('hacking', { solutionsize, timeout })` | See `hacking`'s simplification note above |
| `KeyMinigame(amount)` | `play('keys', { amount })` | Returns `{ quit, faults }`, matching upstream exactly |
| `Lockpick(pins)` | `play('lockpick', { pinCount = pins })` | **Divergence** -- different mechanic than upstream's own lockpick, see below |
| `StartPinpad(numbers)` | `play('pinpad', { numbers })` | Returns `{ quit, correct }`, matching upstream exactly |
| `Quiz(questions, correctRequired, timer)` | `play('quiz', { questions, correctRequired, timer })` | Direct mapping |
| `Skillbar(difficulty, validKeys)` | `play('skillbar', { zoneSize = <from difficulty> })` | **Divergence** -- `validKeys` dropped, see below |
| `WordGuess(word, hint, guesses)` | `play('wordguess', { word, hint, guesses })` | Direct mapping |
| `WordScramble(word, hint, timer)` | `play('wordscramble', { word, hint, timer })` | Direct mapping |

Two documented divergences:
- **`Lockpick`**: upstream's `pins` argument (its own README calls it "number of tries") is mapped onto qblib's `pinCount` for a script that "just works", but it's a different minigame -- qblib's pin-target-on-a-triangle-wave lockpick, not upstream's own tumbler minigame.
- **`Skillbar`**: `validKeys` (e.g. `"wasdfgh"`) has no equivalent in qblib's triangle-wave skillbar and is silently dropped (one-time console warning); `difficulty` is translated into a `zoneSize` instead.

Every other export is a straight pass-through with no mechanic divergence -- the only behavioral difference from upstream is qblib's server-authoritative validation replacing upstream's client-trust model.
