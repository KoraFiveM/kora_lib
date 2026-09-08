import { useCallback, useEffect, useRef, useState, type CSSProperties } from "react"

import { cn } from "@/lib/cn"
import { resolveIcon } from "@/lib/icon"
import { iconAnimationClass } from "@/lib/iconAnimation"
import type { NotifyPayload, NotifyPosition, NotifyType } from "@/lib/types"
import { useNuiEvent } from "@/lib/useNuiEvent"
import { Markdown } from "@/components/ui/markdown"

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
    "center-left": "left-4 top-1/2 -translate-y-1/2 flex-col items-start",
    "center-right": "right-4 top-1/2 -translate-y-1/2 flex-col items-end",
    top: "left-1/2 top-4 -translate-x-1/2 flex-col items-center",
    bottom: "bottom-4 left-1/2 -translate-x-1/2 flex-col-reverse items-center",
}

const ENTER_ANIMATION: Record<NotifyPosition, string> = {
    "top-left": "slide-in-from-left-2",
    "top-center": "slide-in-from-top-2",
    "top-right": "slide-in-from-right-2",
    "bottom-left": "slide-in-from-left-2",
    "bottom-center": "slide-in-from-bottom-2",
    "bottom-right": "slide-in-from-right-2",
    "center-left": "slide-in-from-left-2",
    "center-right": "slide-in-from-right-2",
    top: "slide-in-from-top-2",
    bottom: "slide-in-from-bottom-2",
}

interface ToastEntry {
    id: number | string
    title?: string
    message?: string
    duration: number
    type: NotifyType
    position: NotifyPosition
    icon?: string
    iconColor?: string
    iconAnimation?: NotifyPayload["iconAnimation"]
    alignIcon?: NotifyPayload["alignIcon"]
    style?: Record<string, string | number>
    titleStyle?: Record<string, string | number>
    messageStyle?: Record<string, string | number>
    showDuration?: boolean
}

let nextToastId = 0

function isNotifyType(value: unknown): value is NotifyType {
    return typeof value === "string" && value in TYPE_STYLES
}

function isNotifyPosition(value: unknown): value is NotifyPosition {
    return typeof value === "string" && value in POSITION_STYLES
}

function scalarStyles(value: unknown): Record<string, string | number> | undefined {
    if (!value || typeof value !== "object") return undefined
    const styles = Object.fromEntries(Object.entries(value).filter(([key, entry]) => key !== "pointerEvents" && (typeof entry === "string" || typeof entry === "number")))
    return Object.keys(styles).length ? styles : undefined
}

function notifyStyles(value: unknown) {
    const root = scalarStyles(value)
    let title: Record<string, string | number> | undefined
    let message: Record<string, string | number> | undefined
    if (value && typeof value === "object") {
        for (const [selector, styles] of Object.entries(value)) {
            const normalized = selector.toLowerCase().replace(/^&\s*/, "").replace(/^\./, "")
            if (normalized === "title") title = scalarStyles(styles)
            if (normalized === "description" || normalized === "message" || normalized === "text") message = scalarStyles(styles)
        }
    }
    return { root, title, message }
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
    const timeoutsRef = useRef<Map<number | string, ReturnType<typeof setTimeout>>>(new Map())

    const clearToastTimeout = useCallback((id: number | string) => {
        const timeout = timeoutsRef.current.get(id)
        if (timeout) {
            clearTimeout(timeout)
            timeoutsRef.current.delete(id)
        }
    }, [])

    const dismiss = useCallback(
        (id: number | string) => {
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

        const hasId = typeof payload.id === "number" || (typeof payload.id === "string" && payload.id !== "")
        const id = hasId ? payload.id! : nextToastId++
        const duration = typeof payload.duration === "number"
            && Number.isFinite(payload.duration)
            && payload.duration > 0
            ? payload.duration
            : DEFAULT_DURATION

        const styles = notifyStyles(payload.style)
        const entry: ToastEntry = {
            id,
            title,
            message,
            duration,
            type: isNotifyType(payload.type) ? payload.type : DEFAULT_TYPE,
            position: isNotifyPosition(payload.position) ? payload.position : DEFAULT_POSITION,
            icon: typeof payload.icon === "string" ? payload.icon : undefined,
            iconColor: typeof payload.iconColor === "string" ? payload.iconColor : undefined,
            iconAnimation: payload.iconAnimation,
            alignIcon: payload.alignIcon,
            style: styles.root,
            titleStyle: styles.title,
            messageStyle: styles.message,
            showDuration: payload.showDuration,
        }

        clearToastTimeout(id)
        setToasts((prev) => {
            const existingIndex = prev.findIndex((toast) => toast.id === id)
            const next = existingIndex === -1
                ? [...prev, entry]
                : prev.map((toast, index) => index === existingIndex ? entry : toast)
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
            style={{ ...toast.style, "--toast-duration": `${toast.duration}ms` } as CSSProperties}
            className={cn(
                "animate-in fade-in-0 relative flex w-full gap-2 overflow-hidden rounded-lg border border-l-4 bg-popover p-3 shadow-floating duration-popover ease-entry",
                ENTER_ANIMATION[toast.position],
                variant.accent,
            )}
        >
            {Icon ? (
                <span className={cn("inline-flex h-6 w-6 shrink-0 items-center justify-center rounded-md", toast.alignIcon === "top" ? "self-start" : "self-center", variant.chip)}>
                    <Icon aria-hidden className={cn("h-4 w-4", iconAnimationClass(toast.iconAnimation))} style={{ color: toast.iconColor }} />
                </span>
            ) : null}
            <div className="min-w-0 flex-1 text-popover-foreground">
                {toast.title && <p className="text-sm font-semibold leading-tight" style={toast.titleStyle as CSSProperties}>{toast.title}</p>}
                {toast.message && (
                    <Markdown className={cn("break-words text-xs text-muted-foreground", toast.title && "mt-1")} style={toast.messageStyle as CSSProperties}>{toast.message}</Markdown>
                )}
            </div>
            {toast.showDuration !== false ? <span
                aria-hidden
                className={cn("toast-lifetime absolute bottom-0 left-0 h-px w-full", variant.progress)}
            /> : null}
        </div>
    )
}
