import { useEffect, useRef, useState } from "react"

import type { CancelledAttempt, CircuitAttempt, CircuitConnection, CircuitNode, CircuitPuzzle } from "@/lib/types"
import { cn } from "@/lib/cn"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"

interface CircuitGameProps {
    puzzle: CircuitPuzzle
    attempt: number
    attempts: number
    timeLimit: number
    lastResult?: "fail"
    respond: (attempt: CircuitAttempt | CancelledAttempt) => void
}

/**
 * Click an input, then the output sharing its color, to connect them --
 * correctness is inherent in the colors (see modules/minigames/server.lua's
 * generate.circuit), so there's nothing else to hide or forge. Reports the
 * connections made, with a timestamp each, once every input is connected (or
 * on timeout, whatever's connected so far).
 */
export function CircuitGame({ puzzle, attempt, attempts, timeLimit, lastResult, respond }: CircuitGameProps) {
    const startRef = useRef(performance.now())
    const doneRef = useRef(false)
    const [elapsed, setElapsed] = useState(0)
    const [selectedInput, setSelectedInput] = useState<string | null>(null)
    const [connections, setConnections] = useState<CircuitConnection[]>([])

    useEffect(() => {
        let raf: number
        function tick() {
            setElapsed(performance.now() - startRef.current)
            raf = requestAnimationFrame(tick)
        }
        raf = requestAnimationFrame(tick)
        return () => cancelAnimationFrame(raf)
    }, [])

    function finish(conns: CircuitConnection[]) {
        if (doneRef.current) return
        doneRef.current = true
        respond({ connections: conns })
    }

    function cancel() {
        if (doneRef.current) return
        doneRef.current = true
        respond({ cancelled: true })
    }

    useEffect(() => {
        if (elapsed >= timeLimit) finish(connections)
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [elapsed, timeLimit])

    const inputs = puzzle.nodes.filter((node) => node.side === "input")
    const outputs = puzzle.nodes.filter((node) => node.side === "output")
    const connectedInputs = new Set(connections.map((c) => c.from))
    const connectedOutputs = new Set(connections.map((c) => c.to))

    function handleInputClick(id: string) {
        if (connectedInputs.has(id)) return
        setSelectedInput(id)
    }

    function handleOutputClick(id: string) {
        if (!selectedInput || connectedOutputs.has(id)) return

        const next = [...connections, { from: selectedInput, to: id, elapsed: performance.now() - startRef.current }]
        setSelectedInput(null)
        setConnections(next)

        if (next.length >= inputs.length) finish(next)
    }

    return (
        <Dialog open onOpenChange={(open) => { if (!open) cancel() }}>
            <DialogContent hideClose className="max-w-md">
                <DialogHeader>
                    <DialogTitle>
                        Circuit &mdash; attempt {attempt} of {attempts}
                    </DialogTitle>
                </DialogHeader>

                {lastResult === "fail" && (
                    <p className="text-sm text-destructive">Last attempt failed &mdash; try again.</p>
                )}

                <div className="flex justify-between gap-10 px-4">
                    <div className="flex flex-col gap-3">
                        {inputs.map((node) => (
                            <NodeButton
                                key={node.id}
                                node={node}
                                selected={selectedInput === node.id}
                                connected={connectedInputs.has(node.id)}
                                onClick={() => handleInputClick(node.id)}
                            />
                        ))}
                    </div>
                    <div className="flex flex-col gap-3">
                        {outputs.map((node) => (
                            <NodeButton
                                key={node.id}
                                node={node}
                                selected={false}
                                connected={connectedOutputs.has(node.id)}
                                onClick={() => handleOutputClick(node.id)}
                            />
                        ))}
                    </div>
                </div>

                <p className="text-xs text-muted-foreground">
                    Click an input, then the output with the matching color. Press{" "}
                    <span className="font-medium text-foreground">Esc</span> to cancel.
                </p>
            </DialogContent>
        </Dialog>
    )
}

function NodeButton({
    node,
    selected,
    connected,
    onClick,
}: {
    node: CircuitNode
    selected: boolean
    connected: boolean
    onClick: () => void
}) {
    return (
        <button
            type="button"
            disabled={connected}
            onClick={onClick}
            aria-label={`${node.side} ${node.id}, color ${node.color}`}
            className={cn(
                "h-9 w-9 rounded-full border-2 border-transparent transition-[transform,box-shadow] disabled:opacity-50",
                selected && "ring-2 ring-offset-2 ring-offset-background ring-primary"
            )}
            style={{ backgroundColor: node.color }}
        />
    )
}
