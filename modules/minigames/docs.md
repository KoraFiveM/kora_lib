# Minigames

## Overview
The minigames module gives you four server-validated skill-check minigames -- lockpick, skillbar, circuit, and mash-key -- for gating gameplay actions where a purely client-side pass/fail could be bypassed by a modified client. The server generates every round's solution and validates every submitted attempt; the client only renders the puzzle and reports raw input.

## API

### `QB.minigames.play(gameType, opts)`
Plays one round-based minigame session, opening a full-screen overlay and blocking (via the returned promise) until the player succeeds, runs out of attempts, or the round trip fails.

#### Parameters
- `gameType: "lockpick" | "skillbar" | "circuit" | "mash"`
- `opts?: table` -- per-type difficulty overrides, merged over `Config.minigames.<type>` and clamped server-side (a modified client sending extreme values can't trivialize the puzzle). Accepted fields per type:
  - `lockpick`: `attempts`, `pinCount`, `tolerance`, `speed`, `timeLimit`
  - `skillbar`: `attempts`, `zoneSize`, `speed`, `timeLimit`
  - `circuit`: `attempts`, `nodeCount`, `timeLimit`
  - `mash`: `attempts`, `requiredPresses`, `timeLimit`

#### Behavior
Opens NUI focus once and keeps the same overlay mounted for every attempt -- a failed attempt with tries remaining re-renders a **freshly generated** puzzle in place (anti-farming: the target can't be memorized and repeated), it doesn't close and reopen. Each round is individually time-limited (`timeLimit`, per type); the overlay is expected to auto-submit whatever partial input it has once that time is up, which counts as a failed attempt like any other.

#### Returns
- `promise|any result` -- resolves/returns `{ success: boolean, attempts: integer }` (`attempts` = how many tries it took) for a same-VM caller (unchanged, awaitable as before) or a genuine cross-resource caller respectively. Rejects/errors if a minigame is already active for this player (checked client- and server-side), `gameType` is invalid, or the round trip fails outright.

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
