import { useMinigameLabels, formatMinigameLabel } from '@/lib/minigameLocale'
import { useRef, useState } from "react"

import type { CancelledAttempt, HackingAttempt, HackingPuzzle } from "@/lib/types"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { useMinigameTimeout, useSecondsLeft } from "@/components/minigames/useMinigameTimer"

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
    const labels = useMinigameLabels()
    const startRef = useRef(performance.now())
    const doneRef = useRef(false)
    const valueRef = useRef("")
    const [value, setValue] = useState("")

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

    useMinigameTimeout(timeLimit, () => finish(valueRef.current))
    const secondsLeft = useSecondsLeft(startRef.current, timeLimit)

    return (
        <Dialog open onOpenChange={(open) => { if (!open) cancel() }}>
            <DialogContent hideClose className="max-w-sm">
                <DialogHeader>
                    <DialogTitle>
                        {formatMinigameLabel(labels.titleAttempt, labels.titleHacking, attempt, attempts)}
                    </DialogTitle>
                </DialogHeader>

                {lastResult === "fail" && (
                    <p className="text-sm text-destructive">{labels.lastAttemptFailed}</p>
                )}

                <p className="text-center text-2xl font-mono font-semibold tracking-widest text-primary">
                    {puzzle.code}
                </p>
                <p className="text-center text-xs tabular-nums text-muted-foreground">{formatMinigameLabel(labels.secondsLeft, secondsLeft)}</p>

                <div className="flex gap-2">
                    <Input
                        autoFocus
                        value={value}
                        maxLength={puzzle.solutionsize}
                        onChange={(e) => {
                            const next = e.target.value.toUpperCase()
                            valueRef.current = next
                            setValue(next)
                        }}
                        onKeyDown={(e) => { if (e.key === "Enter") finish(value) }}
                        placeholder="Enter the code..."
                        className="font-mono uppercase"
                    />
                    <Button onClick={() => finish(value)}>{labels.submit}</Button>
                </div>

                <p className="text-xs text-muted-foreground">{formatMinigameLabel(labels.cancelInstruction, "Esc")}</p>
            </DialogContent>
        </Dialog>
    )
}
