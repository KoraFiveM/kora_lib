import { useCallback, useEffect, useState, type CSSProperties, type KeyboardEvent } from "react"
import { ChevronLeft, ChevronRight } from "lucide-react"

import { cn } from "@/lib/cn"
import type { CloseMenuPayload, MenuItem, MenuResult, NuiRequestEventEnvelope, OpenMenuPayload, UpdateMenuPayload } from "@/lib/types"
import { useNuiRequest } from "@/lib/useNuiRequest"
import { useNuiEvent } from "@/lib/useNuiEvent"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList } from "@/components/ui/command"
import { MenuItemLabel } from "@/components/menu/MenuItemLabel"
import { fetchNui } from "@/lib/fetchNui"
import { Markdown } from "@/components/ui/markdown"

/** One level of the menu stack. `viaId` is the item that opened it (absent at the root). */
interface Level {
    title?: string
    items: MenuItem[]
    viaId?: string
}

function positiveNumber(value: unknown): number | undefined {
    return typeof value === "number" && Number.isFinite(value) && value > 0 ? value : undefined
}

function metadataKeywords(item: MenuItem): string {
    return item.metadata?.map((metadata) => typeof metadata === "string"
        ? metadata
        : `${metadata.label} ${metadata.value === undefined ? "" : String(metadata.value)}`
    ).join(" ") ?? ""
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
 * an "openMenu" message; settles the pending Kora.nui.request promise exactly
 * once, either with the selected item or a cancellation (via useNuiRequest).
 *
 * Items carrying a `submenu` push a new level rather than resolving, and the
 * whole tree arrives in the single openMenu payload -- so descending and going
 * back never touch Lua, and the request settles exactly once no matter how
 * deep the player wandered.
 */
export function MenuContainer() {
    const [stack, setStack] = useState<Level[]>([])
    const [selectedId, setSelectedId] = useState("")
    const [valueIndexes, setValueIndexes] = useState<Record<string, number>>({})
    const [checkedStates, setCheckedStates] = useState<Record<string, boolean>>({})
    const [viewPayload, setViewPayload] = useState<OpenMenuPayload | null>(null)
    const [menuVersion, setMenuVersion] = useState(0)
    // Controlled so it can be cleared on every navigation: cmdk keeps the
    // filter otherwise, and a term typed at one level would silently hide most
    // of the next one -- which reads as "the submenu is empty".
    const [search, setSearch] = useState("")

    const seedMenu = useCallback((open: OpenMenuPayload) => {
        setViewPayload(open)
        setMenuVersion((current) => current + 1)
        setStack([{ title: open.title, items: open.items }])
        setSearch("")
        const start = Math.max(0, Math.min(open.items.length - 1, (open.startIndex ?? 1) - 1))
        setSelectedId(open.items[start]?.id ?? "")
        setValueIndexes(Object.fromEntries(open.items.filter((item) => item.values?.length).map((item) => [item.id, Math.max(0, Math.min(item.values!.length - 1, (item.defaultIndex ?? 1) - 1))])))
        setCheckedStates(Object.fromEntries(open.items.filter((item) => item.checked !== undefined).map((item) => [item.id, item.checked === true])))
    }, [])

    const { requestId, token, isOpen, respond } = useNuiRequest<OpenMenuPayload, MenuResult>(
        "openMenu",
        seedMenu,
    )

    const level = stack[stack.length - 1]
    const canGoBack = stack.length > 1

    const emitEvent = useCallback((event: string, data: unknown) => {
        if (requestId === null || token === null) return
        void fetchNui("kora_lib:nui:event", { requestId, token, event, data } satisfies NuiRequestEventEnvelope).catch((error) => {
            console.error(`[kora_lib] menu event '${event}' failed:`, error)
        })
    }, [requestId, token])

    useNuiEvent<UpdateMenuPayload>("updateMenu", useCallback((message) => {
        if (message.requestId !== requestId || message.token !== token || viewPayload?.presentation !== "panel") return
        seedMenu({ ...message.payload, presentation: "panel" })
    }, [requestId, seedMenu, token, viewPayload?.presentation]))

    useEffect(() => {
        if (!selectedId || !level) return
        const timer = window.setTimeout(() => {
            const index = level.items.findIndex((item) => item.id === selectedId)
            if (index < 0) return
            emitEvent("selected", { selectedId, index: index + 1, valueIndex: valueIndexes[selectedId] === undefined ? undefined : valueIndexes[selectedId] + 1, checked: checkedStates[selectedId] })
        }, 100)
        return () => window.clearTimeout(timer)
    // Value/check changes have their own event channels; changing either must
    // not re-fire onSelected for a row whose selection did not move.
    // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [emitEvent, level, selectedId])

    useNuiEvent<CloseMenuPayload>("closeMenu", useCallback(() => {
        if (isOpen) respond({ cancelled: true })
    }, [isOpen, respond]))

    const goBack = useCallback(() => {
        setStack((prev) => {
            if (prev.length <= 1) return prev
            const returnTo = prev[prev.length - 1]?.viaId
            const next = prev.slice(0, -1)
            setSelectedId(returnTo ?? next[next.length - 1]?.items[0]?.id ?? "")
            return next
        })
        setSearch("")
    }, [])

    const handleSelect = useCallback(
        (item: MenuItem) => {
            if (item.disabled || item.readOnly) return

            const submenu = item.submenu

            if (submenu) {
                setStack((prev) => [...prev, { title: submenu.title ?? item.label, items: submenu.items, viaId: item.id }])
                setSelectedId(submenu.items[0]?.id ?? "")
                setSearch("")
                return
            }

            if (item.checked !== undefined && !item.values) {
                const checked = !checkedStates[item.id]
                setCheckedStates((previous) => ({ ...previous, [item.id]: checked }))
                const index = level.items.findIndex((entry) => entry.id === item.id)
                emitEvent("checked", { selectedId: item.id, index: index + 1, checked })
                return
            }

            // Root-first trail of the ids walked through to get here. Each
            // level past the root records the item that opened it, so this is
            // just those plus the leaf. Read from `stack` rather than inside a
            // setStack updater: respond() is a side effect, and updaters must
            // stay pure (StrictMode double-invokes them in dev) -- the same
            // reasoning as the note in lib/useNuiRequest.ts.
            const path = stack.slice(1).map((entry) => entry.viaId ?? "")
            const selection = { selectedId: item.id, path: [...path, item.id], valueIndex: valueIndexes[item.id] === undefined ? undefined : valueIndexes[item.id] + 1, checked: checkedStates[item.id] }
            if (item.close === false) {
                const index = level.items.findIndex((entry) => entry.id === item.id)
                emitEvent("confirmed", { ...selection, index: index + 1 })
                return
            }
            respond(selection)
        },
        [checkedStates, emitEvent, level, stack, respond, valueIndexes],
    )

    const changeValue = useCallback((direction: 1 | -1) => {
        if (!level || !selectedId) return false
        const item = level.items.find((entry) => entry.id === selectedId)
        if (!item?.values?.length) return false
        const current = valueIndexes[item.id] ?? Math.max(0, (item.defaultIndex ?? 1) - 1)
        const next = (current + direction + item.values.length) % item.values.length
        setValueIndexes((previous) => ({ ...previous, [item.id]: next }))
        const index = level.items.findIndex((entry) => entry.id === item.id)
        emitEvent("sideScroll", { selectedId: item.id, index: index + 1, valueIndex: next + 1 })
        return true
    }, [emitEvent, level, selectedId, valueIndexes])

    const handleKeyDown = useCallback((event: KeyboardEvent) => {
        if (event.key === "ArrowLeft" || event.key === "ArrowRight") {
            if (changeValue(event.key === "ArrowRight" ? 1 : -1)) {
                event.preventDefault()
                event.stopPropagation()
            }
        }
    }, [changeValue])

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

            if (viewPayload?.canClose !== false) respond({ cancelled: true })
        },
        [canGoBack, goBack, respond, viewPayload?.canClose],
    )

    const closeFromKey = useCallback((keyPressed: "Escape" | "Backspace") => {
        if (canGoBack) {
            goBack()
            return
        }
        if (viewPayload?.canClose !== false) respond({ cancelled: true, keyPressed })
    }, [canGoBack, goBack, respond, viewPayload?.canClose])

    useEffect(() => {
        if (!isOpen || viewPayload?.presentation !== "panel") return
        const handlePanelKey = (event: globalThis.KeyboardEvent) => {
            if (event.key !== "Escape" && event.key !== "Backspace") return
            const target = event.target
            if (event.key === "Backspace" && target instanceof HTMLInputElement && target.value !== "") return
            event.preventDefault()
            event.stopPropagation()
            closeFromKey(event.key)
        }
        document.addEventListener("keydown", handlePanelKey)
        return () => document.removeEventListener("keydown", handlePanelKey)
    }, [closeFromKey, isOpen, viewPayload?.presentation])

    if (!isOpen || !viewPayload || !level) return null

    const placement = menuPlacement(viewPayload)
    const panel = viewPayload.presentation === "panel"
    const headerBack = canGoBack || viewPayload.back === true
    const handleHeaderBack = () => {
        if (canGoBack) {
            goBack()
            return
        }
        emitEvent("back", {})
    }
    const command = (
        <Command key={menuVersion} className={cn("min-h-0 rounded-none border-0 bg-popover text-popover-foreground", panel && "max-h-[calc(100dvh-4rem)]")} value={selectedId} onValueChange={setSelectedId} onKeyDownCapture={handleKeyDown} shouldFilter={!panel}>
            <CommandInput autoFocus placeholder="Search..." value={search} onValueChange={setSearch} containerClassName={panel ? "sr-only" : undefined} aria-hidden={panel || undefined} tabIndex={panel ? -1 : undefined} readOnly={panel} />
            <CommandList className={cn("min-h-0 flex-1", panel ? "max-h-[calc(100dvh-8rem)]" : "max-h-none")}>
                <CommandEmpty>No results</CommandEmpty>
                <CommandGroup>
                    {canGoBack && !panel && (
                        <CommandItem forceMount value="__kora_lib_back__" onSelect={goBack} className="min-h-10 items-center gap-2 py-2 text-muted-foreground">
                            <ChevronLeft aria-hidden className="h-4 w-4 shrink-0" />
                            <span>Back</span>
                        </CommandItem>
                    )}
                    {level.items.map((item) => (
                        <CommandItem
                            key={item.id}
                            value={item.id}
                            keywords={[item.label, item.description ?? "", metadataKeywords(item)]}
                            disabled={item.disabled}
                            data-readonly={item.readOnly || undefined}
                            onSelect={() => handleSelect(item)}
                            className={cn("min-h-12 items-start gap-2 py-2", item.readOnly && "cursor-default data-[selected=true]:bg-transparent")}
                        >
                            <MenuItemLabel item={item} valueIndex={valueIndexes[item.id]} checked={checkedStates[item.id]} />
                            {(item.submenu || item.arrow === true) && item.arrow !== false && <ChevronRight aria-hidden className="ml-auto mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" />}
                        </CommandItem>
                    ))}
                </CommandGroup>
            </CommandList>
        </Command>
    )

    if (panel) {
        return (
            <section
                role="dialog"
                aria-modal="false"
                aria-label={level.title ?? "Menu"}
                className={cn("pointer-events-auto fixed z-overlay grid w-[24rem] max-w-[calc(100vw-2rem)] grid-rows-[auto_minmax(0,1fr)] overflow-hidden rounded-lg border bg-popover shadow-floating duration-popover ease-entry animate-in fade-in-0", placement.className)}
                style={placement.style}
            >
                <header className={cn("title-rail mx-3 mt-2 flex min-h-9 items-center gap-1 border-b border-border pb-2 text-sm font-semibold", !level.title && !headerBack && "sr-only")}>
                    {headerBack && (
                        <button
                            type="button"
                            aria-label="Back"
                            title="Back"
                            className="focus-ring -ml-1 inline-flex h-8 w-8 shrink-0 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-surface-hover hover:text-foreground"
                            onClick={handleHeaderBack}
                        >
                            <ChevronLeft aria-hidden className="h-4 w-4" />
                        </button>
                    )}
                    <Markdown inline>{level.title ?? "Menu"}</Markdown>
                </header>
                {command}
            </section>
        )
    }

    return (
        <Dialog open onOpenChange={handleOpenChange}>
            {/* DialogContent (ui/dialog.tsx) already carries pointer-events-auto
                for the page-wide pointer-events: none default -- nothing extra
                to opt into here. */}
            <DialogContent
                className={cn("grid h-[75dvh] max-h-[calc(100dvh-2rem)] max-w-md grid-rows-[auto_minmax(0,1fr)] gap-0 overflow-hidden p-0", placement.className)}
                style={placement.style}
                onEscapeKeyDown={(event) => {
                    event.preventDefault()
                    closeFromKey("Escape")
                }}
                onKeyDownCapture={(event) => {
                    if (event.key !== "Backspace") return
                    const target = event.target
                    if (target instanceof HTMLInputElement && target.value !== "") return
                    event.preventDefault()
                    event.stopPropagation()
                    closeFromKey("Backspace")
                }}
            >
                <DialogHeader className={cn("mx-4 mt-4 pb-3", !level.title && "sr-only")}>
                    <DialogTitle><Markdown inline>{level.title ?? "Menu"}</Markdown></DialogTitle>
                </DialogHeader>
                {command}
            </DialogContent>
        </Dialog>
    )
}
