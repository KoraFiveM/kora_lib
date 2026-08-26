import { useEffect, useRef, useState } from "react"

import type { CancelledAttempt, HackingAttempt, HackingPuzzle } from "@/lib/types"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"

interface HackingGameProps {
    puzzle: HackingPuzzle
    attempt: number
    attempts: number
    timeLimit: number
    lastResult?: "fail"
    respond: (attempt: HackingAttempt | CancelledAttempt) => void
}

/**
 * `puzzle.code` is revealed directly (same reasoning as lockpick's target
 * zone) -- the skill is entering it correctly before the countdown ends, not
 * decrypting a hidden value. The server independently compares the
 * submission against its own copy (see server.lua's validate.hacking).
 */
export function HackingGame({ puzzle, attempt, attempts, timeLimit, lastResult, respond }: HackingGameProps) {
    const startRef = useRef(performance.now())
    const doneRef = useRef(false)
    const [elapsed, setElapsed] = useState(0)
    const [value, setValue] = useState("")

    useEffect(() => {
        let raf: number
        function tick() {
            setElapsed(performance.now() - startRef.current)
            raf = requestAnimationFrame(tick)
        }
        raf = requestAnimationFrame(tick)
        return () => cancelAnimationFrame(raf)
    }, [])

    function finish(submitted: string) {
        if (doneRef.current) return
        doneRef.current = true
        respond({ submitted, elapsed: performance.now() - startRef.current })
    }

    function cancel() {
        if (doneRef.current) return
        doneRef.current = true
        respond({ cancelled: true })
    }

    useEffect(() => {
        if (elapsed >= timeLimit) finish(value)
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [elapsed, timeLimit])

    const secondsLeft = Math.max(0, Math.ceil((timeLimit - elapsed) / 1000))

    return (
        <Dialog open onOpenChange={(open) => { if (!open) cancel() }}>
            <DialogContent hideClose className="max-w-sm">
                <DialogHeader>
                    <DialogTitle>
                        Hacking &mdash; attempt {attempt} of {attempts}
                    </DialogTitle>
                </DialogHeader>

                {lastResult === "fail" && (
                    <p className="text-sm text-destructive">Last attempt failed &mdash; try again.</p>
                )}

                <p className="text-center text-2xl font-mono font-semibold tracking-widest text-primary">
                    {puzzle.code}
                </p>
                <p className="text-center text-xs tabular-nums text-muted-foreground">{secondsLeft}s left</p>

                <div className="flex gap-2">
                    <Input
                        autoFocus
                        value={value}
                        maxLength={puzzle.solutionsize}
                        onChange={(e) => setValue(e.target.value.toUpperCase())}
                        onKeyDown={(e) => { if (e.key === "Enter") finish(value) }}
                        placeholder="Enter the code..."
                        className="font-mono uppercase"
                    />
                    <Button onClick={() => finish(value)}>Submit</Button>
                </div>

                <p className="text-xs text-muted-foreground">Press <span className="font-medium text-foreground">Esc</span> to cancel.</p>
            </DialogContent>
        </Dialog>
    )
}
