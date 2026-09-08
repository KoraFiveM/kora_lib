import { useEffect, useRef, useState } from "react"

import type { CancelledAttempt, WordGuessAttempt, WordGuessLetter, WordGuessPuzzle } from "@/lib/types"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { useMinigameTimeout } from "@/components/minigames/useMinigameTimer"

interface WordGuessGameProps {
    puzzle: WordGuessPuzzle
    attempt: number
    attempts: number
    timeLimit: number
    lastResult?: "fail"
    respond: (attempt: WordGuessAttempt | CancelledAttempt) => void
}

/**
 * The word itself is never sent to this client -- only its length and a
 * hint (see server.lua's generate.wordguess) -- so unlike upstream's
 * hangman, this can't reveal correct letters live; it only reports every
 * guessed letter and when, and the server alone decides success/failure at
 * the end of the round.
 */
export function WordGuessGame({ puzzle, attempt, attempts, timeLimit, lastResult, respond }: WordGuessGameProps) {
    const startRef = useRef(performance.now())
    const doneRef = useRef(false)
    const guessesRef = useRef<WordGuessLetter[]>([])
    const [guessed, setGuessed] = useState<string[]>([])

    function finish(guesses: WordGuessLetter[]) {
        if (doneRef.current) return
        doneRef.current = true
        respond({ guesses })
    }

    function cancel() {
        if (doneRef.current) return
        doneRef.current = true
        respond({ cancelled: true })
    }

    useMinigameTimeout(timeLimit, () => finish(guessesRef.current))

    useEffect(() => {
        function onKeyDown(event: KeyboardEvent) {
            if (doneRef.current) return
            if (event.key === "Escape") return
            if (!/^[a-zA-Z]$/.test(event.key)) return
            const letter = event.key.toLowerCase()
            if (guessed.includes(letter)) return

            const now = performance.now() - startRef.current
            guessesRef.current = [...guessesRef.current, { letter, elapsed: now }]
            setGuessed((prev) => [...prev, letter])
        }

        window.addEventListener("keydown", onKeyDown)
        return () => window.removeEventListener("keydown", onKeyDown)
    }, [guessed])

    return (
        <Dialog open onOpenChange={(open) => { if (!open) cancel() }}>
            <DialogContent hideClose className="max-w-md">
                <DialogHeader>
                    <DialogTitle>
                        Word Guess &mdash; attempt {attempt} of {attempts}
                    </DialogTitle>
                </DialogHeader>

                {lastResult === "fail" && (
                    <p className="text-sm text-destructive">Last attempt failed &mdash; try again.</p>
                )}

                <p className="text-sm text-muted-foreground">Hint: {puzzle.hint}</p>

                <div className="flex flex-wrap justify-center gap-1">
                    {Array.from({ length: puzzle.length }).map((_, i) => (
                        <div key={i} className="flex h-9 w-7 items-center justify-center rounded-md border border-input bg-background" />
                    ))}
                </div>

                <p className="text-center text-xs text-muted-foreground">
                    Guessed: {guessed.join(", ").toUpperCase() || "—"} ({Math.max(0, puzzle.guesses - guessed.length)} guesses left)
                </p>

                <p className="text-xs text-muted-foreground">
                    Type a letter to guess it. Press <span className="font-medium text-foreground">Esc</span> to cancel.
                </p>
            </DialogContent>
        </Dialog>
    )
}
