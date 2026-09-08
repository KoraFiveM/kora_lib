import { useState } from "react"

import { resolveIcon } from "@/lib/icon"
import type { TextUiPayload } from "@/lib/types"
import { useNuiEvent } from "@/lib/useNuiEvent"

const positionClasses: Record<TextUiPayload["position"], string> = {
    "left-center": "left-6 top-1/2 -translate-y-1/2",
    "right-center": "right-6 top-1/2 -translate-y-1/2",
    "top-center": "left-1/2 top-6 -translate-x-1/2",
    "bottom-center": "bottom-24 left-1/2 -translate-x-1/2",
}

/** Display-only QB.textui prompt. It never takes pointer or keyboard focus. */
export function TextUi() {
    const [state, setState] = useState<TextUiPayload | null>(null)

    useNuiEvent<TextUiPayload | false>("textui:set", (payload) => {
        if (
            !payload ||
            typeof payload.id !== "number" ||
            typeof payload.text !== "string" ||
            !Object.hasOwn(positionClasses, payload.position)
        ) {
            setState(null)
            return
        }

        setState(payload)
    })

    if (!state) return null
    const Icon = resolveIcon(state.icon)

    return (
        <div
            className={`pointer-events-none fixed z-hud max-w-[calc(100vw-3rem)] select-none ${positionClasses[state.position]}`}
            role="status"
            aria-live="polite"
        >
            <div className="hud-chip overlay-text flex min-h-11 items-center gap-2 px-3 py-2 text-card-foreground">
                {state.key && (
                    <kbd className="flex min-h-7 min-w-7 shrink-0 items-center justify-center rounded-md border border-brand-border bg-brand-soft px-1.5 font-mono text-xs font-bold text-foreground">
                        {state.key}
                    </kbd>
                )}
                {!state.key && Icon && <Icon aria-hidden className="h-4 w-4 shrink-0 text-primary" />}
                {state.key && Icon && <Icon aria-hidden className="h-4 w-4 shrink-0 text-muted-foreground" />}
                <span className="max-w-sm whitespace-pre-line text-sm font-medium leading-5">{state.text}</span>
            </div>
        </div>
    )
}
