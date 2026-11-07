import { useCallback, useEffect, useMemo, useRef, useState, type CSSProperties } from "react"
import { ChevronRight } from "lucide-react"

import { cn } from "@/lib/cn"
import type { MenuItem, MenuResult, OpenContextMenuPayload } from "@/lib/types"
import { useNuiRequest } from "@/lib/useNuiRequest"
import { getNuiViewport } from "@/lib/viewport"
import { MenuItemLabel } from "@/components/menu/MenuItemLabel"
import { Markdown } from "@/components/ui/markdown"

// Rough per-item footprint used only to decide whether the popup needs to be
// flipped onto screen -- doesn't need to be exact, just close enough that the
// menu never renders (even partially) past the viewport edge.
const ESTIMATED_WIDTH = 220
const ESTIMATED_ITEM_HEIGHT = 36

/**
 * Always-mounted, self-contained context menu for the "openContextMenu" NUI
 * request. Renders nothing until Lua asks for one; positions itself at the
 * requested (x, y) (flipping to stay on screen), and resolves the pending
 * Lua request with either a MenuResult selection or a cancellation --
 * dismissed by an outside click, Escape, or picking an item. Arrow keys/Home/
 * End move a roving focus between items and Enter selects the focused one,
 * matching the role="menu"/role="menuitem" semantics below.
 */
export function ContextMenuContainer() {
    const [activeIndex, setActiveIndex] = useState(-1)
    const menuRef = useRef<HTMLDivElement>(null)
    const itemRefs = useRef<(HTMLButtonElement | null)[]>([])

    const { payload, isOpen, respond } = useNuiRequest<OpenContextMenuPayload, MenuResult>(
        "openContextMenu",
        useCallback((openPayload: OpenContextMenuPayload) => {
            setActiveIndex(openPayload.items.findIndex((item) => !item.disabled))
        }, []),
        { cancelled: true },
    )

    const items = useMemo(() => payload?.items ?? [], [payload])
    const enabledIndexes = useMemo(
        () => items.reduce<number[]>((acc, item, i) => (item.disabled ? acc : [...acc, i]), []),
        [items],
    )

    const selectItem = useCallback(
        (item: MenuItem) => {
            if (item.disabled || item.readOnly) return
            // Always a single-element path: the context menu is a flat,
            // anchored one-shot list and ignores `submenu` (there's nowhere
            // sensible to put a back row) -- see MenuItem in lib/types.ts.
            respond({ selectedId: item.id, path: [item.id] })
        },
        [respond],
    )

    const dismiss = useCallback(() => {
        if (payload?.canClose !== false) respond({ cancelled: true })
    }, [payload?.canClose, respond])

    // Outside-click / Escape / arrow-key dismissal+navigation -- there's no
    // Radix popover here to do this for us, so it's wired up by hand for as
    // long as a menu is open.
    useEffect(() => {
        if (!isOpen) return

        function onMouseDown(event: MouseEvent) {
            if (menuRef.current && !menuRef.current.contains(event.target as Node)) {
                dismiss()
            }
        }

        function onKeyDown(event: KeyboardEvent) {
            if (event.key === "Escape") {
                dismiss()
                return
            }

            if (enabledIndexes.length === 0) return

            if (event.key === "ArrowDown" || event.key === "ArrowUp") {
                event.preventDefault()
                const pos = enabledIndexes.indexOf(activeIndex)
                const delta = event.key === "ArrowDown" ? 1 : -1
                const nextPos = pos === -1 ? 0 : (pos + delta + enabledIndexes.length) % enabledIndexes.length
                setActiveIndex(enabledIndexes[nextPos])
            } else if (event.key === "Home") {
                event.preventDefault()
                setActiveIndex(enabledIndexes[0])
            } else if (event.key === "End") {
                event.preventDefault()
                setActiveIndex(enabledIndexes[enabledIndexes.length - 1])
            } else if (event.key === "Enter" || event.key === " ") {
                event.preventDefault()
                const item = items[activeIndex]
                if (item) selectItem(item)
            }
        }

        document.addEventListener("mousedown", onMouseDown)
        document.addEventListener("keydown", onKeyDown)
        return () => {
            document.removeEventListener("mousedown", onMouseDown)
            document.removeEventListener("keydown", onKeyDown)
        }
    }, [isOpen, activeIndex, enabledIndexes, items, selectItem, dismiss])

    // Keep DOM focus on the active item so screen readers/keyboard users
    // track roving focus the same way the ARIA role="menu" semantics imply.
    useEffect(() => {
        if (isOpen) itemRefs.current[activeIndex]?.focus()
    }, [isOpen, activeIndex])

    if (!isOpen || !payload) return null

    const viewport = getNuiViewport()
    // Lua supplies screen pixels. The root is scaled above 1080p, so convert
    // those coordinates before positioning inside its virtual viewport.
    const x = (payload.x ?? window.innerWidth / 2) / viewport.scale
    const y = (payload.y ?? window.innerHeight / 2) / viewport.scale
    const estimatedHeight = items.reduce(
        (height, item) => height + (item.description || item.metadata?.length ? ESTIMATED_ITEM_HEIGHT + 24 : ESTIMATED_ITEM_HEIGHT),
        payload.title ? 48 : 8,
    )
    const clampedY = Math.min(Math.max(8, y), viewport.height - 8)
    const spaceAbove = clampedY - 8
    const spaceBelow = viewport.height - clampedY - 8
    const flipX = x + ESTIMATED_WIDTH > viewport.width
    const flipY = estimatedHeight > spaceBelow && spaceAbove > spaceBelow
    const maxHeight = flipY ? spaceAbove : spaceBelow

    const style: CSSProperties = {
        position: "fixed",
        maxHeight,
        ...(flipX ? { right: Math.max(8, viewport.width - x) } : { left: Math.max(8, x) }),
        ...(flipY ? { bottom: Math.max(8, viewport.height - clampedY) } : { top: clampedY }),
    }

    return (
        <div
            ref={menuRef}
            role="menu"
            style={style}
            className="pointer-events-auto z-overlay max-h-[calc(100vh-1rem)] min-w-[10rem] max-w-[calc(100vw-1rem)] overflow-x-hidden overflow-y-auto rounded-lg bg-popover p-1 text-popover-foreground shadow-floating duration-popover ease-entry animate-in fade-in-0"
        >
            {payload.title ? (
                <div className="mx-3 mb-1 mt-2 pb-1 font-heading text-sm font-semibold">
                    <Markdown inline>{payload.title}</Markdown>
                </div>
            ) : null}
            {items.map((item, index) => (
                <button
                    key={item.id}
                    ref={(el) => { itemRefs.current[index] = el }}
                    type="button"
                    role="menuitem"
                    tabIndex={index === activeIndex ? 0 : -1}
                    disabled={item.disabled}
                    data-readonly={item.readOnly || undefined}
                    onMouseEnter={() => !item.disabled && setActiveIndex(index)}
                    onClick={() => selectItem(item)}
                    className={cn(
                        "focus-ring relative flex min-h-9 w-full items-start gap-2 rounded-sm px-3 py-1.5 text-left text-sm outline-none transition-colors duration-fast",
                        (item.description || item.metadata?.length) && "min-h-12",
                        item.disabled
                            ? "pointer-events-none cursor-not-allowed opacity-[0.48]"
                            : item.readOnly ? "cursor-default" : "cursor-pointer hover:bg-surface-hover",
                        index === activeIndex && !item.disabled && "bg-surface-hover before:absolute before:bottom-1.5 before:left-0 before:top-1.5 before:w-0.5 before:rounded-full before:bg-primary"
                    )}
                >
                    <MenuItemLabel item={item} />
                    {(item.submenu || item.arrow === true) && item.arrow !== false ? <ChevronRight aria-hidden className="ml-auto mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" /> : null}
                </button>
            ))}
        </div>
    )
}
