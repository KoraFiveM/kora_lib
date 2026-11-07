import { useCallback, useRef, useState } from "react"

import { fetchNui } from "@/lib/fetchNui"
import { resolveIcon } from "@/lib/icon"
import type { InteractOpenPayload, InteractOption } from "@/lib/types"
import { useNuiEvent } from "@/lib/useNuiEvent"

interface InteractState {
    options: InteractOpenPayload
    selectedIndex: number
}

/**
 * Visual half of Kora.interact. Lua owns all controls and selection dispatch;
 * this component is deliberately pointer-transparent so it cannot take mouse
 * look or NUI focus from gameplay.
 */
export function InteractSelect() {
    const [state, setState] = useState<InteractState | null>(null)
    const submittingRef = useRef(false)

    useNuiEvent<InteractOpenPayload>("openInteract", (payload) => {
        const options = Array.isArray(payload)
            ? payload.filter((option): option is InteractOption => typeof option?.label === "string" && option.label.length > 0)
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
                console.error("[kora_lib] interact selection failed:", error)
            })
    }, [state])

    useNuiEvent("select", select)
    useNuiEvent("hideInteract", () => {
        submittingRef.current = false
        setState(null)
    })

    if (!state) return null

    // kora_hud owns the bottom-centre gauge/vehicle stack in a separate NUI page,
    // so keep this selector above that reserved gameplay-HUD band.
    //
    // One panel and one row per option. The selected row is a brand-soft fill with
    // the key hint at its right; an option's icon, when it resolves, sits left of
    // the label.
    return (
        <div className="pointer-events-none fixed bottom-36 left-1/2 z-hud grid w-64 max-w-[calc(100vw-2rem)] -translate-x-1/2 select-none gap-0.5 rounded-lg bg-popover p-1.5 text-card-foreground shadow-floating">
            {state.options.map((option, index) => {
                const selected = index === state.selectedIndex
                const Icon = resolveIcon(option.icon)

                return (
                    <div
                        key={`${option.label}-${index}`}
                        className={`flex min-h-9 items-center gap-2.5 rounded-sm px-2.5 py-1.5 text-sm transition-colors duration-fast ${selected ? "bg-brand-soft text-foreground" : "text-muted-foreground"}`}
                    >
                        {Icon ? <Icon aria-hidden className="h-4 w-4 shrink-0" /> : null}
                        {/* The label keeps its own element: `truncate` is
                            text-overflow, which does not apply to a bare text
                            node inside a flex container. Removing this span
                            would let a long option overflow the panel instead
                            of ellipsising. */}
                        <span className="min-w-0 flex-1 truncate font-medium">{option.label}</span>
                        {selected ? <kbd className="shrink-0 rounded-sm bg-surface-hover px-1.5 py-0.5 font-mono text-xs text-muted-foreground">E</kbd> : null}
                    </div>
                )
            })}
        </div>
    )
}
