import { useEffect, useRef, useState } from "react"

import type { LockpickAttempt, LockpickPress, LockpickPuzzle } from "@/lib/types"
import { triangleWave } from "@/lib/triangleWave"
import { cn } from "@/lib/cn"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"

interface LockpickGameProps {
    puzzle: LockpickPuzzle
    attempt: number
    attempts: number
    timeLimit: number
    lastResult?: "fail"
    respond: (attempt: LockpickAttempt) => void
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

    useEffect(() => {
        if (elapsed >= timeLimit) finish(pressesRef.current)
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [elapsed, timeLimit])

    useEffect(() => {
        function onKeyDown(event: KeyboardEvent) {
            if (event.repeat || (event.code !== "Space" && event.code !== "Enter")) return
            event.preventDefault()
            if (doneRef.current || pinIndex >= puzzle.pinCount) return

            const press: LockpickPress = { index: pinIndex + 1, elapsed: performance.now() - startRef.current }
            pressesRef.current = [...pressesRef.current, press]

            if (pinIndex + 1 >= puzzle.pinCount) {
                finish(pressesRef.current)
            } else {
                setPinIndex(pinIndex + 1)
            }
        }

        window.addEventListener("keydown", onKeyDown)
        return () => window.removeEventListener("keydown", onKeyDown)
    }, [pinIndex, puzzle.pinCount])

    const position = triangleWave(elapsed, puzzle.speed)

    return (
        <Dialog open>
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
                            target={pin.target}
                            tolerance={puzzle.tolerance}
                            position={i === pinIndex ? position : undefined}
                        />
                    ))}
                </div>

                <p className="text-xs text-muted-foreground">
                    Press <span className="font-medium text-foreground">Space</span> when the indicator is inside the highlighted zone.
                </p>
            </DialogContent>
        </Dialog>
    )
}

function PinTrack({
    active,
    done,
    target,
    tolerance,
    position,
}: {
    active: boolean
    done: boolean
    target: number
    tolerance: number
    position?: number
}) {
    return (
        <div className={cn("relative h-3 overflow-hidden rounded-full bg-secondary", active && "ring-2 ring-primary")}>
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
                <div className="absolute inset-0 flex items-center justify-end pr-2 text-[10px] font-semibold text-success">
                    done
                </div>
            )}
        </div>
    )
}
