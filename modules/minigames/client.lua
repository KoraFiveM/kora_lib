-- A promise object doesn't survive crossing a real cross-resource exports()
-- call back to the caller: only METHOD CALLS on it reach the real promise
-- inside qblib, while plain field reads (.state, .value -- what Citizen.Await
-- itself checks) on the crossed reference never reflect the real remote
-- promise's settlement, so the caller's own Citizen.Await silently resolves
-- nil regardless of the real outcome. GetInvokingResource() is nil for a
-- same-VM call (qblib's own modules, every dofile()'d smoke test) and the
-- real calling resource's name for a genuine cross-resource exports() call --
-- exactly the distinction that matters here. Same-VM callers get the real
-- promise back unchanged. A genuine cross-resource caller gets the
-- already-awaited plain value (or a raised error on rejection, which -- like
-- every other qblib error -- surfaces to that caller as a printed
-- export-call error and a nil return, not a catchable Lua error) instead of
-- a promise it can't usefully await. Deliberately duplicated per-file -- see
-- local/callback/{client,server}.lua, local/events/{client,server}.lua, and
-- modules/{cache,zones,nui}/client.lua for the other copies.
local function settleForExport(p)
    if GetInvokingResource() then
        return Citizen.Await(p)
    end
    return p
end

-- Only one minigame can be on screen for this player at a time -- a second
-- concurrent QB.minigames.play() call is rejected immediately rather than
-- queued or allowed to stack overlays, same as modules/zones' single
-- creatorState guard.
local activeSession = nil
local nextSessionToken = 0

local function newSessionToken()
    nextSessionToken = nextSessionToken + 1
    return nextSessionToken
end

-- Ownership tracking here is about the LOCAL overlay/focus, not the server
-- session (the server can't rely on GetInvokingResource() -- see this
-- module's AGENTS.md "Server session ownership" note for why that half is
-- tracked by player instead, via playerDropped in server.lua). If the
-- resource that called QB.minigames.play() stops mid-round, the coroutine
-- driving beginPlay below is simply abandoned (there's no way to force a
-- suspended Citizen.Await to unwind) -- this registry's onDispose is
-- best-effort visual cleanup: drop the guard so a new session can start,
-- release focus so the player isn't left mouse-locked, and close the
-- overlay so it isn't left on screen for an operation nothing is driving
-- anymore. The abandoned coroutine still terminates on its own once its
-- pending promise settles or times out (every QB.callback.trigger and the
-- round's QB.nui.request both have finite timeouts), it just has no one left
-- to report its result to.
local minigameOwnership = QB.resources.registry(function(token)
    if activeSession == token then
        activeSession = nil
        SetNuiFocus(false, false)
        QB.nui.send("minigames:close", { result = "cancelled" })
    end
end)

local function beginPlay(gameType, opts, resource)
    local token = newSessionToken()
    activeSession = token
    minigameOwnership.track(resource, token)

    local p = promise.new()

    CreateThread(function()
        local ok, result = pcall(function()
            return QB.nui.withFocus(true, true, function()
                local round = Citizen.Await(QB.callback.trigger("qblib:minigames:start", gameType, opts))
                local lastResult = nil

                while true do
                    -- The round's own timeLimit bounds how long a human gets to
                    -- act; roundTimeoutBuffer widens that only enough to absorb
                    -- latency/an abandoned overlay -- the NUI is expected to
                    -- auto-submit well before this fires on its own clock (see
                    -- this module's docs.md), so it's a safety net, not the
                    -- real pacing mechanism.
                    local attempt = Citizen.Await(QB.nui.request("minigames:round", {
                        type = gameType,
                        sessionId = round.sessionId,
                        attempt = round.attempt,
                        attempts = round.attempts,
                        timeLimit = round.timeLimit,
                        lastResult = lastResult,
                        puzzle = round.public,
                    }, round.timeLimit + Config.minigames.roundTimeoutBuffer))

                    -- Player pressed Escape (every minigame's Dialog resolves
                    -- {cancelled = true} on Escape/backdrop, same vocabulary
                    -- modules/nui's own menus use) -- distinct from a round
                    -- simply timing out (attempt == nil), which still submits
                    -- as a normal failed attempt below. Ends the server
                    -- session immediately rather than waiting on its TTL, and
                    -- doesn't consume an attempt.
                    if attempt ~= nil and attempt.cancelled then
                        Citizen.Await(QB.callback.trigger("qblib:minigames:cancel", round.sessionId))
                        return { success = false, cancelled = true, attempts = round.attempt - 1 }
                    end

                    local submitResult = Citizen.Await(QB.callback.trigger("qblib:minigames:submit", round.sessionId, attempt))

                    if submitResult.done then
                        -- `faults` is nil for every type except `keys`
                        -- (see server.lua's validate.keys) -- harmless to
                        -- always thread through, since a nil table field is
                        -- simply absent from the result.
                        return {
                            success = submitResult.success,
                            attempts = submitResult.attemptsUsed,
                            proof = submitResult.proof,
                            faults = submitResult.faults,
                        }
                    end

                    -- Anti-farming regeneration happened server-side (see
                    -- server.lua) -- the client just renders whatever fresh
                    -- round it's handed next, in the SAME overlay (no
                    -- re-mount/re-focus between attempts).
                    lastResult = "fail"
                    round = submitResult
                end
            end)
        end)

        minigameOwnership.untrack(token)
        if activeSession == token then activeSession = nil end

        if not ok then
            QB.nui.send("minigames:close", { result = "cancelled" })
            p:reject(result)
            return
        end

        local closeResult = "exhausted"
        if result.success then closeResult = "success" elseif result.cancelled then closeResult = "cancelled" end
        QB.nui.send("minigames:close", { result = closeResult })
        p:resolve(result)
    end)

    return p
end

---Plays one round-based minigame session -- lockpick, skillbar, circuit,
---mash, pinpad, quiz, wordguess, wordscramble, keys, or hacking -- against
---the server, which independently generates and validates every round (see
---modules/minigames/server.lua and this module's AGENTS.md). The client only
---ever renders the puzzle and reports raw input timestamps/selections (and,
---for circuit, which nodes were connected); it never computes or reports a
---pass/fail itself, so the result can't be forged by a modified client beyond
---the basic timestamp-plausibility floor documented in AGENTS.md.
---@param gameType "lockpick" | "skillbar" | "circuit" | "mash" | "pinpad" | "quiz" | "wordguess" | "wordscramble" | "keys" | "hacking"
---@param opts? table Per-type overrides merged over Config.minigames.<type> and clamped/validated server-side -- see docs.md for the accepted fields per type. For pinpad/quiz/wordguess/wordscramble, opts also carries the puzzle's actual CONTENT (numbers/questions/word), since the caller supplies it rather than the server randomizing it.
---@return promise|any result Resolves/returns { success: boolean, attempts: integer, cancelled?: true, faults?: integer }
---(attempts = how many tries it took before success/exhaustion/cancellation; faults is only ever present for
---"keys", see server.lua's validate.keys) for a same-VM caller (unchanged, awaitable as before) or a genuine
---cross-resource caller respectively (see settleForExport above). `cancelled` is present (and `success` false)
---when the player backed out via Escape/backdrop instead of exhausting their attempts or the round trip
---failing outright -- see docs.md's "Cancelling" note. Rejects/errors if a minigame is already in progress for
---this player (checked both here and, in case a modified client skips this, server-side), gameType is
---invalid, or the underlying NUI/callback round trip fails.
function QB.minigames.play(gameType, opts)
    assert(QB.minigames.GAME_TYPES[gameType], "invalid minigame type -- see QB.minigames.GAME_TYPES.")
    assert(opts == nil or type(opts) == "table", "minigame opts must be a table.")

    if activeSession then
        local p = promise.new()
        p:reject("A minigame is already in progress.")
        return settleForExport(p)
    end

    -- Captured now, synchronously, while GetInvokingResource() still reflects
    -- the caller that reached across the exports boundary -- see
    -- modules/zones/client.lua's startCreator for the same reasoning.
    local resource = GetInvokingResource() or GetCurrentResourceName()

    return settleForExport(beginPlay(gameType, opts, resource))
end
