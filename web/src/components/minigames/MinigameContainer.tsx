import { useEffect, useState } from "react"

import type {
    CircuitPuzzle,
    HackingPuzzle,
    KeysPuzzle,
    LockpickPuzzle,
    MashPuzzle,
    FishingPuzzle,
    MinigameAttempt,
    MinigamesClosePayload,
    MinigamesRoundPayload,
    PinpadPuzzle,
    QuizPuzzle,
    SkillbarPuzzle,
    WordGuessPuzzle,
    WordScramblePuzzle,
} from "@/lib/types"
import { useNuiEvent } from "@/lib/useNuiEvent"
import { useNuiRequest } from "@/lib/useNuiRequest"
import { LockpickGame } from "./LockpickGame"
import { SkillbarGame } from "./SkillbarGame"
import { CircuitGame } from "./CircuitGame"
import { MashKeyGame } from "./MashKeyGame"
import { PinpadGame } from "./PinpadGame"
import { QuizGame } from "./QuizGame"
import { WordGuessGame } from "./WordGuessGame"
import { WordScrambleGame } from "./WordScrambleGame"
import { KeysGame } from "./KeysGame"
import { HackingGame } from "./HackingGame"
import { FishingGame } from "./FishingGame"

/**
 * Headless dispatcher for Kora.minigames.play (modules/minigames/client.lua).
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
        case "fishing":
            return <FishingGame key={roundKey} puzzle={payload.puzzle as FishingPuzzle} {...shared} />
        case "pinpad":
            return <PinpadGame key={roundKey} puzzle={payload.puzzle as PinpadPuzzle} {...shared} />
        case "quiz":
            return <QuizGame key={roundKey} puzzle={payload.puzzle as QuizPuzzle} {...shared} />
        case "wordguess":
            return <WordGuessGame key={roundKey} puzzle={payload.puzzle as WordGuessPuzzle} {...shared} />
        case "wordscramble":
            return <WordScrambleGame key={roundKey} puzzle={payload.puzzle as WordScramblePuzzle} {...shared} />
        case "keys":
            return <KeysGame key={roundKey} puzzle={payload.puzzle as KeysPuzzle} {...shared} />
        case "hacking":
            return <HackingGame key={roundKey} puzzle={payload.puzzle as HackingPuzzle} {...shared} />
        default:
            return null
    }
}
