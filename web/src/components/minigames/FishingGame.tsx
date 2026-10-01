import { useEffect, useRef, useState } from "react"

import type { CancelledAttempt, FishingAttempt, FishingPuzzle, FishingReel } from "@/lib/types"
import { triangleWave } from "@/lib/triangleWave"
import { cn } from "@/lib/cn"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { useMinigameTimeout } from "@/components/minigames/useMinigameTimer"

interface FishingGameProps {
    puzzle: FishingPuzzle
    attempt: number
    attempts: number
    timeLimit: number
    lastResult?: "fail"
    respond: (attempt: FishingAttempt | CancelledAttempt) => void
}

/**
 * A compact fishing tension gauge. The browser only reports when each reel
 * happened; the server independently recomputes the marker position.
 */
export function FishingGame({ puzzle, attempt, attempts, timeLimit, lastResult, respond }: FishingGameProps) {
    const startRef = useRef(performance.now())
    const doneRef = useRef(false)
    const reelsRef = useRef<FishingReel[]>([])
    const markerRef = useRef<HTMLDivElement>(null)
    const [biteIndex, setBiteIndex] = useState(0)
    const [caught, setCaught] = useState<boolean[]>([])

    useEffect(() => {
        let raf = 0
        function tick() {
            if (doneRef.current) return
            const position = triangleWave(performance.now() - startRef.current, puzzle.speed)
            if (markerRef.current) markerRef.current.style.bottom = `${position * 100}%`
            raf = requestAnimationFrame(tick)
        }
        raf = requestAnimationFrame(tick)
        return () => cancelAnimationFrame(raf)
    }, [puzzle.speed])

    function finish(reels: FishingReel[]) {
        if (doneRef.current) return
        doneRef.current = true
        respond({ reels })
    }

    function cancel() {
        if (doneRef.current) return
        doneRef.current = true
        respond({ cancelled: true })
    }

    useMinigameTimeout(timeLimit, () => finish(reelsRef.current))

    useEffect(() => {
        function onKeyDown(event: KeyboardEvent) {
            if (event.repeat || (event.code !== "Space" && event.code !== "Enter")) return
            event.preventDefault()
            if (doneRef.current || biteIndex >= puzzle.gameCount) return

            const elapsed = performance.now() - startRef.current
            const position = triangleWave(elapsed, puzzle.speed)
            const zoneStart = puzzle.targets[biteIndex] - puzzle.zoneSize / 2
            const hit = position >= zoneStart && position <= zoneStart + puzzle.zoneSize
            const reel = { index: biteIndex + 1, elapsed }
            reelsRef.current = [...reelsRef.current, reel]
            setCaught((previous) => [...previous, hit])
            if (biteIndex + 1 >= puzzle.gameCount) finish(reelsRef.current)
            else setBiteIndex((previous) => previous + 1)
        }
        window.addEventListener("keydown", onKeyDown)
        return () => window.removeEventListener("keydown", onKeyDown)
    }, [biteIndex, puzzle])

    return (
        <Dialog open onOpenChange={(open) => { if (!open) cancel() }}>
            <DialogContent hideClose className="right-4 left-auto max-w-sm translate-x-0 sm:right-8">
                <DialogHeader>
                    <DialogTitle>Fishing &mdash; attempt {attempt} of {attempts}</DialogTitle>
                </DialogHeader>

                {lastResult === "fail" && <p className="text-sm text-destructive">The line slipped &mdash; cast again.</p>}

                <div className="flex items-center justify-center gap-5 py-2">
                    <div className="relative h-64 w-16 overflow-hidden rounded-full border border-border-strong bg-secondary shadow-inner">
                        <div className="absolute inset-x-0 bottom-0 h-2/3 bg-brand-soft/40" />
                        <div className="absolute inset-x-2 top-2 bottom-2 border-x border-border/60" />
                        <div
                            ref={markerRef}
                            className="absolute left-1/2 h-5 w-5 -translate-x-1/2 translate-y-1/2 rounded-full border-2 border-background bg-primary shadow-[0_0_14px_hsl(var(--primary)/0.65)]"
                            style={{ bottom: "0%" }}
                        />
                        <div
                            className="absolute inset-x-1 rounded-full border border-brand-border bg-brand-soft/80 shadow-[0_0_12px_hsl(var(--primary)/0.18)]"
                            style={{
                                bottom: `${(puzzle.targets[biteIndex] - puzzle.zoneSize / 2) * 100}%`,
                                height: `${puzzle.zoneSize * 100}%`,
                            }}
                        />
                        <div className="absolute inset-x-0 top-1/2 h-px bg-border/50" />
                    </div>
                    <div className="flex flex-col gap-2 text-sm">
                        <p className="font-medium">Keep the marker in the bite zone.</p>
                        <div className="flex gap-1.5">
                            {Array.from({ length: puzzle.gameCount }, (_, index) => (
                                <span key={index} className={cn("h-2 w-8 rounded-full bg-secondary", index < caught.length && (caught[index] ? "bg-success" : "bg-destructive"))} />
                            ))}
                        </div>
                        <p className="text-xs text-muted-foreground">Game {Math.min(biteIndex + 1, puzzle.gameCount)} of {puzzle.gameCount}</p>
                    </div>
                </div>

                <p className="text-xs text-muted-foreground">Press <span className="font-medium text-foreground">Space</span> when the marker is in the highlighted zone. Press <span className="font-medium text-foreground">Esc</span> to cancel.</p>
            </DialogContent>
        </Dialog>
    )
}
