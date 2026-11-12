import { useRef, useState } from "react"

import type { CancelledAttempt, WordScrambleAttempt, WordScramblePuzzle } from "@/lib/types"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { useMinigameTimeout, useSecondsLeft } from "@/components/minigames/useMinigameTimer"

interface WordScrambleGameProps {
    puzzle: WordScramblePuzzle
    attempt: number
    attempts: number
    timeLimit: number
    lastResult?: "fail"
    respond: (attempt: WordScrambleAttempt | CancelledAttempt) => void
}

/**
 * `puzzle.scrambled` is shuffled server-side (see server.lua's
 * generate.wordscramble) -- this just collects one typed guess and reports
 * it with a timestamp; the server alone compares it against the real word.
 */
export function WordScrambleGame({ puzzle, attempt, attempts, timeLimit, lastResult, respond }: WordScrambleGameProps) {
    const startRef = useRef(performance.now())
    const doneRef = useRef(false)
    const valueRef = useRef("")
    const [value, setValue] = useState("")

    function finish(guess: string) {
        if (doneRef.current) return
        doneRef.current = true
        respond({ guess, elapsed: performance.now() - startRef.current })
    }

    function cancel() {
        if (doneRef.current) return
        doneRef.current = true
        respond({ cancelled: true })
    }

    useMinigameTimeout(timeLimit, () => finish(valueRef.current))
    const secondsLeft = useSecondsLeft(startRef.current, timeLimit)

    return (
        <Dialog open onOpenChange={(open) => { if (!open) cancel() }}>
            <DialogContent hideClose className="max-w-sm">
                <DialogHeader>
                    <DialogTitle>
                        Word Scramble &mdash; attempt {attempt} of {attempts}
                    </DialogTitle>
                </DialogHeader>

                {lastResult === "fail" && (
                    <p className="text-sm text-destructive">Last attempt failed &mdash; try again.</p>
                )}

                <p className="text-sm text-muted-foreground">Hint: {puzzle.hint}</p>
                <p className="text-center text-2xl font-semibold tracking-widest text-foreground">
                    {puzzle.scrambled.toUpperCase()}
                </p>
                <p className="text-center text-xs tabular-nums text-muted-foreground">{secondsLeft}s left</p>

                <div className="flex gap-2">
                    <Input
                        autoFocus
                        value={value}
                        onChange={(e) => {
                            valueRef.current = e.target.value
                            setValue(e.target.value)
                        }}
                        onKeyDown={(e) => { if (e.key === "Enter") finish(value) }}
                        placeholder="Unscramble the word..."
                    />
                    <Button onClick={() => finish(value)}>Submit</Button>
                </div>

                <p className="text-xs text-muted-foreground">Press <span className="font-medium text-foreground">Esc</span> to cancel.</p>
            </DialogContent>
        </Dialog>
    )
}
