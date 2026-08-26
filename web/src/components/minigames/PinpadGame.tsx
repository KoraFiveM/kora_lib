import { useEffect, useRef, useState } from "react"

import type { CancelledAttempt, PinpadAttempt, PinpadDigit, PinpadPuzzle } from "@/lib/types"
import { Button } from "@/components/ui/button"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"

interface PinpadGameProps {
    puzzle: PinpadPuzzle
    attempt: number
    attempts: number
    timeLimit: number
    lastResult?: "fail"
    respond: (attempt: PinpadAttempt | CancelledAttempt) => void
}

/**
 * Enter `puzzle.digitCount` digits on a numeric keypad. Reports only which
 * digit was pressed and when -- never whether it's correct -- the server
 * independently compares the full sequence against the real PIN (see
 * modules/minigames/server.lua's validate.pinpad).
 */
export function PinpadGame({ puzzle, attempt, attempts, timeLimit, lastResult, respond }: PinpadGameProps) {
    const startRef = useRef(performance.now())
    const doneRef = useRef(false)
    const digitsRef = useRef<PinpadDigit[]>([])
    const [elapsed, setElapsed] = useState(0)
    const [entered, setEntered] = useState<number[]>([])

    useEffect(() => {
        let raf: number
        function tick() {
            setElapsed(performance.now() - startRef.current)
            raf = requestAnimationFrame(tick)
        }
        raf = requestAnimationFrame(tick)
        return () => cancelAnimationFrame(raf)
    }, [])

    function finish(digits: PinpadDigit[]) {
        if (doneRef.current) return
        doneRef.current = true
        respond({ digits })
    }

    function cancel() {
        if (doneRef.current) return
        doneRef.current = true
        respond({ cancelled: true })
    }

    useEffect(() => {
        if (elapsed >= timeLimit) finish(digitsRef.current)
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [elapsed, timeLimit])

    function press(value: number) {
        if (doneRef.current || entered.length >= puzzle.digitCount) return
        const now = performance.now() - startRef.current
        digitsRef.current = [...digitsRef.current, { value, elapsed: now }]
        const next = [...entered, value]
        setEntered(next)
        if (next.length >= puzzle.digitCount) finish(digitsRef.current)
    }

    function clear() {
        if (doneRef.current) return
        digitsRef.current = []
        setEntered([])
    }

    return (
        <Dialog open onOpenChange={(open) => { if (!open) cancel() }}>
            <DialogContent hideClose className="max-w-xs">
                <DialogHeader>
                    <DialogTitle>
                        Pinpad &mdash; attempt {attempt} of {attempts}
                    </DialogTitle>
                </DialogHeader>

                {lastResult === "fail" && (
                    <p className="text-sm text-destructive">Last attempt failed &mdash; try again.</p>
                )}

                <div className="flex items-center justify-center gap-2">
                    {Array.from({ length: puzzle.digitCount }).map((_, i) => (
                        <div
                            key={i}
                            className="flex h-9 w-7 items-center justify-center rounded-md border border-input bg-background text-lg font-semibold"
                        >
                            {i < entered.length ? "•" : ""}
                        </div>
                    ))}
                </div>

                <div className="grid grid-cols-3 gap-2">
                    {[1, 2, 3, 4, 5, 6, 7, 8, 9].map((n) => (
                        <Button key={n} variant="secondary" onClick={() => press(n)}>
                            {n}
                        </Button>
                    ))}
                    <Button variant="outline" onClick={clear}>C</Button>
                    <Button variant="secondary" onClick={() => press(0)}>0</Button>
                    <div />
                </div>

                <p className="text-xs text-muted-foreground">Press <span className="font-medium text-foreground">Esc</span> to cancel.</p>
            </DialogContent>
        </Dialog>
    )
}
