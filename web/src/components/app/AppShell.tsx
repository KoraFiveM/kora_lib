import { useCallback, useEffect, useMemo, useState, type KeyboardEvent } from "react"
import { AlertCircle, ChevronRight, X } from "lucide-react"

import { Button } from "@/components/ui/button"
import { cn } from "@/lib/cn"
import { fetchNui } from "@/lib/fetchNui"
import { resolveIcon } from "@/lib/icon"
import type {
    AppAction,
    AppActionResponse,
    AppBlock,
    AppContent,
    AppDefinition,
    AppListItem,
    AppResult,
    AppTableRow,
    AppTableValue,
    AppTone,
    CloseAppPayload,
    OpenAppPayload,
    UpdateAppPayload,
} from "@/lib/types"
import { useNuiEvent } from "@/lib/useNuiEvent"
import { useNuiRequest } from "@/lib/useNuiRequest"

const toneClasses: Record<AppTone, string> = {
    neutral: "border-border bg-surface-raised text-foreground",
    primary: "border-brand-border bg-brand-soft text-primary",
    success: "border-success/45 bg-success/10 text-success",
    warning: "border-warning/45 bg-warning/10 text-warning",
    destructive: "border-destructive/45 bg-destructive/10 text-destructive",
}

function enabledView(app: AppDefinition, requested?: string) {
    return app.navigation.find((view) => view.id === requested && !view.disabled)
        ?? app.navigation.find((view) => view.id === app.defaultView && !view.disabled)
        ?? app.navigation.find((view) => !view.disabled)
}

function selectedTabId(view: ReturnType<typeof enabledView>, requested?: string) {
    if (!view?.tabs?.length) return undefined
    return view.tabs.find((tab) => tab.id === requested)?.id
        ?? view.tabs.find((tab) => tab.id === view.defaultTab)?.id
        ?? view.tabs[0]?.id
}

function displayValue(value: AppTableValue) {
    if (value === null || value === "") return "—"
    if (typeof value === "boolean") return value ? "Yes" : "No"
    return String(value)
}

function BlockTitle({ children }: { children?: string }) {
    return children ? <h3 className="mb-3 text-sm font-semibold text-foreground">{children}</h3> : null
}

function ActionButtons({
    actions,
    busy,
    run,
}: {
    actions: AppAction[]
    busy?: string
    run: (action: AppAction) => void
}) {
    return (
        <div className="flex flex-wrap items-center gap-2">
            {actions.map((action) => {
                const Icon = resolveIcon(action.icon)
                return (
                    <Button
                        key={action.id}
                        type="button"
                        variant={action.variant === "primary" ? "default" : action.variant ?? "secondary"}
                        disabled={action.disabled || busy !== undefined}
                        onClick={() => run(action)}
                    >
                        {Icon ? <Icon aria-hidden /> : null}
                        {busy === action.id ? "Working…" : action.label}
                    </Button>
                )
            })}
        </div>
    )
}

function ContentBlock({
    block,
    index,
    busy,
    runAction,
}: {
    block: AppBlock
    index: number
    busy?: string
    runAction: (action: AppAction, item?: { itemId?: string; value?: unknown }) => void
}) {
    if (block.type === "text") {
        return (
            <section className="rounded-lg border border-border bg-card p-4">
                <BlockTitle>{block.title}</BlockTitle>
                <p className="whitespace-pre-wrap text-sm leading-6 text-muted-foreground">{block.text}</p>
            </section>
        )
    }

    if (block.type === "stats") {
        return (
            <section>
                <BlockTitle>{block.title}</BlockTitle>
                <div className="grid grid-cols-[repeat(auto-fit,minmax(180px,1fr))] gap-3">
                    {block.items.map((item, itemIndex) => {
                        const Icon = resolveIcon(item.icon)
                        return (
                            <article key={`${item.label}-${itemIndex}`} className={cn("rounded-lg border p-4", toneClasses[item.tone ?? "neutral"])}>
                                <div className="flex items-center justify-between gap-3">
                                    <p className="text-xs font-medium text-muted-foreground">{item.label}</p>
                                    {Icon ? <Icon aria-hidden className="h-4 w-4" /> : null}
                                </div>
                                <p className="mt-2 font-mono text-2xl font-semibold tabular-nums text-foreground">{item.value}</p>
                                {item.description ? <p className="mt-1 text-xs text-muted-foreground">{item.description}</p> : null}
                            </article>
                        )
                    })}
                </div>
            </section>
        )
    }

    if (block.type === "table") {
        const activate = (row: AppTableRow) => {
            if (!block.action) return
            const rawId = block.idKey ? row[block.idKey] : undefined
            runAction({ id: block.action, label: block.action }, {
                itemId: rawId === null || rawId === undefined ? undefined : String(rawId),
                value: row,
            })
        }
        const keyActivate = (event: KeyboardEvent<HTMLTableRowElement>, row: AppTableRow) => {
            if (!block.action || (event.key !== "Enter" && event.key !== " ")) return
            event.preventDefault()
            activate(row)
        }

        return (
            <section className="overflow-hidden rounded-lg border border-border bg-card">
                {block.title ? <div className="border-b border-border px-4 py-3"><BlockTitle>{block.title}</BlockTitle></div> : null}
                {block.rows.length === 0 ? (
                    <p className="px-4 py-10 text-center text-sm text-muted-foreground">{block.empty ?? "No records"}</p>
                ) : (
                    <div className="overflow-x-auto">
                        <table className="w-full border-collapse text-sm">
                            <thead className="bg-surface-raised text-xs text-muted-foreground">
                                <tr>
                                    {block.columns.map((column) => (
                                        <th key={column.key} className={cn("border-b border-border px-4 py-2.5 font-medium", column.align === "center" ? "text-center" : column.align === "right" ? "text-right" : "text-left")}>{column.label}</th>
                                    ))}
                                    {block.action ? <th className="w-10 border-b border-border" aria-label="Open" /> : null}
                                </tr>
                            </thead>
                            <tbody>
                                {block.rows.map((row, rowIndex) => (
                                    <tr
                                        key={`${index}-${rowIndex}`}
                                        role={block.action ? "button" : undefined}
                                        tabIndex={block.action ? 0 : undefined}
                                        aria-disabled={busy !== undefined || undefined}
                                        onClick={() => busy === undefined && activate(row)}
                                        onKeyDown={(event) => busy === undefined && keyActivate(event, row)}
                                        className={cn("border-b border-border last:border-0", block.action && "cursor-pointer transition-colors duration-fast hover:bg-surface-hover focus-visible:bg-surface-hover focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring")}
                                    >
                                        {block.columns.map((column) => (
                                            <td key={column.key} className={cn("px-4 py-3 text-foreground", column.align === "center" ? "text-center" : column.align === "right" ? "text-right tabular-nums" : "text-left")}>{displayValue(row[column.key])}</td>
                                        ))}
                                        {block.action ? <td className="px-3 text-muted-foreground"><ChevronRight aria-hidden className="h-4 w-4" /></td> : null}
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                )}
            </section>
        )
    }

    if (block.type === "list") {
        const row = (item: AppListItem) => {
            const Icon = resolveIcon(item.icon)
            return (
                <>
                    {Icon ? <span className={cn("flex h-9 w-9 shrink-0 items-center justify-center rounded-md border", toneClasses[item.tone ?? "neutral"])}><Icon aria-hidden className="h-4 w-4" /></span> : null}
                    <span className="min-w-0 flex-1">
                        <span className="block truncate text-sm font-medium text-foreground">{item.label}</span>
                        {item.description ? <span className="mt-0.5 block text-xs leading-5 text-muted-foreground">{item.description}</span> : null}
                    </span>
                    {item.badge !== undefined ? <span className={cn("rounded-full border px-2 py-0.5 text-xs font-medium", toneClasses[item.tone ?? "neutral"])}>{item.badge}</span> : null}
                    {item.action ? <ChevronRight aria-hidden className="h-4 w-4 shrink-0 text-muted-foreground" /> : null}
                </>
            )
        }

        return (
            <section className="overflow-hidden rounded-lg border border-border bg-card">
                {block.title ? <div className="border-b border-border px-4 py-3"><BlockTitle>{block.title}</BlockTitle></div> : null}
                {block.items.length === 0 ? (
                    <p className="px-4 py-10 text-center text-sm text-muted-foreground">{block.empty ?? "Nothing here"}</p>
                ) : (
                    <div className="divide-y divide-border">
                        {block.items.map((item) => item.action ? (
                            <button
                                key={item.id}
                                type="button"
                                disabled={busy !== undefined}
                                onClick={() => runAction({ id: item.action!, label: item.label }, { itemId: item.id, value: item.data })}
                                className="focus-ring flex min-h-14 w-full items-center gap-3 border-0 bg-transparent px-4 py-3 text-left transition-colors duration-fast hover:bg-surface-hover disabled:opacity-[.48]"
                            >{row(item)}</button>
                        ) : (
                            <div key={item.id} className="flex min-h-14 items-center gap-3 px-4 py-3">{row(item)}</div>
                        ))}
                    </div>
                )}
            </section>
        )
    }

    if (block.type === "actions") {
        return (
            <section className="rounded-lg border border-border bg-card p-4">
                <BlockTitle>{block.title}</BlockTitle>
                <ActionButtons actions={block.actions} busy={busy} run={(action) => runAction(action)} />
            </section>
        )
    }

    const Icon = resolveIcon(block.icon)
    return (
        <section className="flex min-h-64 flex-col items-center justify-center rounded-lg border border-dashed border-border bg-card px-6 py-12 text-center">
            {Icon ? <span className="mb-4 flex h-12 w-12 items-center justify-center rounded-lg border border-border bg-surface-raised text-muted-foreground"><Icon aria-hidden className="h-5 w-5" /></span> : null}
            <h3 className="text-base font-semibold text-foreground">{block.title}</h3>
            {block.description ? <p className="mt-1 max-w-md text-sm leading-6 text-muted-foreground">{block.description}</p> : null}
        </section>
    )
}

/**
 * The shared full-application frame. Consumer resources register a JSON-safe
 * definition in Lua; qblib owns focus, navigation, tabs, close behavior, and
 * standard content rendering while routing actions back to that resource.
 */
export function AppShell() {
    const [app, setApp] = useState<AppDefinition | null>(null)
    const [viewId, setViewId] = useState("")
    const [tabId, setTabId] = useState<string>()
    const [busy, setBusy] = useState<string>()
    const [error, setError] = useState<string>()

    const { payload, token, isOpen, respond } = useNuiRequest<OpenAppPayload, AppResult>(
        "openApp",
        useCallback((open: OpenAppPayload) => {
            const view = enabledView(open.app, open.viewId)
            setApp(open.app)
            setViewId(view?.id ?? "")
            setTabId(selectedTabId(view, open.tabId))
            setBusy(undefined)
            setError(undefined)
        }, []),
    )

    const view = useMemo(() => app?.navigation.find((item) => item.id === viewId), [app, viewId])
    const tab = useMemo(() => view?.tabs?.find((item) => item.id === tabId), [view, tabId])
    const content: AppContent | undefined = tab?.content ?? view?.content

    const close = useCallback((reason: string) => {
        if (!isOpen) return
        respond({ closed: true, reason, viewId: viewId || undefined, tabId })
    }, [isOpen, respond, tabId, viewId])

    useNuiEvent<CloseAppPayload>("closeApp", useCallback((message) => {
        if (!app || !token || message.appId !== app.id || message.token !== token) return
        close(message.reason ?? "api")
    }, [app, close, token]))

    useNuiEvent<UpdateAppPayload>("updateApp", useCallback((message) => {
        if (!app || !token || message.appId !== app.id || message.token !== token) return
        setApp(message.app)
    }, [app, token]))

    useEffect(() => {
        if (!app) return
        const nextView = enabledView(app, viewId)
        if (!nextView) return
        if (nextView.id !== viewId) setViewId(nextView.id)
        const nextTab = selectedTabId(nextView, tabId)
        if (nextTab !== tabId) setTabId(nextTab)
    }, [app, tabId, viewId])

    useEffect(() => {
        if (!isOpen) return
        const keydown = (event: globalThis.KeyboardEvent) => {
            if (event.key !== "Escape") return
            event.preventDefault()
            close("escape")
        }
        window.addEventListener("keydown", keydown)
        return () => window.removeEventListener("keydown", keydown)
    }, [close, isOpen])

    const runAction = useCallback(async (action: AppAction, item?: { itemId?: string; value?: unknown }) => {
        if (!app || !token || busy !== undefined || action.disabled) return
        setBusy(action.id)
        setError(undefined)
        try {
            const response = await fetchNui<AppActionResponse>("qblib:app:action", {
                appId: app.id,
                token,
                actionId: action.id,
                viewId,
                tabId,
                itemId: item?.itemId,
                value: item?.value ?? action.data,
            })
            if (response.ok === false) throw new Error(response.error ?? "The action failed.")
            if (response.result?.app) setApp(response.result.app)
            if (response.result?.close) close("action")
        } catch (actionError) {
            setError(actionError instanceof Error ? actionError.message : "The action failed.")
        } finally {
            setBusy(undefined)
        }
    }, [app, busy, close, tabId, token, viewId])

    if (!isOpen || !payload || !app || !view || !token) return null

    const AppIcon = resolveIcon(app.icon)
    const ViewIcon = resolveIcon(view.icon)
    const width = Math.min(Math.max(app.width ?? 1180, 720), 1600)
    const height = Math.min(Math.max(app.height ?? 720, 480), 960)

    return (
        <div className="pointer-events-auto fixed inset-0 z-overlay flex items-center justify-center bg-modal-overlay p-4">
            <main
                aria-label={app.title}
                className="flex max-h-[calc(100dvh-2rem)] max-w-[calc(100vw-2rem)] overflow-hidden rounded-xl border border-border bg-background text-foreground shadow-modal duration-dialog ease-entry animate-in fade-in-0 zoom-in-95"
                style={{ width, height }}
            >
                <aside className="flex w-64 shrink-0 flex-col border-r border-border bg-card">
                    <header className="flex min-h-[76px] items-center gap-3 border-b border-border px-4 py-4">
                        <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg border border-brand-border bg-brand-soft text-primary">
                            {AppIcon ? <AppIcon aria-hidden className="h-5 w-5" /> : <span className="text-sm font-semibold">{app.title.slice(0, 1).toUpperCase()}</span>}
                        </span>
                        <span className="min-w-0">
                            <span className="block truncate text-sm font-semibold">{app.title}</span>
                            {app.description ? <span className="mt-0.5 block truncate text-xs text-muted-foreground">{app.description}</span> : null}
                        </span>
                    </header>

                    <nav aria-label={`${app.title} navigation`} className="scroll-thin min-h-0 flex-1 overflow-y-auto p-3">
                        {app.navigation.map((item, index) => {
                            const Icon = resolveIcon(item.icon)
                            const active = item.id === view.id
                            const previousGroup = index > 0 ? app.navigation[index - 1]?.group : undefined
                            return (
                                <div key={item.id}>
                                    {item.group && item.group !== previousGroup ? <p className="px-2 pb-1 pt-3 text-[10px] font-semibold uppercase tracking-[.12em] text-muted-foreground first:pt-1">{item.group}</p> : null}
                                    <button
                                        type="button"
                                        disabled={item.disabled}
                                        aria-current={active ? "page" : undefined}
                                        onClick={() => {
                                            setViewId(item.id)
                                            setTabId(selectedTabId(item))
                                            setError(undefined)
                                        }}
                                        className={cn(
                                            "focus-ring relative mb-1 flex min-h-10 w-full items-center gap-3 rounded-md border border-transparent px-3 py-2 text-left text-sm font-medium transition-colors duration-fast disabled:cursor-not-allowed disabled:opacity-[.48]",
                                            active ? "border-brand-border bg-brand-soft text-foreground before:absolute before:bottom-2 before:left-0 before:top-2 before:w-0.5 before:rounded-full before:bg-primary" : "text-muted-foreground hover:bg-surface-hover hover:text-foreground",
                                        )}
                                    >
                                        {Icon ? <Icon aria-hidden className="h-4 w-4 shrink-0" /> : null}
                                        <span className="min-w-0 flex-1 truncate">{item.label}</span>
                                        {item.badge !== undefined ? <span className="rounded-full border border-border bg-surface-raised px-1.5 py-0.5 text-[10px] tabular-nums text-muted-foreground">{item.badge}</span> : null}
                                    </button>
                                </div>
                            )
                        })}
                    </nav>

                    {app.footer ? <footer className="border-t border-border px-4 py-3 text-xs text-muted-foreground">{app.footer}</footer> : null}
                </aside>

                <section className="flex min-w-0 flex-1 flex-col bg-background">
                    <header className="flex min-h-[76px] items-center gap-3 border-b border-border px-5 py-4">
                        {ViewIcon ? <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-md border border-border bg-card text-muted-foreground"><ViewIcon aria-hidden className="h-4 w-4" /></span> : null}
                        <div className="min-w-0 flex-1">
                            <h1 className="truncate text-lg font-semibold">{view.label}</h1>
                            {view.description ? <p className="mt-0.5 truncate text-xs text-muted-foreground">{view.description}</p> : null}
                        </div>
                        <Button type="button" variant="ghost" size="icon" onClick={() => close("close")} aria-label={`Close ${app.title}`} title="Close">
                            <X aria-hidden />
                        </Button>
                    </header>

                    {view.tabs?.length ? (
                        <div role="tablist" aria-label={`${view.label} sections`} className="flex min-h-11 items-end gap-1 border-b border-border px-5">
                            {view.tabs.map((item) => {
                                const active = item.id === tabId
                                return (
                                    <button
                                        key={item.id}
                                        type="button"
                                        role="tab"
                                        aria-selected={active}
                                        onClick={() => { setTabId(item.id); setError(undefined) }}
                                        className={cn("focus-ring relative flex h-10 items-center gap-2 rounded-t-md border-0 bg-transparent px-3 text-sm font-medium transition-colors duration-fast", active ? "text-foreground after:absolute after:inset-x-2 after:bottom-0 after:h-0.5 after:rounded-full after:bg-primary" : "text-muted-foreground hover:bg-surface-hover hover:text-foreground")}
                                    >
                                        {item.label}
                                        {item.badge !== undefined ? <span className="rounded-full border border-border bg-surface-raised px-1.5 py-0.5 text-[10px] tabular-nums text-muted-foreground">{item.badge}</span> : null}
                                    </button>
                                )
                            })}
                        </div>
                    ) : null}

                    <div className="scroll-thin min-h-0 flex-1 overflow-y-auto p-5">
                        {content?.title || content?.description || content?.actions?.length ? (
                            <div className="mb-5 flex items-start justify-between gap-6">
                                <div className="min-w-0">
                                    {content.title ? <h2 className="text-base font-semibold">{content.title}</h2> : null}
                                    {content.description ? <p className="mt-1 max-w-3xl text-sm leading-6 text-muted-foreground">{content.description}</p> : null}
                                </div>
                                {content.actions?.length ? <ActionButtons actions={content.actions} busy={busy} run={(action) => runAction(action)} /> : null}
                            </div>
                        ) : null}

                        {error ? <div role="alert" className="mb-4 flex items-center gap-2 rounded-md border border-destructive/45 bg-destructive/10 px-3 py-2 text-sm text-destructive"><AlertCircle aria-hidden className="h-4 w-4 shrink-0" />{error}</div> : null}

                        <div className="space-y-4">
                            {content?.blocks?.length ? content.blocks.map((block, index) => (
                                <ContentBlock key={`${block.type}-${index}`} block={block} index={index} busy={busy} runAction={runAction} />
                            )) : (
                                <section className="flex min-h-64 flex-col items-center justify-center rounded-lg border border-dashed border-border bg-card px-6 py-12 text-center">
                                    <h3 className="text-base font-semibold">Nothing here yet</h3>
                                    <p className="mt-1 text-sm text-muted-foreground">This section is ready for its application content.</p>
                                </section>
                            )}
                        </div>
                    </div>
                </section>
            </main>
        </div>
    )
}
