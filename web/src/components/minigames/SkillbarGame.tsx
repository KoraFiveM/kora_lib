import { useEffect, useRef } from "react"

import type { CancelledAttempt, SkillbarAttempt, SkillbarPuzzle } from "@/lib/types"
import { triangleWave } from "@/lib/triangleWave"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { useMinigameTimeout } from "@/components/minigames/useMinigameTimer"

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
    const indicatorRef = useRef<HTMLDivElement>(null)

    useEffect(() => {
        let raf: number
        function tick() {
            if (doneRef.current) return
            const position = triangleWave(performance.now() - startRef.current, puzzle.speed)
            if (indicatorRef.current) indicatorRef.current.style.left = `${position * 100}%`
            raf = requestAnimationFrame(tick)
        }
        raf = requestAnimationFrame(tick)
        return () => cancelAnimationFrame(raf)
    }, [puzzle.speed])

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

    useMinigameTimeout(timeLimit, () => finish(performance.now() - startRef.current))

    useEffect(() => {
        function onKeyDown(event: KeyboardEvent) {
            const expected = puzzle.input?.toLowerCase()
            const accepted = expected ? event.key.toLowerCase() === expected : event.code === "Space" || event.code === "Enter"
            if (event.repeat || !accepted) return
            event.preventDefault()
            finish(performance.now() - startRef.current)
        }

        window.addEventListener("keydown", onKeyDown)
        return () => window.removeEventListener("keydown", onKeyDown)
    }, [puzzle.input])

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
                        ref={indicatorRef}
                        className="absolute top-1/2 h-5 w-1 -translate-x-1/2 -translate-y-1/2 rounded-full bg-primary"
                        style={{ left: "0%" }}
                    />
                </div>

                <p className="text-xs text-muted-foreground">
                    Press <span className="font-medium text-foreground">{puzzle.input?.toUpperCase() ?? "Space"}</span> when the indicator is inside the zone.
                    Press <span className="font-medium text-foreground">Esc</span> to cancel.
                </p>
            </DialogContent>
        </Dialog>
    )
}
