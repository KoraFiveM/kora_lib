import { useEffect, useRef, useState } from "react"

import type { CancelledAttempt, LockpickAttempt, LockpickPress, LockpickPuzzle } from "@/lib/types"
import { triangleWave } from "@/lib/triangleWave"
import { cn } from "@/lib/cn"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"

interface LockpickGameProps {
    puzzle: LockpickPuzzle
    attempt: number
    attempts: number
    timeLimit: number
    lastResult?: "fail"
    respond: (attempt: LockpickAttempt | CancelledAttempt) => void
}

/**
 * One pin at a time: press Space while the indicator is over the highlighted
 * zone to lock it in and advance. Reports only { index, elapsed } per press --
 * never a position -- the server independently recomputes where the
 * indicator was from the same triangleWave formula (see
 * modules/minigames/AGENTS.md).
 */
export function LockpickGame({ puzzle, attempt, attempts, timeLimit, lastResult, respond }: LockpickGameProps) {
    const startRef = useRef(performance.now())
    const doneRef = useRef(false)
    const pressesRef = useRef<LockpickPress[]>([])
    const [elapsed, setElapsed] = useState(0)
    const [pinIndex, setPinIndex] = useState(0)
    // Purely cosmetic: which already-locked pins landed inside their target
    // zone, keyed by pin index. The server independently re-derives real
    // pass/fail from the same triangleWave formula and never trusts this --
    // see modules/minigames/AGENTS.md's "report timestamps, never positions"
    // note. This only decides whether a track glows green or amber.
    const [pinHits, setPinHits] = useState<Record<number, boolean>>({})

    useEffect(() => {
        let raf: number
        function tick() {
            setElapsed(performance.now() - startRef.current)
            raf = requestAnimationFrame(tick)
        }
        raf = requestAnimationFrame(tick)
        return () => cancelAnimationFrame(raf)
    }, [])

    function finish(presses: LockpickPress[]) {
        if (doneRef.current) return
        doneRef.current = true
        respond({ presses })
    }

    function cancel() {
        if (doneRef.current) return
        doneRef.current = true
        respond({ cancelled: true })
    }

    useEffect(() => {
        if (elapsed >= timeLimit) finish(pressesRef.current)
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [elapsed, timeLimit])

    useEffect(() => {
        function onKeyDown(event: KeyboardEvent) {
            if (event.repeat || (event.code !== "Space" && event.code !== "Enter")) return
            event.preventDefault()
            if (doneRef.current || pinIndex >= puzzle.pinCount) return

            const pressElapsed = performance.now() - startRef.current
            const press: LockpickPress = { index: pinIndex + 1, elapsed: pressElapsed }
            pressesRef.current = [...pressesRef.current, press]

            const pin = puzzle.pins[pinIndex]
            const hit = Math.abs(triangleWave(pressElapsed, puzzle.speed) - pin.target) <= puzzle.tolerance
            setPinHits((prev) => ({ ...prev, [pinIndex]: hit }))

            if (pinIndex + 1 >= puzzle.pinCount) {
                finish(pressesRef.current)
            } else {
                setPinIndex(pinIndex + 1)
            }
        }

        window.addEventListener("keydown", onKeyDown)
        return () => window.removeEventListener("keydown", onKeyDown)
    }, [pinIndex, puzzle])

    const position = triangleWave(elapsed, puzzle.speed)

    return (
        <Dialog open onOpenChange={(open) => { if (!open) cancel() }}>
            <DialogContent hideClose className="max-w-md">
                <DialogHeader>
                    <DialogTitle>
                        Lockpick &mdash; attempt {attempt} of {attempts}
                    </DialogTitle>
                </DialogHeader>

                {lastResult === "fail" && (
                    <p className="text-sm text-destructive">Last attempt failed &mdash; try again.</p>
                )}

                <div className="space-y-3">
                    {puzzle.pins.map((pin, i) => (
                        <PinTrack
                            key={pin.index}
                            active={i === pinIndex}
                            done={i < pinIndex}
                            hit={pinHits[i]}
                            target={pin.target}
                            tolerance={puzzle.tolerance}
                            position={i === pinIndex ? position : undefined}
                        />
                    ))}
                </div>

                <p className="text-xs text-muted-foreground">
                    Press <span className="font-medium text-foreground">Space</span> when the indicator is inside the highlighted zone.
                    Press <span className="font-medium text-foreground">Esc</span> to cancel.
                </p>
            </DialogContent>
        </Dialog>
    )
}

function PinTrack({
    active,
    done,
    hit,
    target,
    tolerance,
    position,
}: {
    active: boolean
    done: boolean
    hit?: boolean
    target: number
    tolerance: number
    position?: number
}) {
    return (
        <div
            className={cn(
                "relative h-3 overflow-hidden rounded-full bg-secondary transition-shadow",
                active && "ring-2 ring-primary",
                done && hit && "ring-2 ring-success"
            )}
        >
            <div
                className="absolute inset-y-0 rounded-full border border-brand-border bg-brand-soft"
                style={{ left: `${(target - tolerance) * 100}%`, width: `${tolerance * 2 * 100}%` }}
            />
            {active && position !== undefined && (
                <div
                    className="absolute top-1/2 h-4 w-1 -translate-x-1/2 -translate-y-1/2 rounded-full bg-primary"
                    style={{ left: `${position * 100}%` }}
                />
            )}
            {done && (
                <div
                    className={cn(
                        "absolute inset-0 flex items-center justify-end pr-2 text-[10px] font-semibold",
                        hit ? "text-success" : "text-muted-foreground"
                    )}
                >
                    {hit ? "got it" : "done"}
                </div>
            )}
        </div>
    )
}
