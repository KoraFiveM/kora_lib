import { useCallback, useEffect, useMemo, useRef, useState } from "react"

import { cn } from "@/lib/cn"
import { resolveIcon } from "@/lib/icon"
import type { MenuItem, MenuResult, OpenRadialMenuPayload } from "@/lib/types"
import { useNuiRequest } from "@/lib/useNuiRequest"

const MAX_RING_ITEMS = 8
const PAGE_SIZE_WITH_MORE = MAX_RING_ITEMS - 1
const DEFAULT_RADIUS = 156
const ITEM_HALF_SIZE = 42
const EDGE_GUTTER = 16

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

/**
 * The visual half of QB.nui.openRadialMenu. The whole nested tree is delivered
 * once; changing levels/pages is local React state and only a terminal choice
 * or cancellation settles the original tokenised NUI request.
 */
export function RadialMenuContainer() {
    const [stack, setStack] = useState<Level[]>([])
    const [activeIndex, setActiveIndex] = useState(-1)
    const itemRefs = useRef<(HTMLButtonElement | null)[]>([])

    const { payload, isOpen, respond } = useNuiRequest<OpenRadialMenuPayload, MenuResult>(
        "openRadialMenu",
        useCallback((open: OpenRadialMenuPayload) => {
            setStack([{ items: open.items, page: 0 }])
            setActiveIndex(-1)
        }, []),
    )

    const level = stack[stack.length - 1]
    const canGoBack = stack.length > 1
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
            respond({ selectedId: item.id, path: [...path, item.id] })
        },
        [respond, stack],
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

    const requestedRadius = payload.radius ?? DEFAULT_RADIUS
    const maximumRadius = Math.max(48, Math.min(window.innerWidth, window.innerHeight) / 2 - ITEM_HALF_SIZE - EDGE_GUTTER)
    const radius = Math.min(Math.max(96, requestedRadius), maximumRadius)
    const activeEntry = entries[activeIndex]
    const activeItem = activeEntry?.kind === "item" ? activeEntry.item : undefined
    // Disabled items don't carry a reason field, so falling back to a plain
    // "unavailable" note is better than the previous silence -- hovering one
    // used to update nothing in the hub at all.
    const activeDescriptionIsFallback = Boolean(activeItem?.disabled && !activeItem.description)
    const activeDescription = activeItem?.description ?? (activeItem?.disabled ? "Unavailable right now" : undefined)
    const closeIcon = resolveIcon("X")
    const backIcon = resolveIcon("ChevronLeft")
    const moreIcon = resolveIcon("ChevronRight")
    const CenterIcon = canGoBack ? backIcon : closeIcon

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
                    const disabled = item?.disabled === true
                    const label = entry.kind === "more" ? `More ${entry.page + 1}/${entry.totalPages}` : item?.label ?? ""

                    return (
                        <button
                            key={entry.kind === "more" ? "__more__" : item?.id}
                            ref={(element) => { itemRefs.current[index] = element }}
                            type="button"
                            role="menuitem"
                            tabIndex={index === activeIndex ? 0 : -1}
                            // aria-disabled instead of the native `disabled` attribute:
                            // a natively-disabled button suppresses mouse/focus events
                            // entirely, so hovering a disabled item could never explain
                            // why it's unavailable. selectItem()/activateEntry() already
                            // no-op for disabled items, so this stays inert to clicks.
                            aria-disabled={disabled || undefined}
                            aria-haspopup={item?.submenu ? "menu" : undefined}
                            aria-label={item?.description ? `${label}: ${item.description}` : label}
                            title={item?.description ?? label}
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
                            {Icon ? <Icon aria-hidden className="h-5 w-5 shrink-0" /> : <span aria-hidden className="font-mono text-sm">{index + 1}</span>}
                            <span className="max-w-full truncate leading-4">{label}</span>
                            {item?.submenu ? <span aria-hidden className="absolute right-1.5 top-1.5 text-muted-foreground">›</span> : null}
                        </button>
                    )
                })}

                <div
                    className={cn(
                        "pointer-events-auto absolute left-1/2 top-1/2 flex h-24 w-24 -translate-x-1/2 -translate-y-1/2 flex-col items-center justify-center rounded-xl border bg-card p-2 text-center shadow-low transition-colors duration-fast",
                        // Ties the hub visually to whichever spoke is highlighted,
                        // instead of only updating the description text below.
                        activeItem && !activeItem.disabled ? "border-brand-border" : "border-border",
                    )}
                >
                    <button
                        type="button"
                        onClick={canGoBack ? goBack : dismiss}
                        className="focus-ring flex h-9 w-9 items-center justify-center rounded-md text-muted-foreground transition-[background-color,color,transform] duration-fast hover:bg-surface-hover hover:text-foreground active:scale-[0.98]"
                        aria-label={canGoBack ? "Back" : "Close radial menu"}
                        title={canGoBack ? "Back" : "Close"}
                    >
                        {CenterIcon ? <CenterIcon aria-hidden className="h-4 w-4" /> : <span aria-hidden>×</span>}
                    </button>
                    <span className="max-w-full truncate text-[10px] font-semibold text-foreground">{canGoBack ? "Back" : level.title ?? "Actions"}</span>
                    {activeDescription ? (
                        <span className={cn("mt-0.5 line-clamp-2 text-[9px] leading-3 text-muted-foreground", activeDescriptionIsFallback && "italic")}>
                            {activeDescription}
                        </span>
                    ) : null}
                </div>
            </div>
        </>
    )
}
