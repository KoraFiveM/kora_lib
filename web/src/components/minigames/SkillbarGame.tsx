import { useEffect, useRef, useState } from "react"

import type { CancelledAttempt, SkillbarAttempt, SkillbarPuzzle } from "@/lib/types"
import { triangleWave } from "@/lib/triangleWave"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"

interface SkillbarGameProps {
    puzzle: SkillbarPuzzle
    attempt: number
    attempts: number
    timeLimit: number
    lastResult?: "fail"
    respond: (attempt: SkillbarAttempt | CancelledAttempt) => void
}

/**
 * One moving bar, one press: reports only { elapsed } -- never a position --
 * the server independently recomputes where the bar was from the same
 * triangleWave formula (see modules/minigames/AGENTS.md).
 */
export function SkillbarGame({ puzzle, attempt, attempts, timeLimit, lastResult, respond }: SkillbarGameProps) {
    const startRef = useRef(performance.now())
    const doneRef = useRef(false)
    const [elapsed, setElapsed] = useState(0)

    useEffect(() => {
        let raf: number
        function tick() {
            setElapsed(performance.now() - startRef.current)
            raf = requestAnimationFrame(tick)
        }
        raf = requestAnimationFrame(tick)
        return () => cancelAnimationFrame(raf)
    }, [])

    function finish(elapsedAtPress: number) {
        if (doneRef.current) return
        doneRef.current = true
        respond({ elapsed: elapsedAtPress })
    }

    function cancel() {
        if (doneRef.current) return
        doneRef.current = true
        respond({ cancelled: true })
    }

    useEffect(() => {
        if (elapsed >= timeLimit) finish(elapsed)
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [elapsed, timeLimit])

    useEffect(() => {
        function onKeyDown(event: KeyboardEvent) {
            if (event.repeat || (event.code !== "Space" && event.code !== "Enter")) return
            event.preventDefault()
            finish(performance.now() - startRef.current)
        }

        window.addEventListener("keydown", onKeyDown)
        return () => window.removeEventListener("keydown", onKeyDown)
    }, [])

    const position = triangleWave(elapsed, puzzle.speed)

    return (
        <Dialog open onOpenChange={(open) => { if (!open) cancel() }}>
            <DialogContent hideClose className="max-w-md">
                <DialogHeader>
                    <DialogTitle>
                        Skill check &mdash; attempt {attempt} of {attempts}
                    </DialogTitle>
                </DialogHeader>

                {lastResult === "fail" && (
                    <p className="text-sm text-destructive">Last attempt failed &mdash; try again.</p>
                )}

                <div className="relative h-4 overflow-hidden rounded-full bg-secondary">
                    <div
                        className="absolute inset-y-0 rounded-full border border-brand-border bg-brand-soft"
                        style={{ left: `${puzzle.zoneStart * 100}%`, width: `${(puzzle.zoneEnd - puzzle.zoneStart) * 100}%` }}
                    />
                    <div
                        className="absolute top-1/2 h-5 w-1 -translate-x-1/2 -translate-y-1/2 rounded-full bg-primary"
                        style={{ left: `${position * 100}%` }}
                    />
                </div>

                <p className="text-xs text-muted-foreground">
                    Press <span className="font-medium text-foreground">Space</span> when the indicator is inside the zone.
                    Press <span className="font-medium text-foreground">Esc</span> to cancel.
                </p>
            </DialogContent>
        </Dialog>
    )
}
