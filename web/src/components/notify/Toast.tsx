import { useCallback, useEffect, useRef, useState, type CSSProperties } from "react"

import { cn } from "@/lib/cn"
import { resolveIcon } from "@/lib/icon"
import type { NotifyPayload, NotifyPosition, NotifyType } from "@/lib/types"
import { useNuiEvent } from "@/lib/useNuiEvent"

// Lua's QB.notify.send resolves these from Config.notify before sending, but
// this component must stay renderable from a bare payload too -- any resource
// can post straight to the "notify" action.
const DEFAULT_DURATION = 5000
const DEFAULT_TYPE: NotifyType = "info"
const DEFAULT_POSITION: NotifyPosition = "top-right"

// Oldest toasts are dropped past this, so a notify-spamming caller degrades
// to a rotating stack instead of unbounded DOM growth. Counted across all
// positions: the cap exists to bound total DOM, not per-corner density.
const MAX_TOASTS = 6

const TYPE_STYLES: Record<NotifyType, { accent: string; icon: string; chip: string; progress: string }> = {
    info: { accent: "border-l-info", icon: "Info", chip: "bg-info/10 text-info", progress: "bg-info" },
    success: { accent: "border-l-success", icon: "CheckCircle", chip: "bg-success/10 text-success", progress: "bg-success" },
    warning: { accent: "border-l-warning", icon: "AlertTriangle", chip: "bg-warning/10 text-warning", progress: "bg-warning" },
    error: { accent: "border-l-destructive", icon: "AlertCircle", chip: "bg-destructive/10 text-destructive", progress: "bg-destructive" },
}

// Anchor + stack direction per position. Newest toast renders last in the
// array, so bottom-anchored stacks reverse to keep the newest nearest the edge.
const POSITION_STYLES: Record<NotifyPosition, string> = {
    "top-left": "left-4 top-4 flex-col items-start",
    "top-center": "left-1/2 top-4 -translate-x-1/2 flex-col items-center",
    "top-right": "right-4 top-4 flex-col items-end",
    "bottom-left": "bottom-4 left-4 flex-col-reverse items-start",
    "bottom-center": "bottom-4 left-1/2 -translate-x-1/2 flex-col-reverse items-center",
    "bottom-right": "bottom-4 right-4 flex-col-reverse items-end",
}

const ENTER_ANIMATION: Record<NotifyPosition, string> = {
    "top-left": "slide-in-from-left-2",
    "top-center": "slide-in-from-top-2",
    "top-right": "slide-in-from-right-2",
    "bottom-left": "slide-in-from-left-2",
    "bottom-center": "slide-in-from-bottom-2",
    "bottom-right": "slide-in-from-right-2",
}

interface ToastEntry {
    id: number
    title?: string
    message?: string
    duration: number
    type: NotifyType
    position: NotifyPosition
    icon?: string
}

let nextToastId = 0

function isNotifyType(value: unknown): value is NotifyType {
    return typeof value === "string" && value in TYPE_STYLES
}

function isNotifyPosition(value: unknown): value is NotifyPosition {
    return typeof value === "string" && value in POSITION_STYLES
}

/**
 * Renders QB.notify.send's "notify" messages (see modules/notify/) as
 * auto-dismissing toasts, grouped into one stack per requested screen
 * position. Always mounted; stays pointer-events-none the whole time it's
 * visible -- notifications are informational only, never interactive, so they
 * must never be able to steal a click/key from the game.
 */
export function Toast() {
    const [toasts, setToasts] = useState<ToastEntry[]>([])
    const timeoutsRef = useRef<Map<number, ReturnType<typeof setTimeout>>>(new Map())

    const clearToastTimeout = useCallback((id: number) => {
        const timeout = timeoutsRef.current.get(id)
        if (timeout) {
            clearTimeout(timeout)
            timeoutsRef.current.delete(id)
        }
    }, [])

    const dismiss = useCallback(
        (id: number) => {
            setToasts((prev) => prev.filter((toast) => toast.id !== id))
            clearToastTimeout(id)
        },
        [clearToastTimeout],
    )

    useNuiEvent<NotifyPayload>("notify", (payload) => {
        // Normalized on ingestion: QB.notify.assert type-checks these Lua-side,
        // but this component must not be crashable by a raw QB.nui.send from
        // some other caller -- a non-string field renders as nothing rather
        // than becoming an invalid React child that unmounts the whole root.
        const title = typeof payload.title === "string" ? payload.title : undefined
        const message = typeof payload.message === "string" ? payload.message : undefined
        if (!title && !message) return

        const id = nextToastId++
        const duration = typeof payload.duration === "number"
            && Number.isFinite(payload.duration)
            && payload.duration > 0
            ? payload.duration
            : DEFAULT_DURATION

        const entry: ToastEntry = {
            id,
            title,
            message,
            duration,
            type: isNotifyType(payload.type) ? payload.type : DEFAULT_TYPE,
            position: isNotifyPosition(payload.position) ? payload.position : DEFAULT_POSITION,
            icon: typeof payload.icon === "string" ? payload.icon : undefined,
        }

        setToasts((prev) => {
            const next = [...prev, entry]
            const overflow = Math.max(0, next.length - MAX_TOASTS)

            for (const dropped of next.slice(0, overflow)) clearToastTimeout(dropped.id)

            return next.slice(overflow)
        })
        timeoutsRef.current.set(id, setTimeout(() => dismiss(id), duration))
    })

    // Clear every pending auto-dismiss timer on unmount so none of them fire
    // (and call setState) after the component's gone.
    useEffect(() => {
        const timeouts = timeoutsRef.current
        return () => {
            timeouts.forEach((timeout) => clearTimeout(timeout))
            timeouts.clear()
        }
    }, [])

    if (toasts.length === 0) return null

    const byPosition = new Map<NotifyPosition, ToastEntry[]>()
    for (const toast of toasts) {
        const stack = byPosition.get(toast.position)
        if (stack) stack.push(toast)
        else byPosition.set(toast.position, [toast])
    }

    return (
        <>
            {[...byPosition].map(([position, stack]) => (
                <div
                    key={position}
                    className={cn(
                        "pointer-events-none fixed z-overlay flex w-80 max-w-[calc(100vw-2rem)] gap-2",
                        POSITION_STYLES[position],
                    )}
                >
                    {stack.map((toast) => (
                        <ToastCard key={toast.id} toast={toast} />
                    ))}
                </div>
            ))}
        </>
    )
}

function ToastCard({ toast }: { toast: ToastEntry }) {
    const variant = TYPE_STYLES[toast.type]
    const Icon = resolveIcon(toast.icon ?? variant.icon)

    return (
        <div
            role={toast.type === "error" ? "alert" : "status"}
            aria-live={toast.type === "error" ? undefined : "polite"}
            aria-atomic="true"
            style={{ "--toast-duration": `${toast.duration}ms` } as CSSProperties}
            className={cn(
                "animate-in fade-in-0 relative flex w-full gap-2 overflow-hidden rounded-lg border border-l-4 bg-popover p-3 shadow-floating duration-popover ease-entry",
                ENTER_ANIMATION[toast.position],
                variant.accent,
            )}
        >
            {Icon ? (
                <span className={cn("mt-0.5 inline-flex h-6 w-6 shrink-0 items-center justify-center rounded-md", variant.chip)}>
                    <Icon aria-hidden className="h-4 w-4" />
                </span>
            ) : null}
            <div className="min-w-0 flex-1 text-popover-foreground">
                {toast.title && <p className="text-sm font-semibold leading-tight">{toast.title}</p>}
                {toast.message && (
                    <p className={cn("break-words text-xs text-muted-foreground", toast.title && "mt-1")}>
                        {toast.message}
                    </p>
                )}
            </div>
            <span
                aria-hidden
                className={cn("toast-lifetime absolute bottom-0 left-0 h-px w-full", variant.progress)}
            />
        </div>
    )
}
