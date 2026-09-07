import { useEffect, useMemo, useState } from "react"
import { Minus, Plus } from "lucide-react"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Textarea } from "@/components/ui/textarea"
import { cn } from "@/lib/cn"
import type { AppShellLabels, FieldValue, InputField, InputOption } from "@/lib/types"

const RANGE_FALLBACK_MIN = 0
const RANGE_FALLBACK_MAX = 100
const COMBOBOX_MAX_SUGGESTIONS = 8
const MAX_PATTERN_INPUT_LENGTH = 256
const TEXTUAL_TYPES = new Set<InputField["type"]>(["text", "password", "textarea", "combobox"])

export const defaultFormLabels: Pick<AppShellLabels, "required" | "invalidFormat" | "minValue" | "maxValue" | "minLength" | "maxLength" | "select"> = {
    required: "Required.",
    invalidFormat: "Invalid format.",
    minValue: "Must be at least %{value}.",
    maxValue: "Must be at most %{value}.",
    minLength: "Must be at least %{value} characters.",
    maxLength: "Must be at most %{value} characters.",
    select: "Select…",
}

function interpolate(template: string, value: string | number) {
    return template.replace("%{value}", String(value))
}

export function defaultValueFor(field: InputField): FieldValue {
    if (field.default !== undefined) {
        if (field.type === "multiselect") return Array.isArray(field.default) ? field.default.map(String) : []
        if (field.type === "select") return String(field.default)
        return field.default
    }
    if (field.type === "checkbox") return false
    if (field.type === "multiselect") return []
    if (field.type === "range") return field.min ?? RANGE_FALLBACK_MIN
    if (field.type === "number") return 0
    return ""
}

export function createFieldValues(fields: InputField[], previous?: Record<string, FieldValue>) {
    const values: Record<string, FieldValue> = {}
    for (const field of fields) {
        values[field.id] = previous && Object.prototype.hasOwnProperty.call(previous, field.id)
            ? previous[field.id]
            : defaultValueFor(field)
    }
    return values
}

export function fieldOptions(field: InputField, values: Record<string, FieldValue>) {
    return field.dependsOn
        ? field.optionsByValue?.[String(values[field.dependsOn] ?? "")] ?? []
        : field.options ?? []
}

export function isFieldVisible(field: InputField, values: Record<string, FieldValue>) {
    return !field.visibleWhen || values[field.visibleWhen.fieldId] === field.visibleWhen.equals
}

export function validateFields(fields: InputField[], values: Record<string, FieldValue>, labelOverrides?: Partial<AppShellLabels>) {
    const labels = { ...defaultFormLabels, ...labelOverrides }
    const errors: Record<string, string> = {}
    for (const field of fields) {
        if (!isFieldVisible(field, values)) continue
        const value = values[field.id]
        const empty = value === "" || value === undefined || value === null
            || (field.type === "checkbox" && value !== true)
            || (field.type === "multiselect" && (!Array.isArray(value) || value.length === 0))
        if (field.required && empty) {
            errors[field.id] = labels.required
            continue
        }
        if ((field.type === "number" || field.type === "range") && typeof value === "number") {
            if (field.min !== undefined && value < field.min) errors[field.id] = interpolate(labels.minValue, field.min)
            else if (field.max !== undefined && value > field.max) errors[field.id] = interpolate(labels.maxValue, field.max)
        }
        if (TEXTUAL_TYPES.has(field.type) && typeof value === "string") {
            if (field.minLength !== undefined && value.length < field.minLength) errors[field.id] = interpolate(labels.minLength, field.minLength)
            else if (field.maxLength !== undefined && value.length > field.maxLength) errors[field.id] = interpolate(labels.maxLength, field.maxLength)
            else if (field.pattern && value !== "" && value.length <= MAX_PATTERN_INPUT_LENGTH) {
                try {
                    if (!new RegExp(field.pattern).test(value)) errors[field.id] = labels.invalidFormat
                } catch {
                    // Invalid caller patterns are ignored; authoritative validation remains server-side.
                }
            }
        }
    }
    return errors
}

export function FormFields({ fields, values, errors, onChange, labels, idPrefix = "field", columns = 1 }: {
    fields: InputField[]
    values: Record<string, FieldValue>
    errors: Record<string, string>
    onChange: (values: Record<string, FieldValue>) => void
    labels?: Partial<AppShellLabels>
    idPrefix?: string
    columns?: 1 | 2
}) {
    const setValue = (id: string, value: FieldValue) => {
        const next = { ...values, [id]: value }
        const changed = [id]
        const visited = new Set<string>()

        // Reset dependent controls in the same state update as their parent.
        // This keeps AppShell forms and standalone dialogs identical, even
        // when a country -> state -> city chain changes several fields.
        while (changed.length) {
            const parentId = changed.shift()!
            if (visited.has(parentId)) continue
            visited.add(parentId)
            for (const field of fields) {
                if (field.dependsOn !== parentId) continue
                const options = fieldOptions(field, next)
                const current = next[field.id]
                let replacement = current
                if (field.type === "multiselect") {
                    const allowed = new Set(options.map((option) => String(option.value)))
                    replacement = Array.isArray(current) ? current.filter((entry) => allowed.has(entry)) : []
                } else if (!options.some((option) => String(option.value) === String(current ?? ""))) {
                    const configuredDefault = field.default === undefined ? undefined : String(field.default)
                    replacement = configuredDefault && options.some((option) => String(option.value) === configuredDefault)
                        ? configuredDefault
                        : options[0] === undefined ? "" : String(options[0].value)
                }
                if (JSON.stringify(replacement) !== JSON.stringify(current)) {
                    next[field.id] = replacement
                    changed.push(field.id)
                }
            }
        }
        onChange(next)
    }

    return <div className={cn("grid gap-3", columns === 2 && "sm:grid-cols-2")}>
        {fields.filter((field) => isFieldVisible(field, values)).map((field) => {
            const id = `${idPrefix}-${field.id}`
            const error = errors[field.id]
            const errorId = `${id}-error`
            const options = fieldOptions(field, values)
            const describedBy = [field.description ? `${id}-description` : undefined, error ? errorId : undefined].filter(Boolean).join(" ") || undefined
            return <div key={field.id} className={cn("flex flex-col gap-1", columns === 2 && field.type === "textarea" && "sm:col-span-2")}>
                {field.type === "checkbox" ? <label htmlFor={id} className="focus-within-ring flex min-h-9 cursor-pointer items-center gap-2 rounded-md text-sm font-medium">
                    <input id={id} type="checkbox" className="h-4 w-4 shrink-0 rounded-sm border border-input bg-background accent-primary" checked={Boolean(values[field.id])} onChange={(event) => setValue(field.id, event.target.checked)} aria-invalid={Boolean(error)} aria-describedby={describedBy} />
                    <span>{field.label}{field.required ? <span className="text-destructive"> *</span> : null}</span>
                </label> : <>
                    <label htmlFor={id} className="text-sm font-medium leading-5">{field.label}{field.required ? <span className="text-destructive"> *</span> : null}</label>
                    {field.type === "textarea" ? <Textarea id={id} rows={field.rows ?? 3} placeholder={field.placeholder} value={String(values[field.id] ?? "")} minLength={field.minLength} maxLength={field.maxLength} onChange={(event) => setValue(field.id, event.target.value)} aria-invalid={Boolean(error)} aria-describedby={describedBy} />
                        : field.type === "number" ? <NumberField id={id} field={field} value={values[field.id]} error={error} describedBy={describedBy} labels={labels} onChange={(value) => setValue(field.id, value)} />
                        : field.type === "range" ? <div className="flex items-center gap-3"><input id={id} type="range" min={field.min ?? RANGE_FALLBACK_MIN} max={field.max ?? RANGE_FALLBACK_MAX} step={field.step ?? 1} value={Number(values[field.id] ?? field.min ?? RANGE_FALLBACK_MIN)} onChange={(event) => setValue(field.id, Number(event.target.value))} className="h-9 min-w-0 flex-1 cursor-pointer accent-primary" aria-invalid={Boolean(error)} aria-describedby={describedBy} /><RangeValueInput field={field} value={Number(values[field.id] ?? field.min ?? RANGE_FALLBACK_MIN)} error={error} describedBy={describedBy} labels={labels} onChange={(value) => setValue(field.id, value)} /></div>
                        : field.type === "select" ? <Select value={String(values[field.id] ?? "")} onValueChange={(value) => setValue(field.id, value)}><SelectTrigger id={id} aria-invalid={Boolean(error)} aria-describedby={describedBy}><SelectValue placeholder={field.placeholder ?? labels?.select ?? defaultFormLabels.select} /></SelectTrigger><SelectContent>{options.map((option) => <SelectItem key={String(option.value)} value={String(option.value)} disabled={option.disabled}>{option.label}</SelectItem>)}</SelectContent></Select>
                        : field.type === "multiselect" ? <MultiSelectField id={id} field={field} options={options} value={values[field.id]} error={error} describedBy={describedBy} onChange={(value) => setValue(field.id, value)} />
                        : field.type === "combobox" ? <ComboboxField id={id} field={field} options={options} value={values[field.id]} error={error} describedBy={describedBy} onChange={(value) => setValue(field.id, value)} />
                        : <><Input id={id} type={field.type} inputMode={field.numericOnly ? "numeric" : undefined} placeholder={field.placeholder} value={String(values[field.id] ?? "")} minLength={field.minLength} maxLength={field.maxLength} onChange={(event) => { const cleaned = field.numericOnly ? event.target.value.replace(/\D/g, "") : event.target.value; setValue(field.id, field.maxLength === undefined ? cleaned : cleaned.slice(0, field.maxLength)) }} aria-invalid={Boolean(error)} aria-describedby={describedBy} />{field.keypad ? <NumericKeypad value={String(values[field.id] ?? "")} maxLength={field.maxLength} labels={labels} onChange={(value) => setValue(field.id, value)} /> : null}</>}
                    {field.type === "number" && field.presets?.length ? <div className="grid grid-cols-4 gap-1.5">{field.presets.map((preset) => <Button key={preset.value} type="button" size="sm" variant="outline" className="font-mono text-xs" onClick={() => setValue(field.id, preset.value)}>{preset.label ?? preset.value}</Button>)}</div> : null}
                </>}
                {field.description ? <p id={`${id}-description`} className="text-xs leading-5 text-muted-foreground">{field.description}</p> : null}
                <span id={errorId} role={error ? "status" : undefined} aria-hidden={!error} className="min-h-[18px] text-xs text-destructive">{error}</span>
            </div>
        })}
    </div>
}

function NumericKeypad({ value, maxLength, labels, onChange }: { value: string; maxLength?: number; labels?: Partial<AppShellLabels>; onChange: (value: string) => void }) {
    const append = (digit: string) => { const next = `${value}${digit}`; onChange(maxLength === undefined ? next : next.slice(0, maxLength)) }
    return <div className="grid grid-cols-3 gap-1.5">{["1", "2", "3", "4", "5", "6", "7", "8", "9"].map((digit) => <Button key={digit} type="button" variant="outline" className="font-mono" onClick={() => append(digit)}>{digit}</Button>)}<Button type="button" variant="ghost" onClick={() => onChange("")}>{labels?.clear ?? "Clear"}</Button><Button type="button" variant="outline" className="font-mono" onClick={() => append("0")}>0</Button><Button type="button" variant="ghost" aria-label={labels?.backspace ?? "Backspace"} onClick={() => onChange(value.slice(0, -1))}>⌫</Button></div>
}

function NumberField({ id, field, value, error, describedBy, labels, onChange }: { id: string; field: InputField; value: FieldValue; error?: string; describedBy?: string; labels?: Partial<AppShellLabels>; onChange: (value: number) => void }) {
    const parsed = typeof value === "number" && Number.isFinite(value) ? value : 0
    const step = field.step ?? 1
    const adjust = (direction: 1 | -1) => onChange(Math.min(field.max ?? Infinity, Math.max(field.min ?? -Infinity, parsed + direction * step)))
    return <div className="flex items-center gap-2"><Input id={id} type="number" min={field.min} max={field.max} step={step} placeholder={field.placeholder} value={String(value ?? 0)} onChange={(event) => onChange(Number(event.target.value) || 0)} aria-invalid={Boolean(error)} aria-describedby={describedBy} className="number-field min-w-0 flex-1" /><Button type="button" variant="outline" size="icon" aria-label={(labels?.decrease ?? "Decrease %{field}").replace("%{field}", field.label)} disabled={field.min !== undefined && parsed <= field.min} onClick={() => adjust(-1)}><Minus aria-hidden /></Button><Button type="button" variant="outline" size="icon" aria-label={(labels?.increase ?? "Increase %{field}").replace("%{field}", field.label)} disabled={field.max !== undefined && parsed >= field.max} onClick={() => adjust(1)}><Plus aria-hidden /></Button></div>
}

function RangeValueInput({ field, value, error, describedBy, labels, onChange }: { field: InputField; value: number; error?: string; describedBy?: string; labels?: Partial<AppShellLabels>; onChange: (value: number) => void }) {
    const [draft, setDraft] = useState(String(value))
    const min = field.min ?? RANGE_FALLBACK_MIN
    const max = field.max ?? RANGE_FALLBACK_MAX

    useEffect(() => setDraft(String(value)), [value])

    const commit = () => {
        const parsed = Number(draft)
        const next = Number.isFinite(parsed) ? Math.min(max, Math.max(min, parsed)) : value
        setDraft(String(next))
        onChange(next)
    }

    return <Input type="number" min={min} max={max} step={field.step ?? 1} inputMode="decimal" value={draft} onFocus={(event) => event.currentTarget.select()} onChange={(event) => setDraft(event.target.value)} onBlur={commit} onKeyDown={(event) => { if (event.key === "Enter") { event.preventDefault(); event.currentTarget.blur() } }} aria-label={`${field.label} ${labels?.value ?? "value"}`} aria-invalid={Boolean(error)} aria-describedby={describedBy} className="number-field h-8 w-20 shrink-0 px-2 text-right font-mono text-xs tabular-nums" />
}

function MultiSelectField({ id, field, options, value, error, describedBy, onChange }: { id: string; field: InputField; options: InputOption[]; value: FieldValue; error?: string; describedBy?: string; onChange: (value: string[]) => void }) {
    const selected = Array.isArray(value) ? value : []
    return <div id={id} role="group" aria-label={field.label} aria-invalid={Boolean(error)} aria-describedby={describedBy} className="grid gap-1 rounded-md border border-input bg-background p-1.5 sm:grid-cols-2">{options.map((option) => { const optionValue = String(option.value); const checked = selected.includes(optionValue); return <label key={optionValue} className={cn("focus-within-ring flex min-h-9 items-center gap-2 rounded-sm px-2 text-sm", option.disabled ? "cursor-not-allowed opacity-[.48]" : "cursor-pointer hover:bg-surface-hover")}><input type="checkbox" checked={checked} disabled={option.disabled} onChange={() => onChange(checked ? selected.filter((entry) => entry !== optionValue) : [...selected, optionValue])} className="h-4 w-4 accent-primary" /><span>{option.label}</span></label> })}</div>
}

function ComboboxField({ id, field, options, value, error, describedBy, onChange }: { id: string; field: InputField; options: InputOption[]; value: FieldValue; error?: string; describedBy?: string; onChange: (value: string) => void }) {
    const [open, setOpen] = useState(false)
    const text = String(value ?? "")
    const suggestions = useMemo(() => { const needle = text.trim().toLowerCase(); return (needle ? options.filter((option) => option.label.toLowerCase().includes(needle) || String(option.value).toLowerCase().includes(needle)) : options).slice(0, COMBOBOX_MAX_SUGGESTIONS) }, [options, text])
    return <div className="relative"><Input id={id} type="text" placeholder={field.placeholder} value={text} minLength={field.minLength} maxLength={field.maxLength} onChange={(event) => onChange(event.target.value)} onFocus={() => setOpen(true)} onBlur={() => window.setTimeout(() => setOpen(false), 120)} autoComplete="off" role="combobox" aria-expanded={open && suggestions.length > 0} aria-invalid={Boolean(error)} aria-describedby={describedBy} />{open && suggestions.length > 0 ? <div role="listbox" className="absolute left-0 right-0 top-full z-50 mt-1 max-h-48 overflow-y-auto rounded-lg border border-border bg-popover p-1 shadow-low">{suggestions.map((option) => { const optionValue = String(option.value); return <button key={optionValue} type="button" role="option" aria-selected={optionValue === text} disabled={option.disabled} className="focus-ring flex min-h-10 w-full items-center rounded-sm px-3 py-1.5 text-left text-sm hover:bg-surface-hover disabled:cursor-not-allowed disabled:opacity-[.48]" onMouseDown={(event) => { event.preventDefault(); onChange(optionValue); setOpen(false) }}>{option.label}</button> })}</div> : null}</div>
}
