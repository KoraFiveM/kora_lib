import { useCallback, useEffect, useRef, useState, type CSSProperties } from "react"

import type { ProgressStartPayload } from "@/lib/types"
import { useNuiEvent } from "@/lib/useNuiEvent"

interface ProgressState {
    id: number
    label: string
    duration: number
}

let nextProgressId = 0

/**
 * Renders QB.progressbar.start's "progressStart"/"progressCancel" messages
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
        setState({ id, label, duration })
        // Self-dismissing, same idiom as Toast's auto-dismiss timer -- Lua's
        // own poll loop is timed to the same duration, so this is purely the
        // visual finishing in step with it, not a second source of truth.
        timeoutRef.current = setTimeout(() => {
            setState((prev) => (prev?.id === id ? null : prev))
        }, duration)
    })

    useNuiEvent("progressCancel", () => {
        clearPending()
        setState(null)
    })

    useEffect(() => clearPending, [clearPending])

    if (!state) return null

    return (
        <div className="pointer-events-none fixed bottom-24 left-1/2 z-hud w-72 max-w-[calc(100vw-2rem)] -translate-x-1/2 select-none">
            <div className="hud-chip overlay-text px-3 py-2">
                {state.label && (
                    <p className="mb-1.5 truncate text-center text-xs font-medium text-foreground">{state.label}</p>
                )}
                <div className="h-1.5 w-full overflow-hidden rounded-full bg-muted">
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
