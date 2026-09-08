import { useState, type CSSProperties } from "react"

import { cn } from "@/lib/cn"
import { isIconImage, resolveIcon } from "@/lib/icon"
import { iconAnimationClass } from "@/lib/iconAnimation"
import type { TextUiPayload } from "@/lib/types"
import { useNuiEvent } from "@/lib/useNuiEvent"
import { Markdown } from "@/components/ui/markdown"

const positionClasses: Record<TextUiPayload["position"], string> = {
    "left-center": "left-6 top-1/2 -translate-y-1/2",
    "right-center": "right-6 top-1/2 -translate-y-1/2",
    "top-center": "left-1/2 top-6 -translate-x-1/2",
    "bottom-center": "bottom-24 left-1/2 -translate-x-1/2",
}

function camelCaseCssProperty(property: string): string {
    if (property.startsWith("--")) return property
    return property
        .replace(/^-ms-/, "ms-")
        .replace(/-([a-z])/g, (_match, letter: string) => letter.toUpperCase())
}

/**
 * Converts legacy CSS declaration strings through the browser's own inline
 * style parser. Assigning only to `style.cssText` means selectors and global
 * stylesheet rules cannot escape onto the page.
 */
function scopedStyle(style: TextUiPayload["style"]): Record<string, string | number> | undefined {
    if (typeof style === "string") {
        const probe = document.createElement("div")
        probe.style.cssText = style
        const parsed: Record<string, string> = {}
        for (let index = 0; index < probe.style.length; index += 1) {
            const property = probe.style.item(index)
            if (!property || property.toLowerCase() === "pointer-events") continue
            parsed[camelCaseCssProperty(property)] = probe.style.getPropertyValue(property)
        }
        return parsed
    }
    if (!style || typeof style !== "object") return undefined
    return Object.fromEntries(Object.entries(style).filter(([key, value]) => key !== "pointerEvents" && key !== "pointer-events" && (typeof value === "string" || typeof value === "number")))
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

        setState({ ...payload, style: scopedStyle(payload.style) })
    })

    if (!state) return null
    const iconIsImage = isIconImage(state.icon)
    const Icon = iconIsImage ? undefined : resolveIcon(state.icon)
    const iconClassName = cn(
        "h-4 w-4 shrink-0",
        state.key ? "text-muted-foreground" : "text-primary",
        state.alignIcon === "top" ? "self-start mt-0.5" : "self-center",
        iconAnimationClass(state.iconAnimation),
    )

    return (
        <div
            className={`pointer-events-none fixed z-hud max-w-[calc(100vw-3rem)] select-none ${positionClasses[state.position]}`}
            role="status"
            aria-live="polite"
        >
            <div style={state.style as CSSProperties} className="hud-chip overlay-text flex min-h-11 items-center gap-2 px-3 py-2 text-card-foreground">
                {state.key && (
                    <kbd className="flex min-h-7 min-w-7 shrink-0 items-center justify-center rounded-md border border-brand-border bg-brand-soft px-1.5 font-mono text-xs font-bold text-foreground">
                        {state.key}
                    </kbd>
                )}
                {iconIsImage ? <img aria-hidden src={state.icon} className={cn("h-4 w-4 shrink-0 object-contain", state.alignIcon === "top" ? "self-start mt-0.5" : "self-center")} /> : Icon ? <Icon aria-hidden className={iconClassName} style={{ color: state.iconColor }} /> : null}
                <Markdown className="max-w-sm text-sm font-medium leading-5" allowImages>{state.text}</Markdown>
            </div>
        </div>
    )
}
