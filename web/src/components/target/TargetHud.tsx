import { useState } from "react"

import type { TargetHudPayload } from "@/lib/types"
import { useNuiEvent } from "@/lib/useNuiEvent"

/**
 * Display-only presentation for kora_target. Lua remains responsible for every
 * target decision and all game controls; this stays pointer-transparent and
 * never asks for NUI focus, so aiming remains completely native.
 */
export function TargetHud() {
    const [state, setState] = useState<TargetHudPayload | null>(null)

    useNuiEvent<TargetHudPayload>("kora_target:target", (payload) => {
        if (!payload?.active) {
            setState(null)
            return
        }

        setState({
            active: true,
            label: typeof payload.label === "string" ? payload.label : undefined,
            optionCount: typeof payload.optionCount === "number" ? payload.optionCount : 0,
        })
    })

    if (!state) return null

    return (
        <div className="pointer-events-none fixed inset-0 z-hud select-none" aria-hidden="true">
            <div
                className={`absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 target-reticle ${state.label ? "target-reticle-active" : ""}`}
            >
                <span className="target-reticle-dot" />
            </div>
            {state.label && (
                <div className="target-prompt overlay-text absolute left-1/2 top-[calc(50%+3rem)] min-w-36 max-w-64 -translate-x-1/2 px-3 py-2 text-center">
                    <p className="truncate text-sm font-semibold text-foreground">{state.label}</p>
                    <p className="mt-0.5 text-xs text-muted-foreground">
                        {state.optionCount && state.optionCount > 1 ? "Release Alt to choose" : "Release Alt to interact"}
                    </p>
                </div>
            )}
        </div>
    )
}
