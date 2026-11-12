---
title: "Minigames"
sidebar_position: 14
---

# Minigames

## Overview
The minigames module gives you eleven server-validated skill-check minigames -- lockpick, skillbar, circuit, mash-key, fishing, pinpad, quiz, wordguess, wordscramble, keys, and hacking. The server generates every round's solution and validates every submitted attempt; the client only renders the puzzle and reports bounded raw input. For a result that gates a real server action, use the authorization/proof flow below: ordinary and legacy client-only calls remain playable but deliberately cannot mint a server-consumable proof. The last six types back `compat/client/qb-minigames.lua`, a drop-in shim for the real `github.com/qbcore-fivem/qb-minigames` resource -- see "Legacy compat" below.

## API

### `Kora.minigames.play(gameType, opts, authorization)`
Plays one round-based minigame session, opening a full-screen overlay and waiting until the player succeeds, runs out of attempts, or the round trip fails. The public function returns the result directly; callers do not need `Citizen.Await`.

#### Parameters
- `gameType: "lockpick" | "skillbar" | "circuit" | "mash" | "fishing" | "pinpad" | "quiz" | "wordguess" | "wordscramble" | "keys" | "hacking"`
- `opts?: table` -- per-type overrides, merged over `Config.minigames.<type>` and clamped/validated server-side (a modified client sending extreme values can't trivialize the puzzle). Accepted fields per type:
  - `lockpick`: `attempts`, `pinCount`, `tolerance`, `speed`, `timeLimit`
  - `skillbar`: `attempts`, `zoneSize`, `speed`, `timeLimit`
  - `circuit`: `attempts`, `nodeCount`, `timeLimit`
  - `mash`: `attempts`, `requiredPresses`, `timeLimit`
  - `fishing`: `attempts`, `games` (1, 2, or 3), `zoneSize`, `speed` (`"easy"`, `"medium"`, or `"hard"`), `timeLimit`
  - `pinpad`: `numbers` (the PIN, e.g. `1234`; digit count randomized from `digits` if omitted), `digits`, `attempts`, `timeLimit`
  - `quiz`: `questions` (required -- `{ question, answer, options }[]`), `correctRequired`, `timer` (seconds per question), `attempts`
  - `wordguess`: `word` (required), `hint`, `guesses`, `attempts`, `timeLimit`
  - `wordscramble`: `word` (required), `hint`, `timer` (seconds), `attempts`
  - `keys`: `amount` (number of arrow-key prompts; `attempts` is always 1 -- see below)
  - `hacking`: `solutionsize` (hex characters), `timeout` (seconds; `attempts` is always 1 -- see below)

  For `pinpad`/`quiz`/`wordguess`/`wordscramble`, `opts` is where the caller supplies the puzzle's actual content, exactly like the real qb-minigames exports -- the server never invents a PIN/word/quiz on its own for these.

  `wordguess` currently keeps the solution server-side, so the browser cannot
  reveal correct letter positions as guesses are entered. It collects unique
  letters and submits them at the deadline for authoritative scoring; it is a
  secure word-attempt check, not full interactive Hangman parity.
- `authorization?: string` -- 32-character alphanumeric opaque value returned by the gameplay resource's server-side `Kora.minigames.authorizeProof`. When present and valid, the server uses the trusted options captured at authorization time and ignores this client's `opts` entirely. When absent, the legacy/client-configured session remains playable but proof-less.

#### Behavior
Opens NUI focus once and keeps the same overlay mounted for every attempt -- a failed attempt with tries remaining re-renders a **freshly generated** puzzle in place (anti-farming: the target can't be memorized and repeated), it doesn't close and reopen. Each round is individually time-limited (`timeLimit`, per type); the overlay is expected to auto-submit whatever partial input it has once that time is up, which counts as a failed attempt like any other. `keys` and `hacking` always run with `attempts = 1`, matching upstream's single-pass shape (KeyMinigame never retries; Hacking is a single pass/fail against a countdown).

Round expiry is scheduled against one exact browser deadline. Whole-second countdown labels update at a low cadence, while the lockpick and skillbar indicators alone animate at display refresh rate. This keeps input and animation responsive without re-rendering the entire overlay every frame.

#### Returns
- The function returns `{ success: boolean, attempts: integer, proof?: string, cancelled?: true, faults?: integer }` directly (`attempts` = how many tries it took before success/exhaustion/cancellation). `proof` is present only after a successful authorized session. `cancelled` is present (and `success` false) when the player backed out early -- see "Cancelling" below. `faults` is present only for `"keys"` -- see its note below. It rejects/errors if a minigame is already active for this player (checked client- and server-side), `gameType` is invalid, the authorization is invalid/expired/already used, or the round trip fails outright.

#### `keys` always succeeds
Unlike every other type, `keys` never fails -- `success` is always `true` (unless cancelled). It mirrors upstream `KeyMinigame`, which has no pass/fail concept of its own; the result's `faults` field (how many prompts were missed or mistimed) is what the calling script checks, e.g. `if result.faults > 3 then ... end`.

## Cancelling
Every minigame's dialog closes on Escape or a backdrop click, same as `Kora.nui.openMenu`/`openInputDialog`. Cancelling ends the round immediately -- it does **not** consume an attempt, and the server session is freed right away (not left to its `sessionTTL`), so the player can start a fresh `Kora.minigames.play()` call right after cancelling instead of hitting "already in progress" until the old session would have expired. A round that instead simply runs out of `timeLimit` still auto-submits and counts as a normal failed attempt, exactly as before.

#### Example
```lua
RegisterCommand('lockpick_door', function()
    local result = Kora.minigames.play("lockpick", { pinCount = 5, timeLimit = 10000 })

    if result.success then
        print(("unlocked in %d attempt(s)"):format(result.attempts))
    else
        print("failed to pick the lock")
    end
end, false)
```

Called from another resource:
```lua
local result = exports.kora_lib:minigames_play("skillbar", { attempts = 1 })
if result.success then
    -- proceed
end
```

`Kora.minigames.playAsync(gameType, opts, authorization, owner)` is the internal,
owner-aware composition form used by compatibility providers that need to
retain a cancellable promise. `Kora.minigames.cancel()` only settles a round
owned by its calling resource (or its explicit internal `owner` argument), so
one resource cannot cancel another resource's active check. Gameplay resources
should normally use `play`, which waits and returns the result directly.

## Notes
- **Proofs require server authorization.** A bare `play` call can still report UX success to its client caller, but it never returns a proof. A gameplay resource must issue an authorization first and later consume the matching proof on the server.
- **This is a floor, not full anti-cheat.** The client never computes or reports a pass/fail, and for lockpick/skillbar never reports a position -- only *when* an input happened. The server independently recomputes correctness from a solution it never sends to the client, and rejects timestamps that are too close together or outside the round's time limit to be human. A sufficiently sophisticated modified client that fabricates *plausible* timestamps can still pass -- authorization prevents it from choosing a weaker proof-producing configuration or minting a generic proof, but the consuming resource must still re-verify its own action state (proximity, item ownership, target identity, etc.).
- Only one `Kora.minigames.play()` session can be active per player at a time; a second concurrent call rejects immediately rather than queuing.
- Reported input timestamps cannot exceed the server's elapsed time for the current round, with a fixed 50 ms margin for clock quantization. Each retry starts a new server clock; time spent in previous rounds cannot justify future inputs.
- Each server-side round gets at least `Config.minigames.sessionTTL` (60s by default), or its configured `timeLimit` plus the timeout buffer when that is longer. The deadline refreshes for a retry but is capped by a bounded overall-session deadline, so valid long rounds work without letting repeated retries retain state forever. An expired session's next submit (if any) fails cleanly, and an unclaimed session is swept automatically even if the client never submits again.
- Numeric inputs must be finite. Attempt arrays must be dense and are capped to the expected round size. Puzzle content is byte/count bounded by `Config.minigames.inputLimits` (including at most 8 PIN digits, 20 quiz questions with 8 options each, 32-byte wordguess words, 64-byte scrambled words, and 256-byte hints). `wordguess` words are ASCII letters because its input protocol submits one ASCII letter at a time.
- The start/submit/cancel callbacks have per-player quotas in `Config.minigames.callbackRateLimits`; the defaults are 5/20/10 calls respectively per 10 seconds.

### Skill-aware checks (`kora_skills`, optional)

`Kora.minigames.playSkillCheck(skill, gameType, opts?, authorization?)` is the
client helper for a check whose difficulty may scale with a `kora_skills` level.
If `kora_skills` is not started it behaves exactly like `play`.

For an action that has real value, issue the authorization on the server with
`Kora.minigames.authorizeSkillCheck(src, skill, gameType, trustedOpts)`. kora_lib
first resolves the trusted options, then lets kora_skills adjust that resolved
configuration and captures the final result inside the authorization. The
client cannot replace it with easier options at start time.

```lua
-- server, after your own item/proximity/state checks
local authorization = Kora.minigames.authorizeSkillCheck(src, 'mining', 'skillbar', {
    zoneSize = 0.16,
    attempts = 1,
})

-- client
local result = Kora.minigames.playSkillCheck('mining', 'skillbar', nil, authorization)
```

## Supporting APIs

### Authorized proof flow

1. The gameplay resource calls `Kora.minigames.authorizeProof(src, gameType, trustedOpts)` on the **server**. This returns an opaque authorization owned by that invoking resource and valid for `Config.minigames.authorizationTTL`.
2. Send that authorization to the intended player through the resource's existing callback/event, and pass it as the third argument to `Kora.minigames.play` on the **client**. The authorization is consumed only after a matching player/type session starts. The client-supplied `opts` are ignored; `trustedOpts` determine the proof-producing round.
3. A successful authorized result includes `result.proof`. Send the proof and original authorization back as part of the gameplay resource's normal completion request.
4. The same gameplay resource calls `Kora.minigames.consumeProof(src, proof, gameType, authorization)` on the **server**. It returns `true` exactly once when issuer, player, game type, authorization, and TTL all match. A mismatch returns `false` without burning an otherwise valid proof; expiry removes it.

```lua
-- server (inside my-resource)
Kora.callback.register('my-resource:server:beginAction', function(src)
    -- Perform resource-specific proximity/item/target checks first.
    local actionToken = issueActionToken(src)
    local authorization = Kora.minigames.authorizeProof(src, 'mash', {
        requiredPresses = 20,
        timeLimit = 4000,
        attempts = 1,
    })
    return { actionToken = actionToken, authorization = authorization }
end)

RegisterNetEvent('my-resource:server:actionCompleted', function(actionToken, authorization, proof)
    local src = source
    if not validateActionToken(src, actionToken) then return end
    if not Kora.minigames.consumeProof(src, proof, 'mash', authorization) then return end
    -- Re-check live resource state, then perform the action.
end)

-- client
local begun = Kora.callback.trigger('my-resource:server:beginAction')
local result = Kora.minigames.play('mash', nil, begun.authorization)
TriggerServerEvent('my-resource:server:actionCompleted', begun.actionToken,
    begun.authorization, result.proof)
```

Authorizations are single-start capabilities. Failed or cancelled sessions do not return a proof and cannot reuse their authorization. Pending authorizations, live authorized sessions, and unconsumed proofs are removed when their issuing resource stops; all state is also removed when the player disconnects and by TTL sweeps.

`Kora.minigames.triangleWave(elapsedMs, speedHz)` is the shared deterministic
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
| `WordGuess(word, hint, guesses)` | `play('wordguess', { word, hint, guesses })` | Signature mapping; the server-private solution prevents progressive letter reveal and early completion. |
| `WordScramble(word, hint, timer)` | `play('wordscramble', { word, hint, timer })` | Direct mapping |

Three documented divergences:
- **`Lockpick`**: upstream's `pins` argument (its own README calls it "number of tries") is mapped onto kora_lib's `pinCount` for a script that "just works", but it's a different minigame -- kora_lib's pin-target-on-a-triangle-wave lockpick, not upstream's own tumbler minigame.
- **`Skillbar`**: `validKeys` (e.g. `"wasdfgh"`) has no equivalent in kora_lib's triangle-wave skillbar and is silently dropped (one-time console warning); `difficulty` is translated into a `zoneSize` instead.
- **`WordGuess`**: the browser never receives the solution, so it cannot reveal
  hits or distinguish a wrong guess while the round is live. It submits the
  collected unique letters when time expires and the server scores them.

The remaining exports are straight pass-throughs with no known mechanic divergence. Compat calls do not carry a server-issued authorization, so they remain usable for legacy UX but are proof-less and must not directly authorize a valuable server action.
