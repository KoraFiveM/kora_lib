-- Only one minigame can be on screen for this player at a time -- a second
-- concurrent QB.minigames.play() call is rejected immediately rather than
-- queued or allowed to stack overlays, same as modules/zones' single
-- creatorState guard.
local activeSession = nil
local activeRoundRequest
local nextSessionToken = 0

local function newSessionToken()
    nextSessionToken = nextSessionToken + 1
    return nextSessionToken
end

-- Ownership tracking here is about the LOCAL overlay/focus, not the server
-- session (the server can't infer a resource owner from this later client
-- callback; authorized sessions inherit the issuer captured earlier by
-- authorizeProof, while legacy sessions remain player-scoped). If the
-- resource that called QB.minigames.play() stops mid-round, the coroutine
-- driving beginPlay below is simply abandoned (there's no way to force a
-- suspended Citizen.Await to unwind) -- this registry's onDispose is
-- best-effort visual cleanup: drop the guard so a new session can start and
-- close the overlay so it isn't left on screen for an operation nothing is
-- driving anymore. QB.nui owns and releases this session's focus lease and
-- pending request through the same resource-stop event. The abandoned coroutine
-- still terminates on its own once its
-- pending promise settles or times out (every QB.callback.trigger and the
-- round's QB.nui.request both have finite timeouts), it just has no one left
-- to report its result to.
local minigameOwnership = QB.resources.registry(function(token)
    if activeSession == token then
        if activeRoundRequest then
            QB.nui.cancelRequest(activeRoundRequest, { cancelled = true })
            activeRoundRequest = nil
        end
        activeSession = nil
        QB.nui.send("minigames:close", { result = "cancelled" })
    end
end)

local function beginPlay(gameType, opts, authorization, resource)
    local token = newSessionToken()
    activeSession = token
    minigameOwnership.track(resource, token)

    local p = promise.new()
    local serverSessionId

    CreateThread(function()
        local ok, result = pcall(function()
            return QB.nui.withFocus(true, true, function()
                local round = Citizen.Await(QB.callback.trigger("qblib:minigames:start", gameType, opts, authorization))
                serverSessionId = round.sessionId
                local lastResult = nil

                while true do
                    -- The round's own timeLimit bounds how long a human gets to
                    -- act; roundTimeoutBuffer widens that only enough to absorb
                    -- latency/an abandoned overlay -- the NUI is expected to
                    -- auto-submit well before this fires on its own clock (see
                    -- this module's docs.md), so it's a safety net, not the
                    -- real pacing mechanism.
                    local roundRequest = QB.nui.requestAsync("minigames:round", {
                        type = gameType,
                        sessionId = round.sessionId,
                        attempt = round.attempt,
                        attempts = round.attempts,
                        timeLimit = round.timeLimit,
                        lastResult = lastResult,
                        puzzle = round.public,
                    }, round.timeLimit + Config.minigames.roundTimeoutBuffer, resource)
                    if activeSession == token then activeRoundRequest = roundRequest end
                    local attempt = Citizen.Await(roundRequest)
                    if activeRoundRequest == roundRequest then activeRoundRequest = nil end

                    -- Player pressed Escape (every minigame's Dialog resolves
                    -- {cancelled = true} on Escape/backdrop, same vocabulary
                    -- modules/nui's own menus use) -- distinct from a round
                    -- simply timing out (attempt == nil), which still submits
                    -- as a normal failed attempt below. Ends the server
                    -- session immediately rather than waiting on its TTL, and
                    -- doesn't consume an attempt.
                    if attempt ~= nil and attempt.cancelled then
                        Citizen.Await(QB.callback.trigger("qblib:minigames:cancel", round.sessionId))
                        serverSessionId = nil
                        return { success = false, cancelled = true, attempts = round.attempt - 1 }
                    end

                    local submitResult = Citizen.Await(QB.callback.trigger("qblib:minigames:submit", round.sessionId, attempt))

                    if submitResult.done then
                        serverSessionId = nil
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
            end, resource)
        end)

        minigameOwnership.untrack(token)
        if activeSession == token then
            activeSession = nil
            activeRoundRequest = nil
        end

        if not ok then
            if serverSessionId then
                -- The server successfully opened a session but a later NUI
                -- or callback request failed. Best-effort cancel it now so an
                -- immediate retry is not blocked until the expiry sweep.
                pcall(function()
                    Citizen.Await(QB.callback.trigger("qblib:minigames:cancel", serverSessionId))
                end)
                serverSessionId = nil
            end
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
---mash, fishing, pinpad, quiz, wordguess, wordscramble, keys, or hacking -- against
---the server, which independently generates and validates every round (see
---modules/minigames/server.lua and this module's AGENTS.md). The client only
---ever renders the puzzle and reports raw input timestamps/selections (and,
---for circuit, which nodes were connected); it never computes or reports a
---pass/fail itself, so the result can't be forged by a modified client beyond
---the basic timestamp-plausibility floor documented in AGENTS.md.
---@param gameType "lockpick" | "skillbar" | "circuit" | "mash" | "fishing" | "pinpad" | "quiz" | "wordguess" | "wordscramble" | "keys" | "hacking"
---@param opts? table Per-type overrides merged over Config.minigames.<type> and clamped/validated server-side -- see docs.md for the accepted fields per type. For pinpad/quiz/wordguess/wordscramble, opts also carries the puzzle's actual CONTENT (numbers/questions/word), since the caller supplies it rather than the server randomizing it.
---@param authorization? string Opaque token returned by the gameplay resource's server-side QB.minigames.authorizeProof call. When present, the server ignores opts and uses the trusted options captured by that authorization. Successful unauthorized legacy sessions remain proof-less.
---@return QBMinigameResult result The resolved result; this public function waits for the round to finish.
---(`attempts` = how many tries it took before success/exhaustion/cancellation; faults is only ever present for
---"keys", see server.lua's validate.keys). Callers do not need to wrap this function in Citizen.Await. `cancelled` is present (and `success` false)
---when the player backed out via Escape/backdrop instead of exhausting their attempts or the round trip
---failing outright -- see docs.md's "Cancelling" note. Rejects/errors if a minigame is already in progress for
---this player (checked both here and, in case a modified client skips this, server-side), gameType is
---invalid, or the underlying NUI/callback round trip fails.
function QB.minigames.play(gameType, opts, authorization, owner)
    return Citizen.Await(QB.minigames.playAsync(gameType, opts, authorization,
        owner or GetInvokingResource() or GetCurrentResourceName()))
end

---Starts a minigame without awaiting through an enclosing export call. This is
---used by compatibility providers that must retain a handle for cancellation.
---@param gameType string
---@param opts? table
---@param authorization? string
---@param owner? string
---@return promise result
function QB.minigames.playAsync(gameType, opts, authorization, owner)
    assert(QB.minigames.GAME_TYPES[gameType], "invalid minigame type -- see QB.minigames.GAME_TYPES.")
    assert(opts == nil or type(opts) == "table", "minigame opts must be a table.")
    assert(authorization == nil or type(authorization) == "string", "minigame authorization must be a string.")
    assert(owner == nil or (type(owner) == 'string' and owner ~= ''), 'minigame owner must be a non-empty string.')

    if activeSession then
        local p = promise.new()
        p:reject("A minigame is already in progress.")
        return p
    end

    -- Captured now, synchronously, while GetInvokingResource() still reflects
    -- the caller that reached across the exports boundary -- see
    -- modules/zones/client.lua's startCreator for the same reasoning.
    local resource = owner or GetInvokingResource() or GetCurrentResourceName()

    return beginPlay(gameType, opts, authorization, resource)
end

---Cancels the active minigame through the same result path as player Escape.
---@return boolean cancelled
function QB.minigames.cancel()
    if not activeSession or not activeRoundRequest then return false end
    local request = activeRoundRequest
    activeRoundRequest = nil
    return QB.nui.cancelRequest(request, { cancelled = true })
end

---Plays a minigame whose optional difficulty adjustment comes from qbskills.
---Without qbskills, this is exactly the same as play(gameType, opts,
---authorization). An authorization issued by authorizeSkillCheck is still the
---only safe path for an action with a server-side reward or consequence.
---@param skill string
---@param gameType "lockpick" | "skillbar" | "circuit" | "mash" | "pinpad" | "quiz" | "wordguess" | "wordscramble" | "keys" | "hacking"
---@param opts? table
---@param authorization? string
---@return QBMinigameResult result
function QB.minigames.playSkillCheck(skill, gameType, opts, authorization)
    assert(type(skill) == 'string' and skill ~= '', 'skill must be a non-empty string.')
    assert(QB.minigames.GAME_TYPES[gameType], 'invalid minigame type -- see QB.minigames.GAME_TYPES.')
    assert(opts == nil or type(opts) == 'table', 'minigame opts must be a table.')

    local adjusted = QB.skills.adjustMinigame(skill, gameType, opts)
    return QB.minigames.play(gameType, adjusted, authorization)
end
