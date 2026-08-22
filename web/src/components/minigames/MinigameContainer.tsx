import { useEffect, useState } from "react"

import type {
    CircuitPuzzle,
    LockpickPuzzle,
    MashPuzzle,
    MinigameAttempt,
    MinigamesClosePayload,
    MinigamesRoundPayload,
    SkillbarPuzzle,
} from "@/lib/types"
import { useNuiEvent } from "@/lib/useNuiEvent"
import { useNuiRequest } from "@/lib/useNuiRequest"
import { LockpickGame } from "./LockpickGame"
import { SkillbarGame } from "./SkillbarGame"
import { CircuitGame } from "./CircuitGame"
import { MashKeyGame } from "./MashKeyGame"

/**
 * Headless dispatcher for QB.minigames.play (modules/minigames/client.lua).
 * One `useNuiRequest("minigames:round")` subscription drives every round of a
 * session through the SAME mounted overlay -- Lua never closes and reopens it
 * between attempts, it just sends the next round's payload once the previous
 * one is answered (see modules/minigames/AGENTS.md). Each per-type child is
 * force-remounted per round via `key` so its own local timers/input state
 * never need to be manually reset between attempts.
 */
export function MinigameContainer() {
    const { payload, isOpen, respond } = useNuiRequest<MinigamesRoundPayload, MinigameAttempt>("minigames:round")
    const [closed, setClosed] = useState(false)

    // Force-hides even mid-round, when no respond() was ever called -- the
    // one case that happens is a cancelled session (resource-stop cleanup on
    // the Lua side, see client.lua's minigameOwnership), where the round
    // request the player was still looking at simply never gets an answer.
    useNuiEvent<MinigamesClosePayload | undefined>("minigames:close", () => {
        setClosed(true)
    })

    useEffect(() => {
        if (isOpen) setClosed(false)
    }, [isOpen, payload])

    if (!isOpen || !payload || closed) return null

    const roundKey = `${payload.sessionId}-${payload.attempt}`
    const shared = {
        attempt: payload.attempt,
        attempts: payload.attempts,
        timeLimit: payload.timeLimit,
        lastResult: payload.lastResult,
        respond,
    }

    switch (payload.type) {
        case "lockpick":
            return <LockpickGame key={roundKey} puzzle={payload.puzzle as LockpickPuzzle} {...shared} />
        case "skillbar":
            return <SkillbarGame key={roundKey} puzzle={payload.puzzle as SkillbarPuzzle} {...shared} />
        case "circuit":
            return <CircuitGame key={roundKey} puzzle={payload.puzzle as CircuitPuzzle} {...shared} />
        case "mash":
            return <MashKeyGame key={roundKey} puzzle={payload.puzzle as MashPuzzle} {...shared} />
        default:
            return null
    }
}
