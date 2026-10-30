import { lazy, Suspense, useCallback, useEffect, useMemo, useRef, useState, type FormEvent, type KeyboardEvent } from "react"
import { AlertCircle, ChevronLeft, ChevronRight, Search, X } from "lucide-react"

import { FormFields, createFieldValues, submissionValues, validateFields } from "@/components/input/FormFields"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { cn } from "@/lib/cn"
import { fetchNui } from "@/lib/fetchNui"
import { resolveIcon } from "@/lib/icon"
import type {
    AppAction, AppActionResponse, AppBlock, AppContent, AppDefinition, AppListItem, AppMapMarker,
    AppResult, AppRichValue, AppShellLabels, AppTableRow, AppTableValue, AppTone, CloseAppPayload,
    FieldValue, OpenAppPayload, UpdateAppPayload,
} from "@/lib/types"
import { useNuiEvent } from "@/lib/useNuiEvent"
import { useNuiRequest } from "@/lib/useNuiRequest"

const AppMapBlock = lazy(() => import("@/components/app/AppMapBlock"))

const defaultLabels: AppShellLabels = {
    cancel: "Cancel", confirm: "Confirm", working: "Working…", runAction: "Run action", search: "Search…",
    previous: "Previous", next: "Next", noRecords: "No records", nothingHere: "Nothing here",
    emptyTitle: "Nothing here yet", emptyDescription: "This section is ready for its application content.",
    close: "Close", select: "Select…", required: "Required.", invalidFormat: "Invalid format.",
    minValue: "Must be at least %{value}.", maxValue: "Must be at most %{value}.",
    minLength: "Must be at least %{value} characters.", maxLength: "Must be at most %{value} characters.",
    page: "Page %{current} of %{total}", recenter: "Recenter map", clear: "Clear", backspace: "Backspace",
    back: "Back", open: "Open", yes: "Yes", no: "No", map: "Map", zoomIn: "Zoom in", zoomOut: "Zoom out", value: "value",
    decrease: "Decrease %{field}", increase: "Increase %{field}",
}

const toneClasses: Record<AppTone, string> = {
    neutral: "border-border bg-surface-raised text-foreground",
    primary: "border-brand-border bg-brand-soft text-primary",
    success: "border-success/45 bg-success/10 text-success",
    warning: "border-warning/45 bg-warning/10 text-warning",
    destructive: "border-destructive/45 bg-destructive/10 text-destructive",
}

interface ActionContext { itemId?: string; value?: unknown }
interface ActiveForm { action: AppAction; source: string; context?: ActionContext }
interface NavigationPoint { viewId: string; tabId?: string }

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

function rawValue(value: AppTableValue) {
    return value && typeof value === "object" ? value.value ?? value.label ?? "" : value
}

function displayValue(value: AppTableValue, labels?: AppShellLabels) {
    const raw = rawValue(value)
    if (raw === null || raw === "") return "—"
    if (typeof raw === "boolean") return raw ? labels?.yes ?? "Yes" : labels?.no ?? "No"
    return String(raw)
}

function RichValue({ value, labels }: { value: AppTableValue; labels: AppShellLabels }) {
    if (!value || typeof value !== "object") return <>{displayValue(value, labels)}</>
    const rich = value as AppRichValue
    const Icon = resolveIcon(rich.icon)
    const contents = <span className="inline-flex items-center gap-1.5">{Icon ? <Icon aria-hidden className="h-3.5 w-3.5" /> : null}<span>{rich.label ?? displayValue(rich, labels)}</span></span>
    return <span title={rich.description} className={rich.badge ? cn("inline-flex rounded-full border px-2 py-0.5 text-xs font-medium", toneClasses[rich.tone ?? "neutral"]) : undefined}>{contents}</span>
}

function BlockTitle({ children }: { children?: string }) {
    return children ? <h3 className="text-sm font-semibold text-foreground">{children}</h3> : null
}

function ActionButtons({ actions, busy, run, labels, compact }: { actions: AppAction[]; busy?: string; run: (action: AppAction) => void; labels: AppShellLabels; compact?: boolean }) {
    return <div className="flex flex-wrap items-center gap-2">{actions.map((action) => {
        const Icon = resolveIcon(action.icon)
        const stateLabel = action.state ? "On" : "Off"
        return <Button key={action.id} type="button" size={compact ? "sm" : "default"} variant={action.variant === "primary" ? "default" : action.variant ?? "secondary"} aria-pressed={action.state} data-state={action.state === undefined ? undefined : stateLabel.toLowerCase()} disabled={action.disabled || busy !== undefined} onClick={() => run(action)}>{Icon ? <Icon aria-hidden /> : null}{busy === action.id ? labels.working : action.label}{action.state !== undefined ? <span className={cn("rounded-sm border px-1.5 py-0.5 text-[10px] font-semibold leading-none", action.state ? "border-success/45 bg-success/10 text-success" : "border-border bg-background/40 text-muted-foreground")} aria-label={`Current state: ${stateLabel}`}>{stateLabel}</span> : null}</Button>
    })}</div>
}

function ActionForm({ form, values, setValues, busy, submit, cancel, labels }: { form: ActiveForm; values: Record<string, FieldValue>; setValues: (values: Record<string, FieldValue>) => void; busy?: string; submit: () => void; cancel: () => void; labels: AppShellLabels }) {
    const fields = form.action.fields ?? []
    const errors = useMemo(() => validateFields(fields, values, labels), [fields, labels, values])
    const submitForm = (event: FormEvent) => { event.preventDefault(); if (Object.keys(errors).length === 0) submit() }
    return <form onSubmit={submitForm} className="rounded-lg border border-brand-border bg-brand-soft/30 p-4">
        <div className="mb-3"><h3 className="text-sm font-semibold">{form.action.label}</h3>{form.action.confirm ? <p className="mt-1 text-xs text-warning">{form.action.confirm}</p> : null}</div>
        <FormFields fields={fields} values={values} errors={errors} labels={labels} columns={2} idPrefix={`app-${form.source}-${form.action.id}`} onChange={setValues} />
        <div className="mt-4 flex justify-end gap-2"><Button type="button" variant="outline" onClick={cancel} disabled={busy !== undefined}>{labels.cancel}</Button><Button type="submit" disabled={busy !== undefined || Object.keys(errors).length > 0}>{busy === form.action.id ? labels.working : form.action.confirm ? labels.confirm : labels.runAction}</Button></div>
    </form>
}

function Paging({ page, pages, setPage, labels }: { page: number; pages: number; setPage: (page: number) => void; labels: AppShellLabels }) {
    if (pages <= 1) return null
    return <div className="flex items-center justify-between gap-3 border-t border-border px-4 py-3"><Button type="button" size="sm" variant="outline" disabled={page <= 0} onClick={() => setPage(page - 1)}>{labels.previous}</Button><span className="text-xs tabular-nums text-muted-foreground">{labels.page.replace("%{current}", String(page + 1)).replace("%{total}", String(pages))}</span><Button type="button" size="sm" variant="outline" disabled={page >= pages - 1} onClick={() => setPage(page + 1)}>{labels.next}</Button></div>
}

function SearchField({ value, setValue, placeholder }: { value: string; setValue: (value: string) => void; placeholder: string }) {
    return <label className="relative block w-full max-w-xs"><Search aria-hidden className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" /><Input aria-label={placeholder} value={value} onChange={(event) => setValue(event.target.value)} placeholder={placeholder} className="pl-9" /></label>
}

function TableBlock({ block, index, busy, labels, runAction }: { block: Extract<AppBlock, { type: "table" }>; index: number; busy?: string; labels: AppShellLabels; runAction: (action: AppAction, context?: ActionContext) => void }) {
    const [search, setSearch] = useState("")
    const [page, setPage] = useState(0)
    const [sort, setSort] = useState<{ key: string; direction: 1 | -1 }>()
    const rows = useMemo(() => {
        const needle = search.trim().toLowerCase()
        const filtered = needle ? block.rows.filter((row) => Object.values(row).some((value) => displayValue(value, labels).toLowerCase().includes(needle))) : block.rows
        if (!sort) return filtered
        return [...filtered].sort((a, b) => String(rawValue(a[sort.key]) ?? "").localeCompare(String(rawValue(b[sort.key]) ?? ""), undefined, { numeric: true }) * sort.direction)
    }, [block.rows, labels, search, sort])
    const pageSize = Math.max(1, block.pageSize ?? (rows.length || 1))
    const pages = Math.max(1, Math.ceil(rows.length / pageSize))
    useEffect(() => setPage((current) => Math.min(current, pages - 1)), [pages])
    const shown = rows.slice(page * pageSize, page * pageSize + pageSize)
    const activate = (row: AppTableRow) => {
        if (!block.action) return
        const id = block.idKey ? rawValue(row[block.idKey]) : undefined
        runAction({ id: block.action, label: block.action }, { itemId: id === null || id === undefined ? undefined : String(id), value: row })
    }
    const keyActivate = (event: KeyboardEvent<HTMLTableRowElement>, row: AppTableRow) => { if (block.action && (event.key === "Enter" || event.key === " ")) { event.preventDefault(); activate(row) } }
    return <section className="overflow-hidden rounded-lg border border-border bg-card">
        {block.title || block.searchable ? <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border px-4 py-3"><BlockTitle>{block.title}</BlockTitle>{block.searchable ? <SearchField value={search} setValue={(value) => { setSearch(value); setPage(0) }} placeholder={block.searchPlaceholder ?? labels.search} /> : null}</div> : null}
        {shown.length === 0 ? <p className="px-4 py-10 text-center text-sm text-muted-foreground">{block.empty ?? labels.noRecords}</p> : <div className="overflow-x-auto"><table className={cn("w-full border-collapse text-sm", block.columns.some((column) => column.width !== undefined) && "table-fixed")}><colgroup>{block.columns.map((column) => <col key={column.key} style={{ width: column.width }} />)}{block.action ? <col className="w-10" /> : null}</colgroup><thead className="bg-surface-raised text-xs text-muted-foreground"><tr>{block.columns.map((column) => <th key={column.key} className={cn("border-b border-border px-4 py-2.5 font-medium", column.align === "center" ? "text-center" : column.align === "right" ? "text-right" : "text-left")}><button type="button" disabled={!column.sortable} className="disabled:cursor-default" onClick={() => setSort((current) => ({ key: column.key, direction: current?.key === column.key ? current.direction === 1 ? -1 : 1 : 1 }))}>{column.label}{sort?.key === column.key ? sort.direction === 1 ? " ↑" : " ↓" : ""}</button></th>)}{block.action ? <th className="w-10 border-b border-border" aria-label={labels.open} /> : null}</tr></thead><tbody>{shown.map((row, rowIndex) => <tr key={`${block.id ?? index}-${rowIndex}`} role={block.action ? "button" : undefined} tabIndex={block.action ? 0 : undefined} onClick={() => busy === undefined && activate(row)} onKeyDown={(event) => busy === undefined && keyActivate(event, row)} className={cn("border-b border-border last:border-0", block.action && "cursor-pointer hover:bg-surface-hover focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring")}>{block.columns.map((column) => <td key={column.key} className={cn("break-words px-4 py-3 align-top", column.align === "center" ? "text-center" : column.align === "right" ? "text-right tabular-nums" : "text-left")}><RichValue value={row[column.key]} labels={labels} /></td>)}{block.action ? <td className="px-3 py-3 align-top text-muted-foreground"><ChevronRight aria-hidden className="h-4 w-4" /></td> : null}</tr>)}</tbody></table></div>}
        <Paging page={page} pages={pages} setPage={setPage} labels={labels} />
    </section>
}

function ListBlock({ block, index, busy, labels, runAction, openForm, activeForm, renderActiveForm }: { block: Extract<AppBlock, { type: "list" }>; index: number; busy?: string; labels: AppShellLabels; runAction: (action: AppAction, context?: ActionContext) => void; openForm: (action: AppAction, source: string, context?: ActionContext) => void; activeForm?: ActiveForm; renderActiveForm: () => React.ReactNode }) {
    const [search, setSearch] = useState("")
    const [page, setPage] = useState(0)
    const [path, setPath] = useState<string[]>([])
    const pathItems = useMemo(() => {
        const resolved: AppListItem[] = []
        let candidates = block.items
        for (const id of path) {
            const item = candidates.find((candidate) => candidate.id === id)
            if (!item) break
            resolved.push(item)
            candidates = item.children ?? []
        }
        return resolved
    }, [block.items, path])
    const items = pathItems.length ? pathItems[pathItems.length - 1].children ?? [] : block.items
    useEffect(() => { if (pathItems.length < path.length) setPath((current) => current.slice(0, pathItems.length)) }, [path.length, pathItems.length])
    const filtered = useMemo(() => { const needle = search.trim().toLowerCase(); return needle ? items.filter((item) => `${item.label} ${item.description ?? ""} ${(item.metadata ?? []).map((entry) => `${entry.label} ${entry.value}`).join(" ")}`.toLowerCase().includes(needle)) : items }, [items, search])
    const pageSize = Math.max(1, block.pageSize ?? (filtered.length || 1))
    const pages = Math.max(1, Math.ceil(filtered.length / pageSize))
    useEffect(() => setPage((current) => Math.min(current, pages - 1)), [pages])
    const shown = filtered.slice(page * pageSize, page * pageSize + pageSize)
    const card = block.layout === "grid" || block.layout === "cards"
    const media = card && block.cardStyle === "media"
    // Keep configured columns even with few items, and collapse below 260px per card.
    const gridStyle = card && block.columns ? { gridTemplateColumns: `repeat(auto-fill, minmax(min(100%, max(260px, calc((100% - ${(block.columns - 1) * 12}px) / ${block.columns}))), 1fr))` } : undefined
    const activate = (item: AppListItem) => {
        if (item.children?.length) { setPath((current) => [...current, item.id]); setPage(0); setSearch(""); return }
        if (item.action) {
            const action = typeof item.action === "string" ? { id: item.action, label: item.label } : item.action
            const context = { itemId: item.id, value: item.data ?? action.data }
            if (action.fields?.length || action.confirm) openForm(action, `list-${block.id ?? index}-${item.id}`, context)
            else runAction(action, context)
        }
    }
    return <section className={cn("overflow-hidden rounded-lg border border-border bg-card", block.scrollable && "flex min-h-0 flex-1 flex-col")}>
        {block.title || block.searchable || path.length ? <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border px-4 py-3"><div className="flex items-center gap-2">{path.length ? <Button type="button" size="icon" variant="ghost" aria-label={labels.back} onClick={() => setPath((current) => current.slice(0, -1))}><ChevronLeft aria-hidden /></Button> : null}<BlockTitle>{pathItems[pathItems.length - 1]?.label ?? block.title}</BlockTitle></div>{block.searchable ? <SearchField value={search} setValue={(value) => { setSearch(value); setPage(0) }} placeholder={block.searchPlaceholder ?? labels.search} /> : null}</div> : null}
        {shown.length === 0 ? <p className="px-4 py-10 text-center text-sm text-muted-foreground">{block.empty ?? labels.nothingHere}</p> : <div style={gridStyle} className={cn(block.scrollable && "scroll-thin min-h-0 flex-1 overflow-y-auto", card ? "grid content-start gap-3 p-3" : "divide-y divide-border", card && (media ? "grid-cols-[repeat(auto-fill,minmax(min(100%,280px),1fr))]" : "grid-cols-[repeat(auto-fit,minmax(260px,1fr))]"))}>{shown.map((item) => {
            const Icon = resolveIcon(item.icon)
            const clickable = Boolean(item.action || item.children?.length)
            const badge = item.badge !== undefined ? <span className={cn("rounded-full border px-2 py-0.5 text-xs", media && "self-start", toneClasses[item.tone ?? "neutral"])}>{item.badge}</span> : null
            const body = <>
                <span className={cn("flex shrink-0 items-center justify-center overflow-hidden", media ? "aspect-video w-full border-b border-border bg-surface-raised text-muted-foreground" : cn("border", card ? "h-14 w-14 rounded-lg" : "h-9 w-9 rounded-md", toneClasses[item.tone ?? "neutral"]))}>{item.image ? <img src={item.image} alt="" className="h-full w-full" style={{ objectFit: item.imageFit ?? block.imageFit ?? "cover" }} /> : Icon ? <Icon aria-hidden className={media ? "h-8 w-8" : "h-4 w-4"} /> : item.label.slice(0, 1)}</span>
                <span className={cn("min-w-0 flex-1", media && "flex w-full flex-col gap-3 p-4")}>
                    {media ? badge : null}
                    <span className={cn("block", media ? "flex items-start justify-between gap-3 break-words text-base font-semibold" : "text-sm font-medium")}><span className={media ? "min-w-0" : undefined}>{item.label}</span>{media && clickable ? <ChevronRight aria-hidden className="h-4 w-4 shrink-0 text-muted-foreground" /> : null}</span>
                    {item.description ? <span className={cn("block leading-5 text-muted-foreground", media ? "break-words text-sm" : "mt-0.5 text-xs")}>{item.description}</span> : null}
                    {item.metadata?.length ? <span className={cn("flex flex-wrap gap-1.5", !media && "mt-2")}>{item.metadata.map((entry) => <span key={entry.label} className={cn("rounded-full border px-2 py-0.5 text-[10px]", toneClasses[entry.tone ?? "neutral"])}>{entry.label}: {String(entry.value)}</span>)}</span> : null}
                </span>
                {!media ? badge : null}
                {!media && clickable ? <ChevronRight aria-hidden className="h-4 w-4 text-muted-foreground" /> : null}
            </>
            const source = `list-${block.id ?? index}-${item.id}`
            return <article key={item.id} data-card-style={card ? media ? "media" : "compact" : undefined} className={cn("flex min-w-0", card ? "flex-col rounded-lg border border-border bg-background" : "min-h-14 items-center px-4 py-3", media ? "overflow-hidden" : "flex-wrap gap-3", card && !media && "p-4")}>
                <div className={cn("flex min-w-0 flex-1", media ? "w-full flex-col items-start" : "items-center gap-3", clickable && "focus-ring cursor-pointer", media && clickable && "hover:bg-surface-hover")} role={clickable ? "button" : undefined} tabIndex={clickable ? 0 : undefined} onClick={() => busy === undefined && activate(item)} onKeyDown={(event) => { if (busy === undefined && (event.key === "Enter" || event.key === " ")) { event.preventDefault(); activate(item) } }}>{body}</div>
                {item.actions?.length ? <div className={cn(media && "mt-auto px-4 pb-4")}><ActionButtons compact={!media} actions={item.actions} busy={busy} labels={labels} run={(action) => action.fields?.length || action.confirm ? openForm(action, source, { itemId: item.id, value: item.data }) : runAction(action, { itemId: item.id, value: item.data ?? action.data })} /></div> : null}
                {activeForm?.source === source ? <div className={cn("w-full", media && "px-4 pb-4")}>{renderActiveForm()}</div> : null}
            </article>
        })}</div>}
        <Paging page={page} pages={pages} setPage={setPage} labels={labels} />
    </section>
}

function AlwaysFormBlock({ block, values, setValues, busy, labels, runAction }: { block: Extract<AppBlock, { type: "form" }>; values: Record<string, FieldValue>; setValues: (values: Record<string, FieldValue>) => void; busy?: string; labels: AppShellLabels; runAction: (action: AppAction, context?: ActionContext) => void }) {
    const errors = useMemo(() => validateFields(block.fields, values, labels), [block.fields, labels, values])
    const submit = (event: FormEvent) => { event.preventDefault(); if (Object.keys(errors).length === 0) runAction(block.action, { value: submissionValues(block.fields, values) }) }
    return <form onSubmit={submit} className="rounded-lg border border-border bg-card p-4"><BlockTitle>{block.title}</BlockTitle>{block.description ? <p className="mb-4 mt-1 text-sm text-muted-foreground">{block.description}</p> : <div className="mb-3" />}<FormFields fields={block.fields} values={values} errors={errors} labels={labels} columns={2} idPrefix={`app-form-${block.id}`} onChange={setValues} /><div className="mt-4 flex justify-end"><Button type="submit" disabled={busy !== undefined || Object.keys(errors).length > 0}>{busy === block.action.id ? labels.working : block.submitLabel ?? block.action.label}</Button></div></form>
}

function ContentBlock({ block, index, busy, labels, runAction, openForm, activeForm, renderActiveForm, formDraft, setFormDraft, runChange }: { block: AppBlock; index: number; busy?: string; labels: AppShellLabels; runAction: (action: AppAction, context?: ActionContext) => void; openForm: (action: AppAction, source: string, context?: ActionContext) => void; activeForm?: ActiveForm; renderActiveForm: () => React.ReactNode; formDraft: (source: string, fields: NonNullable<AppAction["fields"]>) => Record<string, FieldValue>; setFormDraft: (source: string, values: Record<string, FieldValue>) => void; runChange: (action: AppAction, values: Record<string, FieldValue>, context?: ActionContext) => void }) {
    if (block.type === "text") return <section className="rounded-lg border border-border bg-card p-4"><BlockTitle>{block.title}</BlockTitle><p className={cn("whitespace-pre-wrap text-sm leading-6 text-muted-foreground", block.title && "mt-3")}>{block.text}</p></section>
    if (block.type === "stats") return <section><BlockTitle>{block.title}</BlockTitle><div className={cn("grid grid-cols-[repeat(auto-fit,minmax(180px,1fr))] gap-3", block.title && "mt-3")}>{block.items.map((item, itemIndex) => { const Icon = resolveIcon(item.icon); return <article key={`${item.label}-${itemIndex}`} className={cn("rounded-lg border p-4", toneClasses[item.tone ?? "neutral"])}><div className="flex items-center justify-between gap-3"><p className="text-xs font-medium text-muted-foreground">{item.label}</p>{Icon ? <Icon aria-hidden className="h-4 w-4" /> : null}</div><p className="mt-2 font-mono text-2xl font-semibold tabular-nums text-foreground">{item.value}</p>{item.description ? <p className="mt-1 text-xs text-muted-foreground">{item.description}</p> : null}</article> })}</div></section>
    if (block.type === "progress") return <section><BlockTitle>{block.title}</BlockTitle><div className={cn("grid grid-cols-[repeat(auto-fit,minmax(220px,1fr))] gap-3", block.title && "mt-3")}>{block.items.map((item, itemIndex) => { const Icon = resolveIcon(item.icon); const percent = Math.max(0, Math.min(100, item.value / item.max * 100)); const fill = item.tone === "success" ? "bg-success" : item.tone === "warning" ? "bg-warning" : item.tone === "destructive" ? "bg-destructive" : "bg-primary"; return <article key={`${item.label}-${itemIndex}`} className="rounded-lg border border-border bg-card p-4"><div className="flex items-start justify-between gap-3"><div className="flex min-w-0 items-center gap-2.5">{Icon ? <span className={cn("flex h-8 w-8 shrink-0 items-center justify-center rounded-md border", toneClasses[item.tone ?? "neutral"])}><Icon aria-hidden className="h-4 w-4" /></span> : null}<div className="min-w-0"><h3 className="truncate text-sm font-semibold">{item.label}</h3>{item.description ? <p className="mt-0.5 text-xs text-muted-foreground">{item.description}</p> : null}</div></div><span className="shrink-0 font-mono text-sm font-semibold tabular-nums">{Math.round(percent)}%</span></div><div className="mt-4 h-2 overflow-hidden rounded-full bg-surface-raised" role="progressbar" aria-label={item.label} aria-valuemin={0} aria-valuemax={item.max} aria-valuenow={item.value}><div className={cn("h-full rounded-full transition-[width] duration-150", fill)} style={{ width: `${percent}%` }} /></div><div className="mt-2 flex items-center justify-between gap-3 text-xs text-muted-foreground"><span className="font-mono tabular-nums">{item.detail ?? `${item.value} / ${item.max}`}</span><span>{item.max - item.value === 0 ? "Complete" : `${Math.ceil(item.max - item.value)} remaining`}</span></div></article> })}</div></section>
    if (block.type === "table") return <TableBlock block={block} index={index} busy={busy} labels={labels} runAction={runAction} />
    if (block.type === "list") return <ListBlock block={block} index={index} busy={busy} labels={labels} runAction={runAction} openForm={openForm} activeForm={activeForm} renderActiveForm={renderActiveForm} />
    if (block.type === "actions") { const source = `block-${block.id ?? index}`; return <section className="rounded-lg border border-border bg-card p-4"><BlockTitle>{block.title}</BlockTitle><div className={cn(block.title && "mt-3")}><ActionButtons actions={block.actions} busy={busy} labels={labels} run={(action) => action.fields?.length || action.confirm ? openForm(action, source) : runAction(action)} /></div>{activeForm?.source === source ? <div className="mt-4">{renderActiveForm()}</div> : null}</section> }
    if (block.type === "form") { const source = `always-${block.id}`; return <AlwaysFormBlock block={block} values={formDraft(source, block.fields)} setValues={(values) => { setFormDraft(source, values); runChange(block.action, values) }} busy={busy} labels={labels} runAction={runAction} /> }
    if (block.type === "details") return <section className="rounded-lg border border-border bg-card p-4"><BlockTitle>{block.title}</BlockTitle><dl className={cn("grid gap-x-6 gap-y-4", block.title && "mt-4", block.columns === 1 ? "grid-cols-1" : block.columns === 3 ? "sm:grid-cols-3" : "sm:grid-cols-2")}>{block.items.map((item, itemIndex) => { const Icon = resolveIcon(item.icon); return <div key={`${item.label}-${itemIndex}`} className="min-w-0"><dt className="flex items-center gap-1.5 text-xs font-medium text-muted-foreground">{Icon ? <Icon aria-hidden className="h-3.5 w-3.5" /> : null}{item.label}</dt><dd className={cn("mt-1 break-words text-sm", item.tone && toneClasses[item.tone])}>{item.value === null || item.value === undefined || item.value === "" ? "—" : String(item.value)}</dd>{item.description ? <p className="mt-0.5 text-xs text-muted-foreground">{item.description}</p> : null}</div> })}</dl></section>
    if (block.type === "timeline") return <section className="rounded-lg border border-border bg-card p-4"><BlockTitle>{block.title}</BlockTitle>{block.items.length ? <ol className={cn("relative ml-2 border-l border-border", block.title && "mt-4")}>{block.items.map((item) => { const Icon = resolveIcon(item.icon); const source = `timeline-${block.id ?? index}-${item.id}`; return <li key={item.id} className="relative mb-5 ml-6 last:mb-0"><span className={cn("absolute -left-[35px] flex h-5 w-5 items-center justify-center rounded-full border", toneClasses[item.tone ?? "neutral"])}>{Icon ? <Icon aria-hidden className="h-3 w-3" /> : null}</span><div className="flex flex-wrap items-start justify-between gap-2"><div><h4 className="text-sm font-medium">{item.title}</h4>{item.description ? <p className="mt-1 whitespace-pre-wrap text-xs leading-5 text-muted-foreground">{item.description}</p> : null}</div>{item.timestamp ? <time className="text-xs tabular-nums text-muted-foreground">{item.timestamp}</time> : null}</div>{item.metadata?.length ? <div className="mt-2 flex flex-wrap gap-1.5">{item.metadata.map((entry) => <span key={entry.label} className={cn("rounded-full border px-2 py-0.5 text-[10px]", toneClasses[entry.tone ?? "neutral"])}>{entry.label}: {String(entry.value)}</span>)}</div> : null}{item.actions?.length ? <div className="mt-3"><ActionButtons compact actions={item.actions} busy={busy} labels={labels} run={(action) => action.fields?.length || action.confirm ? openForm(action, source, { itemId: item.id }) : runAction(action, { itemId: item.id, value: action.data })} /></div> : null}{activeForm?.source === source ? <div className="mt-3">{renderActiveForm()}</div> : null}</li> })}</ol> : <p className="py-8 text-center text-sm text-muted-foreground">{block.empty ?? labels.nothingHere}</p>}</section>
    if (block.type === "map") return <Suspense fallback={<section className="h-80 animate-pulse rounded-lg border border-border bg-card" />}><AppMapBlock block={block} labels={labels} disabled={busy !== undefined} onSelect={(marker: AppMapMarker) => { const actionId = marker.action ?? block.action; if (actionId) runAction({ id: actionId, label: marker.label }, { itemId: marker.id, value: marker.data }) }} /></Suspense>
    const Icon = resolveIcon(block.icon)
    return <section className="flex min-h-64 flex-col items-center justify-center rounded-lg border border-dashed border-border bg-card px-6 py-12 text-center">{Icon ? <span className="mb-4 flex h-12 w-12 items-center justify-center rounded-lg border border-border bg-surface-raised text-muted-foreground"><Icon aria-hidden className="h-5 w-5" /></span> : null}<h3 className="text-base font-semibold">{block.title}</h3>{block.description ? <p className="mt-1 max-w-md text-sm leading-6 text-muted-foreground">{block.description}</p> : null}</section>
}

export function AppShell() {
    const [app, setApp] = useState<AppDefinition | null>(null)
    const [viewId, setViewId] = useState("")
    const [tabId, setTabId] = useState<string>()
    const [history, setHistory] = useState<NavigationPoint[]>([])
    const [busy, setBusy] = useState<string>()
    const [error, setError] = useState<string>()
    const [notice, setNotice] = useState<{ tone: AppTone; message: string }>()
    const [activeForm, setActiveForm] = useState<ActiveForm>()
    const [drafts, setDrafts] = useState<Record<string, Record<string, FieldValue>>>({})
    const changeVersion = useRef(0)
    const { payload, token, isOpen, respond } = useNuiRequest<OpenAppPayload, AppResult>("openApp", useCallback((open: OpenAppPayload) => {
        changeVersion.current += 1
        const view = enabledView(open.app, open.viewId)
        setApp(open.app); setViewId(view?.id ?? ""); setTabId(selectedTabId(view, open.tabId)); setHistory([]); setBusy(undefined); setError(undefined); setNotice(undefined); setActiveForm(undefined); setDrafts({})
    }, []))
    useEffect(() => { changeVersion.current += 1; return () => { changeVersion.current += 1 } }, [isOpen, token])
    const labels = useMemo(() => ({ ...defaultLabels, ...app?.labels }), [app?.labels])
    const view = useMemo(() => app?.navigation.find((item) => item.id === viewId), [app, viewId])
    const tab = useMemo(() => view?.tabs?.find((item) => item.id === tabId), [view, tabId])
    const content: AppContent | undefined = tab?.content ?? view?.content
    const draftKey = useCallback((source: string) => `${viewId}:${tabId ?? ""}:${source}`, [tabId, viewId])
    const formDraft = useCallback((source: string, fields: NonNullable<AppAction["fields"]>) => createFieldValues(fields, drafts[draftKey(source)]), [draftKey, drafts])
    const setFormDraft = useCallback((source: string, values: Record<string, FieldValue>) => setDrafts((current) => ({ ...current, [draftKey(source)]: values })), [draftKey])
    const close = useCallback((reason: string) => { changeVersion.current += 1; if (isOpen) respond({ closed: true, reason, viewId: viewId || undefined, tabId }) }, [isOpen, respond, tabId, viewId])
    const navigate = useCallback((target: NavigationPoint & { replace?: boolean }, definition?: AppDefinition) => {
        const destinationApp = definition ?? app
        if (!destinationApp) return
        const next = enabledView(destinationApp, target.viewId)
        if (!next) return
        if (!target.replace) setHistory((current) => [...current, { viewId, tabId }])
        setViewId(next.id); setTabId(selectedTabId(next, target.tabId)); setActiveForm(undefined); setError(undefined)
    }, [app, tabId, viewId])
    const back = () => setHistory((current) => { const target = current[current.length - 1]; if (target) { setViewId(target.viewId); setTabId(target.tabId); setActiveForm(undefined) } return current.slice(0, -1) })

    useNuiEvent<CloseAppPayload>("closeApp", useCallback((message) => { if (app && token && message.appId === app.id && message.token === token) close(message.reason ?? "api") }, [app, close, token]))
    useNuiEvent<UpdateAppPayload>("updateApp", useCallback((message) => { if (app && token && message.appId === app.id && message.token === token) setApp(message.app) }, [app, token]))
    useEffect(() => { if (!app) return; const next = enabledView(app, viewId); if (!next) return; if (next.id !== viewId) setViewId(next.id); const nextTab = selectedTabId(next, tabId); if (nextTab !== tabId) setTabId(nextTab) }, [app, tabId, viewId])
    useEffect(() => { if (!isOpen) return; const keydown = (event: globalThis.KeyboardEvent) => { if (event.key === "Escape") { event.preventDefault(); close("escape") } }; window.addEventListener("keydown", keydown); return () => window.removeEventListener("keydown", keydown) }, [close, isOpen])

    const runAction = useCallback(async (action: AppAction, context?: ActionContext, destination?: NavigationPoint) => {
        if (!app || !token || busy !== undefined || action.disabled) return
        const version = ++changeVersion.current
        setBusy(action.id); setError(undefined); setNotice(undefined)
        try {
            const response = await fetchNui<AppActionResponse>("kora_lib:app:action", { appId: app.id, token, actionId: action.id, viewId: destination?.viewId ?? viewId, tabId: destination ? destination.tabId : tabId, itemId: context?.itemId, value: context?.value ?? action.data })
            if (version !== changeVersion.current) return
            if (response.ok === false) throw new Error(response.error ?? "The action failed.")
            const resultApp = response.result?.app
            if (resultApp) setApp(resultApp)
            if (response.result?.navigate) navigate(response.result.navigate, resultApp)
            if (response.result?.notice) setNotice(response.result.notice)
            if (response.result?.close) close("action")
            setActiveForm(undefined)
        } catch (actionError) {
            if (version === changeVersion.current) setError(actionError instanceof Error ? actionError.message : "The action failed.")
        } finally {
            if (version === changeVersion.current) setBusy(undefined)
        }
    }, [app, busy, close, navigate, tabId, token, viewId])

    const runChange = useCallback(async (action: AppAction, values: Record<string, FieldValue>, context?: ActionContext) => {
        if (!isOpen || !app?.onChange || !token || action.disabled || busy !== undefined) return
        const version = ++changeVersion.current
        try {
            const response = await fetchNui<AppActionResponse>("kora_lib:app:change", { appId: app.id, token, actionId: action.id, viewId, tabId, itemId: context?.itemId, value: values })
            if (version !== changeVersion.current) return
            if (response.ok === false) throw new Error(response.error ?? "The app change failed.")
            setError(undefined)
            if (response.result?.app) setApp(response.result.app)
        } catch (changeError) {
            if (version === changeVersion.current) setError(changeError instanceof Error ? changeError.message : "The app change failed.")
        }
    }, [app, busy, isOpen, tabId, token, viewId])

    const openForm = useCallback((action: AppAction, source: string, context?: ActionContext) => {
        const key = draftKey(`${source}:${action.id}`)
        setDrafts((current) => current[key] ? current : { ...current, [key]: createFieldValues(action.fields ?? []) })
        setActiveForm({ action, source, context })
    }, [draftKey])
    const renderActiveForm = () => activeForm ? <ActionForm form={activeForm} values={formDraft(`${activeForm.source}:${activeForm.action.id}`, activeForm.action.fields ?? [])} setValues={(values) => { setFormDraft(`${activeForm.source}:${activeForm.action.id}`, values); void runChange(activeForm.action, values, activeForm.context) }} busy={busy} labels={labels} cancel={() => setActiveForm(undefined)} submit={() => { const fields = activeForm.action.fields ?? []; runAction(activeForm.action, { ...activeForm.context, value: submissionValues(fields, formDraft(`${activeForm.source}:${activeForm.action.id}`, fields)) }) }} /> : null

    if (!isOpen || !payload || !app || !view || !token) return null
    const compact = app.layout === "compact"
    const AppIcon = resolveIcon(app.icon)
    const ViewIcon = resolveIcon(view.icon)
    const width = Math.min(Math.max(app.width ?? (compact ? 560 : 1180), compact ? 420 : 720), 1600)
    const height = Math.min(Math.max(app.height ?? (compact ? 640 : 720), 420), 960)
    const switchView = (id: string) => {
        const next = app.navigation.find((entry) => entry.id === id && !entry.disabled)
        if (!next) return
        const nextTabId = selectedTabId(next)
        setViewId(next.id); setTabId(nextTabId); setActiveForm(undefined); setError(undefined)
        if (next.onOpen) void runAction({ id: next.onOpen, label: next.label }, { itemId: next.id }, { viewId: next.id, tabId: nextTabId })
    }

    const rightPlaced = app.placement === "right"
    return <div className={cn("pointer-events-auto fixed inset-0 z-overlay flex p-2 sm:p-4", rightPlaced ? "items-center justify-end" : "items-center justify-center")}><main aria-label={app.title} data-layout={app.layout ?? "standard"} data-placement={app.placement ?? "center"} className="flex max-h-[calc(100dvh-1rem)] max-w-[calc(100vw-1rem)] overflow-hidden rounded-xl border border-border bg-background text-foreground shadow-modal duration-dialog ease-entry animate-in fade-in-0 zoom-in-95 sm:max-h-[calc(100dvh-2rem)] sm:max-w-[calc(100vw-2rem)]" style={{ width, height }}>
        {!compact ? <aside className="flex w-64 shrink-0 flex-col border-r border-border bg-card max-[800px]:hidden"><header className="flex min-h-[76px] items-center gap-3 border-b border-border px-4 py-4"><span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg border border-brand-border bg-brand-soft text-primary">{AppIcon ? <AppIcon aria-hidden className="h-5 w-5" /> : app.title.slice(0, 1).toUpperCase()}</span><span className="min-w-0"><span className="block truncate text-sm font-semibold">{app.title}</span>{app.description ? <span className="mt-0.5 block truncate text-xs text-muted-foreground">{app.description}</span> : null}</span></header><nav aria-label={`${app.title} navigation`} className="scroll-thin min-h-0 flex-1 overflow-y-auto p-3">{app.navigation.map((item, index) => { const Icon = resolveIcon(item.icon); const active = item.id === view.id; const previousGroup = app.navigation[index - 1]?.group; return <div key={item.id}>{item.group && item.group !== previousGroup ? <p className="px-2 pb-1 pt-3 text-[10px] font-semibold uppercase tracking-[.12em] text-muted-foreground">{item.group}</p> : null}<button type="button" disabled={item.disabled} aria-current={active ? "page" : undefined} onClick={() => switchView(item.id)} className={cn("focus-ring relative mb-1 flex min-h-10 w-full items-center gap-3 rounded-md border border-transparent px-3 py-2 text-left text-sm font-medium disabled:opacity-[.48]", active ? "border-brand-border bg-brand-soft text-foreground before:absolute before:bottom-2 before:left-0 before:top-2 before:w-0.5 before:bg-primary" : "text-muted-foreground hover:bg-surface-hover hover:text-foreground")}>{Icon ? <Icon aria-hidden className="h-4 w-4" /> : null}<span className="min-w-0 flex-1 truncate">{item.label}</span>{item.badge !== undefined ? <span className="rounded-full border border-border bg-surface-raised px-1.5 py-0.5 text-[10px]">{item.badge}</span> : null}</button></div> })}</nav>{app.footer ? <footer className="border-t border-border px-4 py-3 text-xs text-muted-foreground">{app.footer}</footer> : null}</aside> : null}
            <section className="flex min-w-0 flex-1 flex-col"><header className="flex min-h-[68px] items-center gap-3 border-b border-border px-4 py-3 sm:min-h-[76px] sm:px-5">{history.length ? <Button type="button" variant="ghost" size="icon" onClick={back} aria-label={labels.back}><ChevronLeft aria-hidden /></Button> : null}{compact && AppIcon ? <span className="flex h-9 w-9 items-center justify-center rounded-md border border-brand-border bg-brand-soft text-primary"><AppIcon aria-hidden className="h-4 w-4" /></span> : ViewIcon ? <span className="flex h-9 w-9 items-center justify-center rounded-md border border-border bg-card text-muted-foreground"><ViewIcon aria-hidden className="h-4 w-4" /></span> : null}<div className="min-w-0 flex-1"><h1 className="truncate text-lg font-semibold">{compact && app.navigation.length === 1 ? app.title : view.label}</h1>{view.description ? <p className="mt-0.5 truncate text-xs text-muted-foreground">{view.description}</p> : compact && app.description ? <p className="mt-0.5 truncate text-xs text-muted-foreground">{app.description}</p> : null}</div><Button type="button" variant="ghost" size="icon" onClick={() => close("close")} aria-label={`${labels.close} ${app.title}`} title={labels.close}><X aria-hidden /></Button></header>
            {app.navigation.length > 1 ? <div className={cn("scroll-thin flex min-h-11 gap-1 overflow-x-auto border-b border-border px-4", !compact && "min-[801px]:hidden")}>{app.navigation.map((item) => <button key={item.id} type="button" disabled={item.disabled} onClick={() => switchView(item.id)} className={cn("focus-ring relative h-10 shrink-0 px-3 text-sm font-medium", item.id === view.id ? "text-foreground after:absolute after:inset-x-2 after:bottom-0 after:h-0.5 after:bg-primary" : "text-muted-foreground")}>{item.label}</button>)}</div> : null}
            {view.tabs?.length ? <div role="tablist" aria-label={`${view.label} sections`} className="scroll-thin flex min-h-11 items-end gap-1 overflow-x-auto border-b border-border px-4 sm:px-5">{view.tabs.map((item) => <button key={item.id} type="button" role="tab" aria-selected={item.id === tabId} onClick={() => { setTabId(item.id); setActiveForm(undefined); setError(undefined) }} className={cn("focus-ring relative h-10 shrink-0 px-3 text-sm font-medium", item.id === tabId ? "text-foreground after:absolute after:inset-x-2 after:bottom-0 after:h-0.5 after:bg-primary" : "text-muted-foreground")}>{item.label}{item.badge !== undefined ? <span className="ml-2 rounded-full border border-border px-1.5 py-0.5 text-[10px]">{item.badge}</span> : null}</button>)}</div> : null}
            <div className={cn("scroll-thin min-h-0 flex-1 p-3 sm:p-5", content?.scrollable === false ? "flex flex-col overflow-hidden" : "overflow-y-auto")}>{content?.title || content?.description || content?.actions?.length ? <div className="mb-5 flex flex-wrap items-start justify-between gap-4"><div className="min-w-0">{content.title ? <h2 className="text-base font-semibold">{content.title}</h2> : null}{content.description ? <p className="mt-1 max-w-3xl text-sm leading-6 text-muted-foreground">{content.description}</p> : null}</div>{content.actions?.length ? <ActionButtons actions={content.actions} busy={busy} labels={labels} run={(action) => action.fields?.length || action.confirm ? openForm(action, "header") : runAction(action)} /> : null}</div> : null}
                {activeForm?.source === "header" ? <div className="mb-4">{renderActiveForm()}</div> : null}
                {error ? <div role="alert" className="mb-4 flex items-center gap-2 rounded-md border border-destructive/45 bg-destructive/10 px-3 py-2 text-sm text-destructive"><AlertCircle aria-hidden className="h-4 w-4" />{error}</div> : null}
                {notice ? <div role="status" className={cn("mb-4 rounded-md border px-3 py-2 text-sm", toneClasses[notice.tone])}>{notice.message}</div> : null}
                <div className={cn(content?.scrollable === false ? "flex min-h-0 flex-1 flex-col gap-4" : "space-y-4")}>{content?.blocks?.length ? content.blocks.map((block, index) => <ContentBlock key={`${block.type}-${"id" in block && block.id ? block.id : index}`} block={block} index={index} busy={busy} labels={labels} runAction={runAction} openForm={openForm} activeForm={activeForm} renderActiveForm={renderActiveForm} formDraft={(source, fields) => formDraft(source, fields)} setFormDraft={setFormDraft} runChange={runChange} />) : <section className="flex min-h-64 flex-col items-center justify-center rounded-lg border border-dashed border-border bg-card px-6 py-12 text-center"><h3 className="text-base font-semibold">{labels.emptyTitle}</h3><p className="mt-1 text-sm text-muted-foreground">{labels.emptyDescription}</p></section>}</div>
            </div>
        </section>
    </main></div>
}
