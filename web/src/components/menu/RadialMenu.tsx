import { useCallback, useEffect, useMemo, useRef, useState } from "react"

import { cn } from "@/lib/cn"
import { isIconImage, resolveIcon } from "@/lib/icon"
import { iconAnimationClass } from "@/lib/iconAnimation"
import type { MenuItem, MenuResult, NuiRequestEnvelope, NuiRequestEventEnvelope, OpenRadialMenuPayload } from "@/lib/types"
import { useNuiRequest } from "@/lib/useNuiRequest"
import { useNuiEvent } from "@/lib/useNuiEvent"
import { getNuiViewport } from "@/lib/viewport"
import { fetchNui } from "@/lib/fetchNui"
import { useOxLocale } from "@/lib/oxLocale"

const MAX_RING_ITEMS = 8
const PAGE_SIZE_WITH_MORE = MAX_RING_ITEMS - 1
const DEFAULT_RADIUS = 156
const ITEM_HALF_SIZE = 42
const EDGE_GUTTER = 16
const DEFAULT_LABEL_LINES = 3
const LONG_LABEL_LENGTH = 14

function labelSizeClass(label: string): string {
    if (label.length > 26) return "text-[10px] leading-3"
    if (label.length > LONG_LABEL_LENGTH) return "text-[11px] leading-[13px]"
    return "text-xs leading-4"
}

interface Level {
    title?: string
    items: MenuItem[]
    viaId?: string
    page: number
}

type RingEntry =
    | { kind: "item"; item: MenuItem }
    | { kind: "more"; page: number; totalPages: number }

function firstEnabled(entries: RingEntry[]): number {
    return entries.findIndex((entry) => entry.kind === "more" || !entry.item.disabled)
}

function validPage(items: MenuItem[], requested = 0): number {
    if (items.length <= MAX_RING_ITEMS) return 0
    return Math.max(0, Math.min(requested, Math.ceil(items.length / PAGE_SIZE_WITH_MORE) - 1))
}

function rebuildStack(items: MenuItem[], path: string[], previous: Level[]): Level[] {
    const rebuilt: Level[] = [{ items, page: validPage(items, previous[0]?.page) }]
    let current = items
    for (let index = 0; index < path.length; index += 1) {
        const id = path[index]
        const item = current.find((entry) => entry.id === id)
        if (!item?.submenu) break
        rebuilt.push({
            title: item.submenu.title ?? item.label,
            items: item.submenu.items,
            viaId: item.id,
            page: validPage(item.submenu.items, previous[index + 1]?.page),
        })
        current = item.submenu.items
    }
    return rebuilt
}

/**
 * The visual half of Kora.nui.openRadialMenu. The whole nested tree is delivered
 * once; changing levels/pages is local React state and only a terminal choice
 * or cancellation settles the original tokenised NUI request.
 */
export function RadialMenuContainer() {
    const locale = useOxLocale()
    const [stack, setStack] = useState<Level[]>([])
    const [activeIndex, setActiveIndex] = useState(-1)
    const itemRefs = useRef<(HTMLButtonElement | null)[]>([])

    const { payload, requestId, token, isOpen, respond } = useNuiRequest<OpenRadialMenuPayload, MenuResult>(
        "openRadialMenu",
        useCallback((open: OpenRadialMenuPayload) => {
            setStack([{ items: open.items, page: 0 }])
            setActiveIndex(-1)
        }, []),
        { cancelled: true },
    )

    const level = stack[stack.length - 1]
    const canGoBack = stack.length > 1

    const emitEvent = useCallback((event: string, data: unknown) => {
        if (requestId === null || token === null) return
        void fetchNui("kora_lib:nui:event", { requestId, token, event, data } satisfies NuiRequestEventEnvelope).catch((error) => {
            console.error(`[kora_lib] radial event '${event}' failed:`, error)
        })
    }, [requestId, token])

    useNuiEvent<NuiRequestEnvelope<OpenRadialMenuPayload>>("updateRadialMenu", useCallback((message) => {
        if (message.requestId !== requestId || message.token !== token) return
        setStack((previous) => rebuildStack(
            message.payload.items,
            message.payload.path ?? previous.slice(1).map((entry) => entry.viaId ?? "").filter(Boolean),
            previous,
        ))
        setActiveIndex(-1)
    }, [requestId, token]))

    useEffect(() => {
        if (!isOpen || requestId === null || token === null) return
        const path = stack.slice(1).map((entry) => entry.viaId ?? "")
        void fetchNui("kora_lib:nui:event", {
            requestId,
            token,
            event: "radialLevel",
            data: { path },
        } satisfies NuiRequestEventEnvelope).catch((error) => {
            console.error("[kora_lib] radial level event failed:", error)
        })
    }, [isOpen, requestId, stack, token])

    const entries = useMemo<RingEntry[]>(() => {
        if (!level) return []

        if (level.items.length <= MAX_RING_ITEMS) {
            return level.items.map((item) => ({ kind: "item", item }))
        }

        const totalPages = Math.ceil(level.items.length / PAGE_SIZE_WITH_MORE)
        const page = level.page % totalPages
        const start = page * PAGE_SIZE_WITH_MORE
        const items = level.items.slice(start, start + PAGE_SIZE_WITH_MORE).map((item) => ({ kind: "item" as const, item }))
        return [...items, { kind: "more", page, totalPages }]
    }, [level])

    const dismiss = useCallback(() => respond({ cancelled: true }), [respond])

    const goBack = useCallback(() => {
        setStack((previous) => (previous.length > 1 ? previous.slice(0, -1) : previous))
        setActiveIndex(-1)
    }, [])

    const goNextPage = useCallback(() => {
        setStack((previous) => {
            const current = previous[previous.length - 1]
            if (!current || current.items.length <= MAX_RING_ITEMS) return previous
            const totalPages = Math.ceil(current.items.length / PAGE_SIZE_WITH_MORE)
            return [...previous.slice(0, -1), { ...current, page: (current.page + 1) % totalPages }]
        })
        setActiveIndex(-1)
    }, [])

    const selectItem = useCallback(
        (item: MenuItem) => {
            if (item.disabled) return

            if (item.submenu) {
                setStack((previous) => [
                    ...previous,
                    { title: item.submenu?.title ?? item.label, items: item.submenu?.items ?? [], viaId: item.id, page: 0 },
                ])
                setActiveIndex(-1)
                return
            }

            const path = stack.slice(1).map((entry) => entry.viaId ?? "")
            const selection = { selectedId: item.id, path: [...path, item.id] }
            if (item.close === false) {
                emitEvent("confirmed", selection)
                return
            }
            respond(selection)
        },
        [emitEvent, respond, stack],
    )

    const activateEntry = useCallback(
        (entry: RingEntry) => {
            if (entry.kind === "more") {
                goNextPage()
                return
            }
            selectItem(entry.item)
        },
        [goNextPage, selectItem],
    )

    useEffect(() => {
        if (!isOpen) return
        setActiveIndex((previous) => {
            const current = entries[previous]
            if (current && (current.kind === "more" || !current.item.disabled)) return previous
            return firstEnabled(entries)
        })
    }, [entries, isOpen])

    useEffect(() => {
        if (!isOpen || activeIndex < 0) return
        itemRefs.current[activeIndex]?.focus()
    }, [activeIndex, isOpen, entries])

    useEffect(() => {
        if (!isOpen) return

        function onKeyDown(event: KeyboardEvent) {
            if (event.key === "Escape") {
                event.preventDefault()
                dismiss()
                return
            }

            const enabledIndexes = entries.reduce<number[]>(
                (indexes, entry, index) => (entry.kind === "more" || !entry.item.disabled ? [...indexes, index] : indexes),
                [],
            )
            if (enabledIndexes.length === 0) return

            if (event.key === "ArrowRight" || event.key === "ArrowDown") {
                event.preventDefault()
                const position = enabledIndexes.indexOf(activeIndex)
                setActiveIndex(enabledIndexes[position === -1 ? 0 : (position + 1) % enabledIndexes.length])
            } else if (event.key === "ArrowLeft" || event.key === "ArrowUp") {
                event.preventDefault()
                const position = enabledIndexes.indexOf(activeIndex)
                setActiveIndex(enabledIndexes[position === -1 ? enabledIndexes.length - 1 : (position - 1 + enabledIndexes.length) % enabledIndexes.length])
            } else if (event.key === "Home") {
                event.preventDefault()
                setActiveIndex(enabledIndexes[0])
            } else if (event.key === "End") {
                event.preventDefault()
                setActiveIndex(enabledIndexes[enabledIndexes.length - 1])
            } else if (event.key === "Enter" || event.key === " ") {
                event.preventDefault()
                const entry = entries[activeIndex]
                if (entry) activateEntry(entry)
            }
        }

        document.addEventListener("keydown", onKeyDown)
        return () => document.removeEventListener("keydown", onKeyDown)
    }, [activeIndex, activateEntry, dismiss, entries, isOpen])

    if (!isOpen || !payload || !level) return null

    const viewport = getNuiViewport()
    const requestedRadius = payload.radius ?? DEFAULT_RADIUS
    const maximumRadius = Math.max(48, Math.min(viewport.width, viewport.height) / 2 - ITEM_HALF_SIZE - EDGE_GUTTER)
    const radius = Math.min(Math.max(96, requestedRadius), maximumRadius)
    const labelLines = Math.min(4, Math.max(1, Math.floor(payload.labelLines ?? DEFAULT_LABEL_LINES)))
    const activeEntry = entries[activeIndex]
    const activeItem = activeEntry?.kind === "item" ? activeEntry.item : undefined
    const activeDescriptionIsFallback = Boolean(activeItem?.disabled && !activeItem.description)
    const activeDescription = activeItem?.description ?? (activeItem?.disabled ? "Unavailable right now" : undefined)
    const hubShowsLabel = Boolean(activeItem && activeItem.label.length > LONG_LABEL_LENGTH)
    const hubTitle = hubShowsLabel && activeItem ? activeItem.label : canGoBack ? "Back" : level.title ?? "Actions"
    const moreIcon = resolveIcon("ChevronRight")
    const CenterIcon = resolveIcon(canGoBack ? "ChevronLeft" : "X")

    return (
        <>
            <div className="fixed inset-0 z-overlay bg-modal-overlay pointer-events-auto duration-dialog ease-entry animate-in fade-in-0" onMouseDown={dismiss} aria-hidden="true" />
            <div
                role="menu"
                aria-label={level.title ?? "Radial menu"}
                className="pointer-events-none fixed left-1/2 top-1/2 z-overlay select-none duration-dialog ease-entry animate-in zoom-in-95"
            >
                <svg
                    aria-hidden="true"
                    className="pointer-events-none absolute left-1/2 top-1/2 overflow-visible"
                    width={radius * 2}
                    height={radius * 2}
                    viewBox={`0 0 ${radius * 2} ${radius * 2}`}
                    style={{ transform: "translate(-50%, -50%)" }}
                >
                    {entries.map((entry, index) => {
                        const angle = (index / entries.length) * Math.PI * 2 - Math.PI / 2
                        const isActive = index === activeIndex && (entry.kind === "more" || !entry.item.disabled)
                        const start = 46
                        const end = Math.max(start, radius - ITEM_HALF_SIZE - 6)
                        const center = radius
                        const x1 = center + Math.cos(angle) * start
                        const y1 = center + Math.sin(angle) * start
                        const x2 = center + Math.cos(angle) * end
                        const y2 = center + Math.sin(angle) * end
                        const stroke = isActive ? "hsl(var(--primary))" : "hsl(var(--border-strong))"

                        return (
                            <g key={entry.kind === "more" ? "__more__-link" : entry.item.id}>
                                <line
                                    x1={x1}
                                    y1={y1}
                                    x2={x2}
                                    y2={y2}
                                    stroke={stroke}
                                    strokeWidth={isActive ? 2 : 1}
                                    className="transition-[stroke,stroke-width] duration-fast"
                                />
                                <circle
                                    cx={x2}
                                    cy={y2}
                                    r={isActive ? 3 : 2}
                                    fill={stroke}
                                    className="transition-[fill,r] duration-fast"
                                />
                            </g>
                        )
                    })}
                </svg>

                {entries.map((entry, index) => {
                    const angle = (index / entries.length) * Math.PI * 2 - Math.PI / 2
                    const x = Math.cos(angle) * radius
                    const y = Math.sin(angle) * radius
                    const item = entry.kind === "item" ? entry.item : null
                    const Icon = item ? resolveIcon(item.icon) : moreIcon
                    const iconIsImage = isIconImage(item?.icon)
                    const disabled = item?.disabled === true
                    const label = entry.kind === "more" ? `${locale.more} ${entry.page + 1}/${entry.totalPages}` : item?.label ?? ""

                    return (
                        <button
                            key={entry.kind === "more" ? "__more__" : item?.id}
                            ref={(element) => { itemRefs.current[index] = element }}
                            type="button"
                            role="menuitem"
                            tabIndex={index === activeIndex ? 0 : -1}
                            aria-disabled={disabled || undefined}
                            aria-haspopup={item?.submenu ? "menu" : undefined}
                            aria-label={item?.description ? `${label}: ${item.description}` : label}
                            title={item?.description ? `${label}: ${item.description}` : label}
                            onMouseEnter={() => setActiveIndex(index)}
                            onFocus={() => setActiveIndex(index)}
                            onClick={() => activateEntry(entry)}
                            className={cn(
                                "focus-ring pointer-events-auto absolute flex h-20 w-20 -translate-x-1/2 -translate-y-1/2 flex-col items-center justify-center gap-1 rounded-xl border bg-card px-2 text-center text-xs font-medium text-card-foreground shadow-low transition-[background-color,border-color,color,transform] duration-fast",
                                disabled
                                    ? "cursor-not-allowed border-border opacity-[0.48]"
                                    : "cursor-pointer hover:border-control-border-hover hover:bg-surface-hover",
                                index === activeIndex && !disabled && "border-brand-border bg-brand-soft text-foreground",
                            )}
                            style={{
                                transform: `translate(-50%, -50%) translate(${x}px, ${y}px)`,
                            }}
                        >
                            {iconIsImage ? <img aria-hidden src={item?.icon} className="max-h-16 max-w-16 shrink-0 object-contain" style={{ width: Math.max(0, Math.min(100, item?.iconWidth ?? 20)), height: Math.max(0, Math.min(100, item?.iconHeight ?? 20)) }} /> : Icon ? <Icon aria-hidden className={cn("h-5 w-5 shrink-0", iconAnimationClass(item?.iconAnimation))} style={{ color: item?.iconColor, width: item?.iconWidth, height: item?.iconHeight }} /> : <span aria-hidden className="font-mono text-sm">{index + 1}</span>}
                            <span
                                className={cn("w-full min-w-0 overflow-hidden [overflow-wrap:anywhere] [display:-webkit-box] [-webkit-box-orient:vertical]", labelSizeClass(label))}
                                style={{ WebkitLineClamp: labelLines }}
                            >
                                {label}
                            </span>
                            {item?.submenu ? <span aria-hidden className="absolute right-1.5 top-1.5 text-muted-foreground">›</span> : null}
                        </button>
                    )
                })}

                <div
                    className={cn(
                        "pointer-events-auto absolute left-1/2 top-1/2 flex h-24 w-24 -translate-x-1/2 -translate-y-1/2 flex-col items-center justify-center rounded-xl border bg-card p-2 text-center shadow-low transition-colors duration-fast",
                        activeItem && !activeItem.disabled ? "border-brand-border" : "border-border",
                    )}
                >
                    <button
                        type="button"
                        onClick={canGoBack ? goBack : dismiss}
                        className="focus-ring flex h-9 w-9 items-center justify-center rounded-md text-muted-foreground transition-[background-color,color,transform] duration-fast hover:bg-surface-hover hover:text-foreground active:scale-[0.98]"
                        aria-label={canGoBack ? "Back" : `${locale.close} radial menu`}
                        title={canGoBack ? "Back" : locale.close}
                    >
                        {CenterIcon ? <CenterIcon aria-hidden className="h-4 w-4" /> : <span aria-hidden>×</span>}
                    </button>
                    <span className="line-clamp-2 max-w-full [overflow-wrap:anywhere] text-[10px] font-semibold leading-3 text-foreground">{hubTitle}</span>
                    {activeDescription ? (
                        <span className={cn(hubShowsLabel ? "mt-0.5 line-clamp-1 text-[9px]" : "mt-0.5 line-clamp-2 text-[9px]",
                            " leading-3 text-muted-foreground", activeDescriptionIsFallback && "italic")}>
                            {activeDescription}
                        </span>
                    ) : null}
                </div>
            </div>
        </>
    )
}
