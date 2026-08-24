import { useCallback, useRef, useState } from "react"

import { fetchNui } from "@/lib/fetchNui"
import type { InteractOpenPayload } from "@/lib/types"
import { useNuiEvent } from "@/lib/useNuiEvent"

interface InteractState {
    options: InteractOpenPayload
    selectedIndex: number
}

/**
 * Visual half of QB.interact. Lua owns all controls and selection dispatch;
 * this component is deliberately pointer-transparent so it cannot take mouse
 * look or NUI focus from gameplay.
 */
export function InteractSelect() {
    const [state, setState] = useState<InteractState | null>(null)
    const submittingRef = useRef(false)

    useNuiEvent<InteractOpenPayload>("openInteract", (payload) => {
        const options = Array.isArray(payload)
            ? payload.filter((option): option is { label: string } => typeof option?.label === "string" && option.label.length > 0)
            : []

        submittingRef.current = false
        setState(options.length > 0 ? { options, selectedIndex: 0 } : null)
    })

    useNuiEvent<number>("scroll", (direction) => {
        if (direction !== 1 && direction !== -1) return

        setState((previous) => {
            if (!previous || previous.options.length === 0) return previous
            const selectedIndex = (previous.selectedIndex + direction + previous.options.length) % previous.options.length
            return { ...previous, selectedIndex }
        })
    })

    const select = useCallback(() => {
        if (!state || submittingRef.current) return

        submittingRef.current = true
        void fetchNui("selectOption", state.selectedIndex + 1)
            .then(() => setState(null))
            .catch((error) => {
                submittingRef.current = false
                console.error("[qblib] interact selection failed:", error)
            })
    }, [state])

    useNuiEvent("select", select)
    useNuiEvent("hideInteract", () => {
        submittingRef.current = false
        setState(null)
    })

    if (!state) return null

    // qbhud owns the bottom-centre gauge/vehicle stack in a separate NUI page,
    // so keep this selector above that reserved gameplay-HUD band.
    return (
        <div className="pointer-events-none fixed bottom-36 left-1/2 z-hud w-64 max-w-[calc(100vw-2rem)] -translate-x-1/2 select-none rounded-xl border bg-hud p-2 text-card-foreground shadow-low">
            {state.options.map((option, index) => {
                const selected = index === state.selectedIndex

                return (
                    <div
                        key={`${option.label}-${index}`}
                        className={`relative my-1 flex min-h-10 items-center rounded-md px-3 py-2 text-sm transition-colors duration-fast ${selected ? "bg-brand-soft text-foreground before:absolute before:bottom-1.5 before:left-0 before:top-1.5 before:w-0.5 before:rounded-full before:bg-primary" : "text-muted-foreground"}`}
                    >
                        {selected && (
                            <span className="mr-2 flex h-7 w-7 shrink-0 items-center justify-center rounded-md bg-primary text-xs font-bold text-primary-foreground">
                                E
                            </span>
                        )}
                        <span className="min-w-0 truncate font-medium">{option.label}</span>
                    </div>
                )
            })}
        </div>
    )
}
