import { useState } from "react"

import type { TargetSelectPayload } from "@/lib/types"
import { useNuiEvent } from "@/lib/useNuiEvent"

/**
 * Compact candidate picker for qbtarget, shown when more than one option is
 * available under the reticle. Visually mirrors InteractSelect (same
 * scroll-to-cycle, E-to-confirm shape) but is its own component/action name:
 * qbtarget drives cycling/confirm/cancel entirely through its own control
 * polling in client/loop.lua and already knows the active index, so unlike
 * InteractSelect there is no selectOption callback round trip here -- this
 * stays pointer-transparent and never requests NUI focus, same as TargetHud.
 */
export function TargetSelect() {
    const [state, setState] = useState<TargetSelectPayload | null>(null)

    useNuiEvent<TargetSelectPayload>("qbtarget:select", (payload) => {
        if (!payload?.active || !Array.isArray(payload.items) || payload.items.length === 0) {
            setState(null)
            return
        }

        setState(payload)
    })

    if (!state?.items) return null

    return (
        <div
            className="pointer-events-none fixed bottom-[2vh] left-1/2 z-hud w-64 max-w-[calc(100vw-2rem)] -translate-x-1/2 select-none rounded-xl border bg-hud p-2 text-card-foreground shadow-low"
            aria-hidden="true"
        >
            {state.items.map((item, index) => {
                const selected = index === state.activeIndex

                return (
                    <div
                        key={`${item.label}-${index}`}
                        className={`relative my-1 flex min-h-10 items-center rounded-md px-3 py-2 text-sm transition-colors duration-fast ${selected ? "bg-brand-soft text-foreground before:absolute before:bottom-1.5 before:left-0 before:top-1.5 before:w-0.5 before:rounded-full before:bg-primary" : "text-muted-foreground"}`}
                    >
                        {selected && (
                            <span className="mr-2 flex h-7 w-7 shrink-0 items-center justify-center rounded-md bg-primary text-xs font-bold text-primary-foreground">
                                E
                            </span>
                        )}
                        <span className="min-w-0 truncate font-medium">{item.label}</span>
                    </div>
                )
            })}
        </div>
    )
}
