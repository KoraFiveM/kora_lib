import { useEffect, useRef, useState } from "react"

import type { CancelledAttempt, MashAttempt, MashPuzzle } from "@/lib/types"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { useMinigameTimeout } from "@/components/minigames/useMinigameTimer"

interface MashKeyGameProps {
    puzzle: MashPuzzle
    attempt: number
    attempts: number
    timeLimit: number
    lastResult?: "fail"
    respond: (attempt: MashAttempt | CancelledAttempt) => void
}

/**
 * Press Space `requiredPresses` times before the round ends. Reports the raw
 * press timestamps, not a count -- the server independently checks spacing
 * and total (see modules/minigames/server.lua's validate.mash).
 */
export function MashKeyGame({ puzzle, attempt, attempts, timeLimit, lastResult, respond }: MashKeyGameProps) {
    const startRef = useRef(performance.now())
    const doneRef = useRef(false)
    const pressesRef = useRef<number[]>([])
    const [pressCount, setPressCount] = useState(0)

    function finish(pressTimestamps: number[]) {
        if (doneRef.current) return
        doneRef.current = true
        respond({ pressTimestamps })
    }

    function cancel() {
        if (doneRef.current) return
        doneRef.current = true
        respond({ cancelled: true })
    }

    useMinigameTimeout(timeLimit, () => finish(pressesRef.current))

    useEffect(() => {
        function onKeyDown(event: KeyboardEvent) {
            if (event.repeat || (event.code !== "Space" && event.code !== "Enter")) return
            event.preventDefault()
            if (doneRef.current) return

            pressesRef.current = [...pressesRef.current, performance.now() - startRef.current]
            setPressCount(pressesRef.current.length)

            if (pressesRef.current.length >= puzzle.requiredPresses) finish(pressesRef.current)
        }

        window.addEventListener("keydown", onKeyDown)
        return () => window.removeEventListener("keydown", onKeyDown)
    }, [puzzle.requiredPresses])

    const progress = Math.min(1, pressCount / puzzle.requiredPresses)

    return (
        <Dialog open onOpenChange={(open) => { if (!open) cancel() }}>
            <DialogContent hideClose className="max-w-md">
                <DialogHeader>
                    <DialogTitle>
                        Mash &mdash; attempt {attempt} of {attempts}
                    </DialogTitle>
                </DialogHeader>

                {lastResult === "fail" && (
                    <p className="text-sm text-destructive">Last attempt failed &mdash; try again.</p>
                )}

                <div className="h-4 overflow-hidden rounded-full bg-secondary">
                    <div className="h-full rounded-full bg-primary transition-[width]" style={{ width: `${progress * 100}%` }} />
                </div>

                <p className="text-center text-sm tabular-nums text-muted-foreground">
                    {pressCount} / {puzzle.requiredPresses}
                </p>

                <p className="text-xs text-muted-foreground">
                    Press <span className="font-medium text-foreground">Space</span> as fast as you can. Press{" "}
                    <span className="font-medium text-foreground">Esc</span> to cancel.
                </p>
            </DialogContent>
        </Dialog>
    )
}
