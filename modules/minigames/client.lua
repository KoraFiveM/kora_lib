-- Only one minigame per player at a time; a concurrent play() is rejected rather than queued.
local activeSession = nil
local activeRoundRequest
local nextSessionToken = 0

local function newSessionToken()
    nextSessionToken = nextSessionToken + 1
    return nextSessionToken
end

-- Tracks the LOCAL overlay/focus only; the server session owner is captured earlier by authorizeProof.
-- If the calling resource stops mid-round, the beginPlay coroutine is abandoned (a suspended Citizen.Await can't be unwound);
-- onDispose drops the guard and closes the overlay. The coroutine ends once its finite-timeout promises settle.
local minigameOwnership = Kora.resources.registry(function(token)
    if activeSession == token then
        if activeRoundRequest then
            Kora.nui.cancelRequest(activeRoundRequest, { cancelled = true })
            activeRoundRequest = nil
        end
        activeSession = nil
        Kora.nui.send("minigames:close", { result = "cancelled" })
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
            return Kora.nui.withFocus(true, true, function()
                local round = Citizen.Await(Kora.callback.trigger("kora_lib:minigames:start", gameType, opts, authorization))
                serverSessionId = round.sessionId
                local lastResult = nil

                while true do
                    -- roundTimeoutBuffer only absorbs latency/an abandoned overlay; the NUI auto-submits well before this safety net fires.
                    local roundRequest = Kora.nui.requestAsync("minigames:round", {
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

                    -- Escape/backdrop (cancelled = true), distinct from a timeout (attempt == nil) which submits as a failed attempt.
                    -- Ends the server session immediately and doesn't consume an attempt.
                    if attempt ~= nil and attempt.cancelled then
                        Citizen.Await(Kora.callback.trigger("kora_lib:minigames:cancel", round.sessionId))
                        serverSessionId = nil
                        return { success = false, cancelled = true, attempts = round.attempt - 1 }
                    end

                    local submitResult = Citizen.Await(Kora.callback.trigger("kora_lib:minigames:submit", round.sessionId, attempt))

                    if submitResult.done then
                        serverSessionId = nil
                        -- `faults` is nil except for `keys`.
                        return {
                            success = submitResult.success,
                            attempts = submitResult.attemptsUsed,
                            proof = submitResult.proof,
                            faults = submitResult.faults,
                        }
                    end

                    -- The server regenerated the round (anti-farming); render it in the same overlay.
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
                -- A later NUI/callback request failed; cancel the server session so an immediate retry isn't blocked.
                pcall(function()
                    Citizen.Await(Kora.callback.trigger("kora_lib:minigames:cancel", serverSessionId))
                end)
                serverSessionId = nil
            end
            Kora.nui.send("minigames:close", { result = "cancelled" })
            p:reject(result)
            return
        end

        local closeResult = "exhausted"
        if result.success then closeResult = "success" elseif result.cancelled then closeResult = "cancelled" end
        Kora.nui.send("minigames:close", { result = closeResult })
        p:resolve(result)
    end)

    return p
end

---Plays one round-based minigame session against the server, which generates and validates every round; the client only renders and reports raw input.
---@param gameType "lockpick" | "skillbar" | "circuit" | "mash" | "fishing" | "pinpad" | "quiz" | "wordguess" | "wordscramble" | "keys" | "hacking"
---@param opts? table Per-type overrides merged over Config.minigames.<type> and clamped/validated server-side -- see docs.md for the accepted fields per type. For pinpad/quiz/wordguess/wordscramble, opts also carries the puzzle's actual CONTENT (numbers/questions/word), since the caller supplies it rather than the server randomizing it.
---@param authorization? string Opaque token returned by the gameplay resource's server-side Kora.minigames.authorizeProof call. When present, the server ignores opts and uses the trusted options captured by that authorization. Successful unauthorized legacy sessions remain proof-less.
---@return QBMinigameResult result The resolved result; this public function waits for the round to finish.
---`cancelled` is set (and `success` false) when the player backed out; `faults` is only present for "keys". No Citizen.Await needed.
---Errors if a minigame is already in progress, gameType is invalid, or the NUI/callback round trip fails.
function Kora.minigames.play(gameType, opts, authorization, owner)
    return Citizen.Await(Kora.minigames.playAsync(gameType, opts, authorization,
        owner or GetInvokingResource() or GetCurrentResourceName()))
end

---Starts a minigame without awaiting through an enclosing export call. This is
---used by compatibility providers that must retain a handle for cancellation.
---@param gameType string
---@param opts? table
---@param authorization? string
---@param owner? string
---@return promise result
function Kora.minigames.playAsync(gameType, opts, authorization, owner)
    assert(Kora.minigames.GAME_TYPES[gameType], "invalid minigame type -- see Kora.minigames.GAME_TYPES.")
    assert(opts == nil or type(opts) == "table", "minigame opts must be a table.")
    assert(authorization == nil or type(authorization) == "string", "minigame authorization must be a string.")
    assert(owner == nil or (type(owner) == 'string' and owner ~= ''), 'minigame owner must be a non-empty string.')

    if activeSession then
        local p = promise.new()
        p:reject("A minigame is already in progress.")
        return p
    end

    -- Captured synchronously while GetInvokingResource() still reflects the exports caller (see modules/zones/client.lua startCreator).
    local resource = owner or GetInvokingResource() or GetCurrentResourceName()

    return beginPlay(gameType, opts, authorization, resource)
end

---Cancels the caller's active minigame through the same result path as player Escape.
---@param owner? string Internal owner override for compatibility providers.
---@return boolean cancelled
function Kora.minigames.cancel(owner)
    assert(owner == nil or (type(owner) == 'string' and owner ~= ''), 'minigame owner must be a non-empty string.')
    if not activeSession or not activeRoundRequest then return false end
    local resource = owner or GetInvokingResource() or GetCurrentResourceName()
    if minigameOwnership.owner(activeSession) ~= resource then return false end
    local request = activeRoundRequest
    activeRoundRequest = nil
    return Kora.nui.cancelRequest(request, { cancelled = true })
end

---Plays a minigame with an optional kora_skills difficulty adjustment; identical to play() without kora_skills.
---@param skill string
---@param gameType "lockpick" | "skillbar" | "circuit" | "mash" | "pinpad" | "quiz" | "wordguess" | "wordscramble" | "keys" | "hacking"
---@param opts? table
---@param authorization? string
---@return QBMinigameResult result
function Kora.minigames.playSkillCheck(skill, gameType, opts, authorization)
    assert(type(skill) == 'string' and skill ~= '', 'skill must be a non-empty string.')
    assert(Kora.minigames.GAME_TYPES[gameType], 'invalid minigame type -- see Kora.minigames.GAME_TYPES.')
    assert(opts == nil or type(opts) == 'table', 'minigame opts must be a table.')

    local adjusted = Kora.skills.adjustMinigame(skill, gameType, opts)
    return Kora.minigames.play(gameType, adjusted, authorization)
end
