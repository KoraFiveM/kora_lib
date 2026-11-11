import { useEffect, useRef, useState } from "react"

import type { CancelledAttempt, KeysAttempt, KeysPress, KeysPuzzle } from "@/lib/types"
import { cn } from "@/lib/cn"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { useMinigameTimeout } from "@/components/minigames/useMinigameTimer"

interface KeysGameProps {
    puzzle: KeysPuzzle
    attempt: number
    attempts: number
    timeLimit: number
    lastResult?: "fail"
    respond: (attempt: KeysAttempt | CancelledAttempt) => void
}

const ARROW_TO_KEY: Record<string, string> = {
    ArrowUp: "up",
    ArrowDown: "down",
    ArrowLeft: "left",
    ArrowRight: "right",
}
const ARROW_SYMBOL: Record<string, string> = { up: "↑", down: "↓", left: "←", right: "→" }

/**
 * `puzzle.pattern` is revealed in full up front (see server.lua's
 * generate.keys) -- the player has to see which key comes next. Reports
 * every prompt's response (or a miss, if the player never pressed in time)
 * with a timestamp; the server independently counts faults from this same
 * data (see validate.keys) -- always "succeeding" like upstream's
 * KeyMinigame, which has no pass/fail concept, only a faults count.
 */
export function KeysGame({ puzzle, attempt, attempts, timeLimit, lastResult, respond }: KeysGameProps) {
    const startRef = useRef(performance.now())
    const doneRef = useRef(false)
    const pressesRef = useRef<KeysPress[]>([])
    const [index, setIndex] = useState(0)

    function finish(presses: KeysPress[]) {
        if (doneRef.current) return
        doneRef.current = true
        respond({ presses })
    }

    function cancel() {
        if (doneRef.current) return
        doneRef.current = true
        respond({ cancelled: true })
    }

    useMinigameTimeout(timeLimit, () => finish(pressesRef.current))

    useEffect(() => {
        function onKeyDown(event: KeyboardEvent) {
            if (event.repeat) return
            const key = ARROW_TO_KEY[event.key]
            if (!key || doneRef.current || index >= puzzle.pattern.length) return
            event.preventDefault()

            const now = performance.now() - startRef.current
            pressesRef.current = [...pressesRef.current, { key, elapsed: now }]

            if (index + 1 >= puzzle.pattern.length) {
                finish(pressesRef.current)
            } else {
                setIndex(index + 1)
            }
        }

        window.addEventListener("keydown", onKeyDown)
        return () => window.removeEventListener("keydown", onKeyDown)
    }, [index, puzzle.pattern])

    return (
        <Dialog open onOpenChange={(open) => { if (!open) cancel() }}>
            <DialogContent hideClose className="max-w-md">
                <DialogHeader>
                    <DialogTitle>
                        Keys &mdash; attempt {attempt} of {attempts}
                    </DialogTitle>
                </DialogHeader>

                {lastResult === "fail" && (
                    <p className="text-sm text-destructive">Last attempt failed &mdash; try again.</p>
                )}

                <div className="flex flex-wrap justify-center gap-2">
                    {puzzle.pattern.map((key, i) => (
                        <div
                            key={i}
                            className={cn(
                                "flex h-9 w-9 items-center justify-center rounded-md border border-input bg-background text-lg font-semibold",
                                i === index && "border-primary bg-brand-soft text-primary",
                                i < index && "opacity-40"
                            )}
                        >
                            {ARROW_SYMBOL[key]}
                        </div>
                    ))}
                </div>

                <p className="text-center text-xs text-muted-foreground">
                    Press the highlighted arrow key. Press <span className="font-medium text-foreground">Esc</span> to cancel.
                </p>
            </DialogContent>
        </Dialog>
    )
}
