import { useEffect, useRef, useState } from "react"

import type { CancelledAttempt, QuizAnswer, QuizAttempt, QuizPuzzle } from "@/lib/types"
import { Button } from "@/components/ui/button"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"

interface QuizGameProps {
    puzzle: QuizPuzzle
    attempt: number
    attempts: number
    timeLimit: number
    lastResult?: "fail"
    respond: (attempt: QuizAttempt | CancelledAttempt) => void
}

/**
 * One question at a time; the correct answer is never sent to this client
 * (see server.lua's generate.quiz) -- only the chosen option and when it was
 * chosen are reported, so grading happens entirely server-side.
 */
export function QuizGame({ puzzle, attempt, attempts, timeLimit, lastResult, respond }: QuizGameProps) {
    const startRef = useRef(performance.now())
    const doneRef = useRef(false)
    const answersRef = useRef<QuizAnswer[]>([])
    const [elapsed, setElapsed] = useState(0)
    const [index, setIndex] = useState(0)

    useEffect(() => {
        let raf: number
        function tick() {
            setElapsed(performance.now() - startRef.current)
            raf = requestAnimationFrame(tick)
        }
        raf = requestAnimationFrame(tick)
        return () => cancelAnimationFrame(raf)
    }, [])

    function finish(answers: QuizAnswer[]) {
        if (doneRef.current) return
        doneRef.current = true
        respond({ answers })
    }

    function cancel() {
        if (doneRef.current) return
        doneRef.current = true
        respond({ cancelled: true })
    }

    useEffect(() => {
        if (elapsed >= timeLimit) finish(answersRef.current)
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [elapsed, timeLimit])

    function choose(option: string) {
        if (doneRef.current || index >= puzzle.questions.length) return
        const now = performance.now() - startRef.current
        answersRef.current = [...answersRef.current, { choice: option, elapsed: now }]

        if (index + 1 >= puzzle.questions.length) {
            finish(answersRef.current)
        } else {
            setIndex(index + 1)
        }
    }

    const question = puzzle.questions[index]

    return (
        <Dialog open onOpenChange={(open) => { if (!open) cancel() }}>
            <DialogContent hideClose className="max-w-md">
                <DialogHeader>
                    <DialogTitle>
                        Quiz &mdash; attempt {attempt} of {attempts}
                    </DialogTitle>
                </DialogHeader>

                {lastResult === "fail" && (
                    <p className="text-sm text-destructive">Last attempt failed &mdash; try again.</p>
                )}

                <p className="text-xs text-muted-foreground">
                    Question {question.numb} of {puzzle.questions.length}
                </p>
                <p className="text-sm font-medium text-foreground">{question.question}</p>

                <div className="grid gap-2">
                    {question.options.map((option) => (
                        <Button key={option} variant="secondary" onClick={() => choose(option)}>
                            {option}
                        </Button>
                    ))}
                </div>

                <p className="text-xs text-muted-foreground">Press <span className="font-medium text-foreground">Esc</span> to cancel.</p>
            </DialogContent>
        </Dialog>
    )
}
