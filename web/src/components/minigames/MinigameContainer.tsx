import { useEffect, useState, type ReactNode } from "react"

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
import { MinigameLocaleProvider } from "@/lib/minigameLocale"
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

    let game: ReactNode = null
    switch (payload.type) {
        case "lockpick": game = <LockpickGame key={roundKey} puzzle={payload.puzzle as LockpickPuzzle} {...shared} />; break
        case "skillbar": game = <SkillbarGame key={roundKey} puzzle={payload.puzzle as SkillbarPuzzle} {...shared} />; break
        case "circuit": game = <CircuitGame key={roundKey} puzzle={payload.puzzle as CircuitPuzzle} {...shared} />; break
        case "mash": game = <MashKeyGame key={roundKey} puzzle={payload.puzzle as MashPuzzle} {...shared} />; break
        case "fishing": game = <FishingGame key={roundKey} puzzle={payload.puzzle as FishingPuzzle} {...shared} />; break
        case "pinpad": game = <PinpadGame key={roundKey} puzzle={payload.puzzle as PinpadPuzzle} {...shared} />; break
        case "quiz": game = <QuizGame key={roundKey} puzzle={payload.puzzle as QuizPuzzle} {...shared} />; break
        case "wordguess": game = <WordGuessGame key={roundKey} puzzle={payload.puzzle as WordGuessPuzzle} {...shared} />; break
        case "wordscramble": game = <WordScrambleGame key={roundKey} puzzle={payload.puzzle as WordScramblePuzzle} {...shared} />; break
        case "keys": game = <KeysGame key={roundKey} puzzle={payload.puzzle as KeysPuzzle} {...shared} />; break
        case "hacking": game = <HackingGame key={roundKey} puzzle={payload.puzzle as HackingPuzzle} {...shared} />; break
    }
    return <MinigameLocaleProvider labels={payload.labels}>{game}</MinigameLocaleProvider>
}
