import { useCallback, useEffect, useRef, useState, type CSSProperties } from "react"

import type { ProgressStartPayload } from "@/lib/types"
import { useNuiEvent } from "@/lib/useNuiEvent"

interface ProgressState {
    id: number
    label: string
    duration: number
    presentation: "bar" | "circle"
    position: "middle" | "bottom"
}

let nextProgressId = 0

/**
 * Renders Kora.progressbar.start's "progressStart"/"progressCancel" messages
 * (see modules/progressbar/) as a bottom-center filling bar. Lua owns the
 * real timing -- disabling controls, detecting cancellation, deciding
 * completed vs cancelled -- entirely on its own per-frame poll; this
 * component is purely the visual, filling over `duration` ms via CSS and
 * hiding itself either when that finishes or when "progressCancel" arrives
 * early. Always mounted, stays pointer-events-none the whole time it's
 * visible -- never interactive, same as Toast.
 */
export function ProgressBar() {
    const [state, setState] = useState<ProgressState | null>(null)
    const timeoutRef = useRef<ReturnType<typeof setTimeout>>()
    const progressRef = useRef<HTMLDivElement>(null)

    const clearPending = useCallback(() => {
        if (timeoutRef.current) {
            clearTimeout(timeoutRef.current)
            timeoutRef.current = undefined
        }
    }, [])

    useNuiEvent<ProgressStartPayload>("progressStart", (payload) => {
        // Normalized on ingestion, same reasoning as Toast: Lua's own
        // validation (modules/progressbar/client.lua's assertPayload)
        // guarantees these are well-formed in practice, but any resource can
        // post straight to this action, and a non-string/non-positive value
        // must not become an invalid render or a bar that never disappears.
        const label = typeof payload?.label === "string" ? payload.label : ""
        const duration = typeof payload?.duration === "number" && payload.duration > 0 ? payload.duration : 0
        if (!duration) return

        clearPending()

        const id = nextProgressId++
        setState({
            id,
            label,
            duration,
            presentation: payload.presentation === "circle" ? "circle" : "bar",
            position: payload.position === "bottom" ? "bottom" : "middle",
        })
        timeoutRef.current = setTimeout(() => {
            setState((prev) => (prev?.id === id ? null : prev))
        }, duration)
    })

    useNuiEvent("progressCancel", () => {
        clearPending()
        setState(null)
    })

    useEffect(() => clearPending, [clearPending])

    useEffect(() => {
        if (!state) return
        const startedAt = performance.now()
        const updateAccessibleProgress = () => {
            const elapsed = Math.min(state.duration, Math.max(0, performance.now() - startedAt))
            progressRef.current?.setAttribute("aria-valuenow", String(Math.round(elapsed)))
        }
        updateAccessibleProgress()
        const interval = window.setInterval(updateAccessibleProgress, 250)
        return () => window.clearInterval(interval)
    }, [state])

    if (!state) return null

    if (state.presentation === "circle") {
        const placement = state.position === "bottom" ? "bottom-20" : "top-1/2 -translate-y-1/2"
        return (
            <div className={`pointer-events-none fixed left-1/2 z-hud -translate-x-1/2 select-none ${placement}`}>
                <div className="hud-chip overlay-text flex min-w-28 flex-col items-center gap-2 px-4 py-3">
                    <div
                        ref={progressRef}
                        className="relative h-16 w-16"
                        role="progressbar"
                        aria-label={state.label || "Progress"}
                        aria-valuemin={0}
                        aria-valuemax={state.duration}
                        aria-valuenow={0}
                    >
                        <svg viewBox="0 0 64 64" className="h-full w-full -rotate-90" aria-hidden>
                            <circle cx="32" cy="32" r="27" fill="none" stroke="hsl(var(--muted))" strokeWidth="6" />
                            <circle
                                key={state.id}
                                cx="32"
                                cy="32"
                                r="27"
                                fill="none"
                                stroke="hsl(var(--primary))"
                                strokeWidth="6"
                                strokeLinecap="round"
                                strokeDasharray="169.65"
                                style={{ "--progress-duration": `${state.duration}ms` } as CSSProperties}
                                className="progress-circle"
                            />
                        </svg>
                    </div>
                    {state.label && <p className="max-w-48 truncate text-center text-xs font-medium text-foreground">{state.label}</p>}
                </div>
            </div>
        )
    }

    return (
        <div className="pointer-events-none fixed bottom-24 left-1/2 z-hud w-72 max-w-[calc(100vw-2rem)] -translate-x-1/2 select-none">
            <div className="hud-chip overlay-text px-3 py-2">
                {state.label && (
                    <p className="mb-1.5 truncate text-center text-xs font-medium text-foreground">{state.label}</p>
                )}
                <div
                    ref={progressRef}
                    className="h-1.5 w-full overflow-hidden rounded-full bg-muted"
                    role="progressbar"
                    aria-label={state.label || "Progress"}
                    aria-valuemin={0}
                    aria-valuemax={state.duration}
                    aria-valuenow={0}
                >
                    <div
                        key={state.id}
                        style={{ "--progress-duration": `${state.duration}ms` } as CSSProperties}
                        className="progress-fill h-full rounded-full bg-primary"
                    />
                </div>
            </div>
        </div>
    )
}
