import { useCallback, useState, type CSSProperties } from "react"
import { ChevronLeft, ChevronRight } from "lucide-react"

import { cn } from "@/lib/cn"
import type { CloseMenuPayload, MenuItem, MenuResult, OpenMenuPayload } from "@/lib/types"
import { useNuiRequest } from "@/lib/useNuiRequest"
import { useNuiEvent } from "@/lib/useNuiEvent"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList } from "@/components/ui/command"
import { MenuItemLabel } from "@/components/menu/MenuItemLabel"

/** One level of the menu stack. `viaId` is the item that opened it (absent at the root). */
interface Level {
    title?: string
    items: MenuItem[]
    viaId?: string
}

function positiveNumber(value: unknown): number | undefined {
    return typeof value === "number" && Number.isFinite(value) && value > 0 ? value : undefined
}

function menuPlacement(payload: OpenMenuPayload): { className: string; style: CSSProperties } {
    const horizontal = payload.position?.horizontal ?? "center"
    const vertical = payload.position?.vertical ?? "center"
    const offsetX = positiveNumber(payload.position?.offsetX) ?? 32
    const offsetY = positiveNumber(payload.position?.offsetY) ?? 32

    const horizontalClass = horizontal === "left"
        ? "left-0 translate-x-0"
        : horizontal === "right"
            ? "left-auto right-0 translate-x-0"
            : "left-1/2 -translate-x-1/2"
    const verticalClass = vertical === "top"
        ? "top-0 translate-y-0"
        : vertical === "bottom"
            ? "top-auto bottom-0 translate-y-0"
            : "top-1/2 -translate-y-1/2"

    return {
        className: `${horizontalClass} ${verticalClass}`,
        style: {
            maxWidth: positiveNumber(payload.maxWidth),
            maxHeight: positiveNumber(payload.maxHeight),
            ...(horizontal === "left" ? { left: offsetX } : horizontal === "right" ? { right: offsetX } : {}),
            ...(vertical === "top" ? { top: offsetY } : vertical === "bottom" ? { bottom: offsetY } : {}),
        },
    }
}

/**
 * Renders the "openMenu" request as a searchable Command list inside a
 * Dialog. Always mounted (see App.tsx) but renders nothing until Lua sends
 * an "openMenu" message; settles the pending QB.nui.request promise exactly
 * once, either with the selected item or a cancellation (via useNuiRequest).
 *
 * Items carrying a `submenu` push a new level rather than resolving, and the
 * whole tree arrives in the single openMenu payload -- so descending and going
 * back never touch Lua, and the request settles exactly once no matter how
 * deep the player wandered.
 */
export function MenuContainer() {
    const [stack, setStack] = useState<Level[]>([])
    // Controlled so it can be cleared on every navigation: cmdk keeps the
    // filter otherwise, and a term typed at one level would silently hide most
    // of the next one -- which reads as "the submenu is empty".
    const [search, setSearch] = useState("")

    const { payload, isOpen, respond } = useNuiRequest<OpenMenuPayload, MenuResult>(
        "openMenu",
        useCallback((open: OpenMenuPayload) => {
            setStack([{ title: open.title, items: open.items }])
            setSearch("")
        }, []),
    )

    const level = stack[stack.length - 1]
    const canGoBack = stack.length > 1

    useNuiEvent<CloseMenuPayload>("closeMenu", useCallback(() => {
        if (isOpen) respond({ cancelled: true })
    }, [isOpen, respond]))

    const goBack = useCallback(() => {
        setStack((prev) => (prev.length > 1 ? prev.slice(0, -1) : prev))
        setSearch("")
    }, [])

    const handleSelect = useCallback(
        (item: MenuItem) => {
            if (item.disabled) return

            const submenu = item.submenu

            if (submenu) {
                setStack((prev) => [...prev, { title: submenu.title ?? item.label, items: submenu.items, viaId: item.id }])
                setSearch("")
                return
            }

            // Root-first trail of the ids walked through to get here. Each
            // level past the root records the item that opened it, so this is
            // just those plus the leaf. Read from `stack` rather than inside a
            // setStack updater: respond() is a side effect, and updaters must
            // stay pure (StrictMode double-invokes them in dev) -- the same
            // reasoning as the note in lib/useNuiRequest.ts.
            const path = stack.slice(1).map((entry) => entry.viaId ?? "")
            respond({ selectedId: item.id, path: [...path, item.id] })
        },
        [stack, respond],
    )

    const handleOpenChange = useCallback(
        (open: boolean) => {
            if (open) return

            // Escape/backdrop steps BACK out of a submenu rather than throwing
            // away the whole interaction -- only a dismiss at the root cancels.
            // The dialog stays mounted because `open` is never actually false
            // while a request is pending.
            if (canGoBack) {
                goBack()
                return
            }

            respond({ cancelled: true })
        },
        [canGoBack, goBack, respond],
    )

    if (!isOpen || !payload || !level) return null

    const placement = menuPlacement(payload)

    return (
        <Dialog open onOpenChange={handleOpenChange}>
            {/* DialogContent (ui/dialog.tsx) already carries pointer-events-auto
                for the page-wide pointer-events: none default -- nothing extra
                to opt into here. */}
            <DialogContent
                className={cn("grid h-[75dvh] max-h-[calc(100dvh-2rem)] max-w-md grid-rows-[auto_minmax(0,1fr)] gap-0 overflow-hidden p-0", placement.className)}
                style={placement.style}
            >
                <DialogHeader className={cn("mx-4 mt-4 pb-3", !level.title && "sr-only")}>
                    <DialogTitle>{level.title ?? "Menu"}</DialogTitle>
                </DialogHeader>
                <Command className="min-h-0 rounded-none border-0 bg-popover text-popover-foreground">
                    <CommandInput placeholder="Search..." value={search} onValueChange={setSearch} />
                    <CommandList className="min-h-0 max-h-none flex-1">
                        <CommandEmpty>No results</CommandEmpty>
                        <CommandGroup>
                            {canGoBack && (
                                // Rendered outside `items` rather than injected
                                // into them: a sentinel id could collide with a
                                // real one, and this way it can't be filtered
                                // away by a search term either.
                                <CommandItem
                                    // forceMount keeps Back reachable while a
                                    // search is active -- otherwise typing
                                    // something with no matches strands you.
                                    forceMount
                                    value="__qblib_back__"
                                    onSelect={goBack}
                                    className="min-h-10 items-center gap-2 py-2 text-muted-foreground"
                                >
                                    <ChevronLeft aria-hidden className="h-4 w-4 shrink-0" />
                                    <span>Back</span>
                                </CommandItem>
                            )}

                            {level.items.map((item) => (
                                <CommandItem
                                    key={item.id}
                                    value={item.label}
                                    disabled={item.disabled}
                                    onSelect={() => handleSelect(item)}
                                    className="min-h-12 items-start gap-2 py-2"
                                >
                                    <MenuItemLabel item={item} />
                                    {item.submenu && (
                                        <ChevronRight aria-hidden className="ml-auto mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" />
                                    )}
                                </CommandItem>
                            ))}
                        </CommandGroup>
                    </CommandList>
                </Command>
            </DialogContent>
        </Dialog>
    )
}
