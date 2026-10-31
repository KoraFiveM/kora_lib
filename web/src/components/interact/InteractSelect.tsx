import { useCallback, useRef, useState } from "react"

import { fetchNui } from "@/lib/fetchNui"
import type { InteractOpenPayload } from "@/lib/types"
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
    // Two elements deep, and deliberately no deeper: the panel, and one row per
    // option. The selected row's "E" key chip is the row's own `::before`
    // pseudo-element rather than a nested <span>, and the accent bar is a left
    // border rather than a second absolutely-positioned one -- three layers of
    // boxed chrome (panel, row, badge) around one line of text read as a stack
    // of panels rather than a menu.
    return (
        <div className="pointer-events-none fixed bottom-36 left-1/2 z-hud w-64 max-w-[calc(100vw-2rem)] -translate-x-1/2 select-none rounded-xl border bg-hud p-2 text-card-foreground shadow-low">
            {state.options.map((option, index) => {
                const selected = index === state.selectedIndex

                return (
                    <div
                        key={`${option.label}-${index}`}
                        className={`my-1 flex min-h-10 items-center rounded-md border-l-2 px-3 py-2 text-sm transition-colors duration-fast ${selected ? "border-primary bg-brand-soft text-foreground before:mr-2 before:flex before:h-7 before:w-7 before:shrink-0 before:items-center before:justify-center before:rounded-md before:bg-primary before:text-xs before:font-bold before:text-primary-foreground before:content-['E']" : "border-transparent text-muted-foreground"}`}
                    >
                        {/* The label keeps its own element: `truncate` is
                            text-overflow, which does not apply to a bare text
                            node inside a flex container -- the anonymous flex
                            item it becomes is not a block box. Removing this
                            span would let a long option overflow the panel
                            instead of ellipsising. */}
                        <span className="min-w-0 truncate font-medium">{option.label}</span>
                    </div>
                )
            })}
        </div>
    )
}
