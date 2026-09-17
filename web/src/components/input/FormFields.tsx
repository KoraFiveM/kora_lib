import { useEffect, useMemo, useState } from "react"
import { Minus, Plus, X } from "lucide-react"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Textarea } from "@/components/ui/textarea"
import { cn } from "@/lib/cn"
import type { AppShellLabels, FieldValue, InputField, InputOption, KeyValueEntry, VectorFieldValue } from "@/lib/types"
import { resolveIcon } from "@/lib/icon"

const RANGE_FALLBACK_MIN = 0
const RANGE_FALLBACK_MAX = 100
const COMBOBOX_MAX_SUGGESTIONS = 8
const MAX_PATTERN_INPUT_LENGTH = 256
const KEY_VALUE_PAGE_SIZE = 50
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

const MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
const WEEKDAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

function interpolate(template: string, value: string | number) {
    return template.replace("%{value}", String(value))
}

export function defaultValueFor(field: InputField): FieldValue {
    if (field.default !== undefined) {
        if (field.type === "date") return localDateInputValue(field.default)
        if (field.type === "date-range") return Array.isArray(field.default) ? field.default.slice(0, 2).map(localDateInputValue) : []
        if (field.type === "time" && (typeof field.default === "number" || field.default === true)) return localTimeInputValue(field.default === true ? Date.now() : field.default)
        if (field.type === "multiselect") return Array.isArray(field.default) ? field.default.map(String) : []
        if (field.type === "key-value") return keyValueEntries(field.default).map((entry) => ({ ...entry }))
        if (field.type === "vector") {
            const vector = vectorFieldValue(field.default)
            return vector ? { ...vector } : { x: "", y: "" }
        }
        if (field.type === "select") return String(field.default)
        return field.default
    }
    if (field.type === "checkbox") return false
    if (field.type === "multiselect") return []
    if (field.type === "date-range") return []
    if (field.type === "key-value") return []
    if (field.type === "range") return field.min ?? RANGE_FALLBACK_MIN
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

function localDateInputValue(value: unknown): string {
    if (value === true) value = Date.now()
    if (typeof value !== "number") return String(value ?? "")
    const date = new Date(value)
    if (Number.isNaN(date.getTime())) return ""
    return `${date.getFullYear().toString().padStart(4, "0")}-${(date.getMonth() + 1).toString().padStart(2, "0")}-${date.getDate().toString().padStart(2, "0")}`
}

function localTimeInputValue(value: number): string {
    const date = new Date(value)
    if (Number.isNaN(date.getTime())) return ""
    return `${date.getHours().toString().padStart(2, "0")}:${date.getMinutes().toString().padStart(2, "0")}`
}

function dateInputConstraint(value?: string | number): string | undefined {
    return value === undefined ? undefined : localDateInputValue(value)
}

function ordinal(value: number): string {
    const mod100 = value % 100
    if (mod100 >= 11 && mod100 <= 13) return `${value}th`
    return `${value}${value % 10 === 1 ? "st" : value % 10 === 2 ? "nd" : value % 10 === 3 ? "rd" : "th"}`
}

function formatDate(value: string, pattern = "DD/MM/YYYY") {
    const [year = "", month = "", day = ""] = value.split("-")
    const numericYear = Number(year)
    const numericMonth = Number(month)
    const numericDay = Number(day)
    const date = new Date(numericYear, numericMonth - 1, numericDay)
    if (!year || !month || !day || Number.isNaN(date.getTime())) return value
    const weekday = WEEKDAYS[date.getDay()]
    const replacements: Record<string, string> = {
        YYYY: year,
        YY: year.slice(-2),
        MMMM: MONTHS[numericMonth - 1] ?? "",
        MMM: MONTHS[numericMonth - 1]?.slice(0, 3) ?? "",
        MM: month,
        M: String(numericMonth),
        DD: day,
        D: String(numericDay),
        Do: ordinal(numericDay),
        dddd: weekday,
        ddd: weekday.slice(0, 3),
        dd: weekday.slice(0, 2),
        d: String(date.getDay()),
        Q: String(Math.ceil(numericMonth / 3)),
    }
    return pattern.replace(/\[[^\]]*]|YYYY|MMMM|MMM|YY|MM|DD|dddd|ddd|dd|Do|Q|M|D|d/g, (token) => token.startsWith("[") ? token.slice(1, -1) : replacements[token])
}

function colorHex(value: string) {
    const hex = value.match(/^#([\da-f]{6})(?:[\da-f]{2})?$/i)
    if (hex) return `#${hex[1].toLowerCase()}`
    const rgb = value.match(/^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)/i)
    if (!rgb) return "#ffffff"
    return `#${rgb.slice(1, 4).map((part) => Math.max(0, Math.min(255, Number(part))).toString(16).padStart(2, "0")).join("")}`
}

function formatColor(value: string, format: InputField["colorFormat"] = "hex") {
    const hex = colorHex(value)
    const red = Number.parseInt(hex.slice(1, 3), 16)
    const green = Number.parseInt(hex.slice(3, 5), 16)
    const blue = Number.parseInt(hex.slice(5, 7), 16)
    if (format === "hexa") return `${hex}ff`
    if (format === "rgb") return `rgb(${red}, ${green}, ${blue})`
    if (format === "rgba") return `rgba(${red}, ${green}, ${blue}, 1)`
    if (format === "hsl" || format === "hsla") {
        const r = red / 255; const g = green / 255; const b = blue / 255
        const max = Math.max(r, g, b); const min = Math.min(r, g, b)
        const lightness = (max + min) / 2
        const delta = max - min
        let hue = 0
        if (delta) {
            if (max === r) hue = ((g - b) / delta) % 6
            else if (max === g) hue = (b - r) / delta + 2
            else hue = (r - g) / delta + 4
            hue = Math.round(hue * 60)
            if (hue < 0) hue += 360
        }
        const saturation = delta ? delta / (1 - Math.abs(2 * lightness - 1)) : 0
        const hsl = `${hue}, ${Math.round(saturation * 100)}%, ${Math.round(lightness * 100)}%`
        return format === "hsla" ? `hsla(${hsl}, 1)` : `hsl(${hsl})`
    }
    return hex
}

function validColorDraft(value: string) {
    if (/^#[\da-f]{6}(?:[\da-f]{2})?$/i.test(value)) return true
    const rgb = value.match(/^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)(?:\s*,\s*(\d*\.?\d+))?\s*\)$/i)
    if (rgb) {
        const channels = rgb.slice(1, 4).map(Number)
        const alpha = rgb[4] === undefined ? 1 : Number(rgb[4])
        return channels.every((channel) => channel >= 0 && channel <= 255) && alpha >= 0 && alpha <= 1
    }
    const hsl = value.match(/^hsla?\(\s*(-?\d*\.?\d+)\s*,\s*(\d*\.?\d+)%\s*,\s*(\d*\.?\d+)%(?:\s*,\s*(\d*\.?\d+))?\s*\)$/i)
    if (!hsl) return false
    const saturation = Number(hsl[2])
    const lightness = Number(hsl[3])
    const alpha = hsl[4] === undefined ? 1 : Number(hsl[4])
    return Number.isFinite(Number(hsl[1])) && saturation >= 0 && saturation <= 100
        && lightness >= 0 && lightness <= 100 && alpha >= 0 && alpha <= 1
}

function vectorFieldValue(value: FieldValue | undefined): VectorFieldValue | undefined {
    return typeof value === "object" && value !== null && !Array.isArray(value)
        && "x" in value && "y" in value ? value as VectorFieldValue : undefined
}

export function submissionValues(fields: InputField[], values: Record<string, FieldValue>) {
    const submitted = { ...values }
    for (const field of fields) {
        if (field.type === "number" && !field.required && submitted[field.id] === "") {
            delete submitted[field.id]
        }
        if (field.type === "number" && field.precision !== undefined && typeof submitted[field.id] === "number") {
            const scale = 10 ** field.precision
            submitted[field.id] = Math.round((submitted[field.id] as number) * scale) / scale
        }
        if (field.returnString === false && field.type === "date" && typeof submitted[field.id] === "string") {
            const value = submitted[field.id] as string
            if (value) submitted[field.id] = new Date(`${value}T00:00:00`).getTime()
        }
        if (field.returnString === false && field.type === "date-range" && Array.isArray(submitted[field.id])) {
            submitted[field.id] = (submitted[field.id] as string[]).map((value) => new Date(`${value}T00:00:00`).getTime())
        }
        if (field.returnString === true && field.type === "date" && typeof submitted[field.id] === "string") {
            submitted[field.id] = formatDate(submitted[field.id] as string, field.dateFormat)
        }
        if (field.returnString === true && field.type === "date-range" && Array.isArray(submitted[field.id])) {
            submitted[field.id] = (submitted[field.id] as string[]).map((value) => formatDate(value, field.dateFormat))
        }
        if (field.type === "time" && typeof submitted[field.id] === "string") {
            const value = submitted[field.id] as string
            if (value) {
                const [hours, minutes] = value.split(":").map(Number)
                const date = new Date()
                date.setHours(hours, minutes, 0, 0)
                submitted[field.id] = date.getTime()
            }
        }
        if (field.type === "color" && typeof submitted[field.id] === "string") {
            submitted[field.id] = formatColor(submitted[field.id] as string, field.colorFormat)
        }
    }
    return submitted
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
            || ((field.type === "multiselect" || field.type === "date-range") && (!Array.isArray(value) || value.length === 0))
        if (field.required && empty) {
            errors[field.id] = labels.required
            continue
        }
        if ((field.type === "number" || field.type === "range") && !empty) {
            if (typeof value !== "number" || !Number.isFinite(value)) errors[field.id] = labels.invalidFormat
            else if (field.wholeNumber && !Number.isInteger(value)) errors[field.id] = "Must be a whole number."
            else if (field.min !== undefined && value < field.min) errors[field.id] = interpolate(labels.minValue, field.min)
            else if (field.max !== undefined && value > field.max) errors[field.id] = interpolate(labels.maxValue, field.max)
        }
        if (field.type === "color" && !empty && (typeof value !== "string" || !validColorDraft(value))) {
            errors[field.id] = labels.invalidFormat
        }
        if (field.type === "vector") {
            const vector = vectorFieldValue(value)
            const axes = ["x", "y", "z", "w"].slice(0, field.dimensions ?? 3) as Array<keyof VectorFieldValue>
            if (!vector || axes.some((axis) => typeof vector[axis] !== "number" || !Number.isFinite(vector[axis]))) {
                errors[field.id] = "Every coordinate must be a finite number."
            }
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
        if (field.type === "date-range" && Array.isArray(value) && value.length === 2 && String(value[0]) > String(value[1])) {
            errors[field.id] = labels.invalidFormat
        }
        if (field.type === "key-value") {
            const rows = keyValueEntries(value)
            const keys = new Set<string>()
            for (let index = 0; index < rows.length; index += 1) {
                const key = rows[index].key.trim()
                const rowNumber = index + 1
                if (!key) {
                    errors[field.id] = `Row ${rowNumber} needs a key.`
                    break
                }
                if (field.keyMode === "integer" && (!/^\d+$/.test(key) || Number(key) < 1)) {
                    errors[field.id] = `Row ${rowNumber} needs a positive whole-number key.`
                    break
                }
                const canonicalKey = field.keyMode === "integer" ? String(Number(key)) : key
                if (keys.has(canonicalKey)) {
                    errors[field.id] = `Key “${key}” is used more than once.`
                    break
                }
                keys.add(canonicalKey)
                if (!validKeyValueDraft(rows[index].value)) {
                    errors[field.id] = `Row ${rowNumber} needs a valid value.`
                    break
                }
            }
            if (!errors[field.id] && field.keyMode === "integer") {
                for (let index = 1; index <= rows.length; index += 1) {
                    if (!keys.has(String(index))) {
                        errors[field.id] = "List positions must run consecutively from 1."
                        break
                    }
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
                    replacement = Array.isArray(current) ? current.map(String).filter((entry) => allowed.has(entry)) : []
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
            const FieldIcon = resolveIcon(field.icon)
            const describedBy = [field.description ? `${id}-description` : undefined, error ? errorId : undefined].filter(Boolean).join(" ") || undefined
            return <fieldset key={field.id} disabled={field.disabled} className={cn("flex min-w-0 flex-col gap-1 disabled:opacity-[.48]", columns === 2 && (field.type === "textarea" || field.type === "date-range" || field.type === "key-value" || field.type === "vector") && "sm:col-span-2")}>
                {field.type === "checkbox" ? <label htmlFor={id} className="focus-within-ring flex min-h-9 cursor-pointer items-center gap-2 rounded-md text-sm font-medium">
                    <input id={id} type="checkbox" className="h-4 w-4 shrink-0 rounded-sm border border-input bg-background accent-primary" checked={Boolean(values[field.id])} onChange={(event) => setValue(field.id, event.target.checked)} aria-invalid={Boolean(error)} aria-describedby={describedBy} />
                    {FieldIcon ? <FieldIcon aria-hidden className="h-4 w-4" style={{ color: field.iconColor }} /> : null}<span>{field.label}{field.required ? <span className="text-destructive"> *</span> : null}</span>
                </label> : <>
                    <label htmlFor={id} className="flex items-center gap-1.5 text-sm font-medium leading-5">{FieldIcon ? <FieldIcon aria-hidden className="h-4 w-4" style={{ color: field.iconColor }} /> : null}{field.label}{field.required ? <span className="text-destructive"> *</span> : null}</label>
                    {field.type === "key-value" ? <KeyValueField id={id} field={field} value={values[field.id]} error={error} describedBy={describedBy} onChange={(value) => setValue(field.id, value)} />
                        : field.type === "vector" ? <VectorField id={id} field={field} value={values[field.id]} error={error} describedBy={describedBy} onChange={(value) => setValue(field.id, value)} />
                        : field.type === "textarea" ? <Textarea id={id} rows={field.minRows ?? field.rows ?? 3} placeholder={field.placeholder} value={String(values[field.id] ?? "")} minLength={field.minLength} maxLength={field.maxLength} onChange={(event) => setValue(field.id, event.target.value)} onInput={(event) => { if (!field.autosize) return; const area = event.currentTarget; area.style.height = "auto"; const lineHeight = Number.parseFloat(getComputedStyle(area).lineHeight) || 20; const maxHeight = field.maxRows ? lineHeight * field.maxRows + 16 : area.scrollHeight; area.style.height = `${Math.min(area.scrollHeight, maxHeight)}px` }} aria-invalid={Boolean(error)} aria-describedby={describedBy} />
                        : field.type === "number" ? <NumberField id={id} field={field} value={values[field.id]} error={error} describedBy={describedBy} labels={labels} onChange={(value) => setValue(field.id, value)} />
                        : field.type === "range" ? <div className="flex items-center gap-3"><input id={id} type="range" min={field.min ?? RANGE_FALLBACK_MIN} max={field.max ?? RANGE_FALLBACK_MAX} step={field.step ?? 1} value={Number(values[field.id] ?? field.min ?? RANGE_FALLBACK_MIN)} onChange={(event) => setValue(field.id, Number(event.target.value))} className="h-9 min-w-0 flex-1 cursor-pointer accent-primary" aria-invalid={Boolean(error)} aria-describedby={describedBy} /><RangeValueInput field={field} value={Number(values[field.id] ?? field.min ?? RANGE_FALLBACK_MIN)} error={error} describedBy={describedBy} labels={labels} onChange={(value) => setValue(field.id, value)} /></div>
                        : field.type === "select" ? field.searchable
                            ? <SearchableSelectField id={id} field={field} options={options} value={values[field.id]} error={error} describedBy={describedBy} onChange={(value) => setValue(field.id, value)} />
                            : <div className="flex items-center gap-1"><Select value={String(values[field.id] ?? "")} onValueChange={(value) => setValue(field.id, value)}><SelectTrigger id={id} aria-invalid={Boolean(error)} aria-describedby={describedBy}><SelectValue placeholder={field.placeholder ?? labels?.select ?? defaultFormLabels.select} /></SelectTrigger><SelectContent>{options.map((option) => <SelectItem key={String(option.value)} value={String(option.value)} disabled={option.disabled}>{option.label}</SelectItem>)}</SelectContent></Select>{field.clearable && values[field.id] !== "" ? <Button type="button" variant="ghost" size="icon" aria-label={`Clear ${field.label}`} onClick={() => setValue(field.id, "")}><X aria-hidden /></Button> : null}</div>
                        : field.type === "multiselect" ? <MultiSelectField id={id} field={field} options={options} value={values[field.id]} error={error} describedBy={describedBy} onChange={(value) => setValue(field.id, value)} />
                        : field.type === "combobox" ? <ComboboxField id={id} field={field} options={options} value={values[field.id]} error={error} describedBy={describedBy} onChange={(value) => setValue(field.id, value)} />
                        : field.type === "date-range" ? <DateRangeField id={id} field={field} value={values[field.id]} error={error} describedBy={describedBy} onChange={(value) => setValue(field.id, value)} />
                        : field.type === "date" ? <Input id={id} type="date" min={dateInputConstraint(field.dateMin)} max={dateInputConstraint(field.dateMax)} value={String(values[field.id] ?? "")} onChange={(event) => setValue(field.id, event.target.value)} aria-invalid={Boolean(error)} aria-describedby={describedBy} />
                        : field.type === "time" ? <div className="flex items-center gap-1"><Input id={id} type="time" lang={field.timeFormat === "12" ? "en-US" : field.timeFormat === "24" ? "en-GB" : undefined} value={String(values[field.id] ?? "")} onChange={(event) => setValue(field.id, event.target.value)} aria-invalid={Boolean(error)} aria-describedby={describedBy} />{field.clearable && values[field.id] !== "" ? <Button type="button" variant="ghost" size="icon" aria-label={`Clear ${field.label}`} onClick={() => setValue(field.id, "")}><X aria-hidden /></Button> : null}</div>
                        : field.type === "color" ? <div className="flex items-center gap-2"><Input id={id} type="color" value={colorHex(String(values[field.id] || "#ffffff"))} onChange={(event) => setValue(field.id, formatColor(event.target.value, field.colorFormat))} aria-invalid={Boolean(error)} aria-describedby={describedBy} className="h-10 w-16 shrink-0 cursor-pointer p-1" /><Input aria-label={`${field.label} value`} value={String(values[field.id] || "#ffffff")} onChange={(event) => setValue(field.id, event.target.value)} aria-invalid={Boolean(error)} aria-describedby={describedBy} className="min-w-0 font-mono text-xs" /></div>
                        : <><Input id={id} type={field.type} inputMode={field.numericOnly ? "numeric" : undefined} placeholder={field.placeholder} value={String(values[field.id] ?? "")} minLength={field.minLength} maxLength={field.maxLength} onChange={(event) => { const cleaned = field.numericOnly ? event.target.value.replace(/\D/g, "") : event.target.value; setValue(field.id, field.maxLength === undefined ? cleaned : cleaned.slice(0, field.maxLength)) }} aria-invalid={Boolean(error)} aria-describedby={describedBy} />{field.keypad ? <NumericKeypad value={String(values[field.id] ?? "")} maxLength={field.maxLength} labels={labels} onChange={(value) => setValue(field.id, value)} /> : null}</>}
                    {field.type === "number" && field.presets?.length ? <div className="grid grid-cols-4 gap-1.5">{field.presets.map((preset) => <Button key={preset.value} type="button" size="sm" variant="outline" className="font-mono text-xs" onClick={() => setValue(field.id, preset.value)}>{preset.label ?? preset.value}</Button>)}</div> : null}
                </>}
                {field.description ? <p id={`${id}-description`} className="text-xs leading-5 text-muted-foreground">{field.description}</p> : null}
                <span id={errorId} role={error ? "status" : undefined} aria-hidden={!error} className="min-h-[18px] text-xs text-destructive">{error}</span>
            </fieldset>
        })}
    </div>
}

function keyValueEntries(value: FieldValue | undefined): KeyValueEntry[] {
    if (!Array.isArray(value)) return []
    return value.filter((entry): entry is KeyValueEntry => typeof entry === "object" && entry !== null
        && typeof entry.key === "string" && typeof entry.value === "string")
}

function validKeyValueDraft(value: string) {
    const draft = value.trim()
    if (!draft) return false
    try {
        return JSON.parse(draft) !== null
    } catch {
        // Bare text is accepted as a string. Text that starts like JSON must
        // be valid JSON so a mistyped object, array, quote, or scalar cannot
        // silently turn into a different value type.
        return !/^[\[{\"]/.test(draft) && !/^(?:true|false|null|-?(?:\d|\.\d))/i.test(draft)
    }
}

function KeyValueField({ id, field, value, error, describedBy, onChange }: {
    id: string
    field: InputField
    value: FieldValue
    error?: string
    describedBy?: string
    onChange: (value: KeyValueEntry[]) => void
}) {
    const rows = keyValueEntries(value)
    const [page, setPage] = useState(0)
    const pageCount = Math.max(1, Math.ceil(rows.length / KEY_VALUE_PAGE_SIZE))
    const visiblePage = Math.min(page, pageCount - 1)
    const firstRow = visiblePage * KEY_VALUE_PAGE_SIZE
    const visibleRows = rows.slice(firstRow, firstRow + KEY_VALUE_PAGE_SIZE)

    useEffect(() => {
        if (page !== visiblePage) setPage(visiblePage)
    }, [page, visiblePage])

    const update = (index: number, property: keyof KeyValueEntry, nextValue: string) => {
        onChange(rows.map((row, rowIndex) => rowIndex === index ? { ...row, [property]: nextValue } : row))
    }
    const add = () => {
        const nextRows = [...rows, { key: field.keyMode === "integer" ? String(rows.length + 1) : "", value: "" }]
        setPage(Math.floor((nextRows.length - 1) / KEY_VALUE_PAGE_SIZE))
        onChange(nextRows)
    }
    const remove = (index: number) => {
        const remaining = rows.filter((_, rowIndex) => rowIndex !== index)
        onChange(field.keyMode === "integer"
            ? remaining.map((row, rowIndex) => ({ ...row, key: String(rowIndex + 1) }))
            : remaining)
    }

    return <div id={id} className="overflow-hidden rounded-lg border border-border bg-background" aria-invalid={Boolean(error)} aria-describedby={describedBy}>
        <div className="grid grid-cols-[minmax(0,0.65fr)_minmax(0,1.35fr)_2.25rem] gap-2 border-b border-border bg-muted/40 px-3 py-2 text-xs font-medium text-muted-foreground">
            <span>{field.keyLabel ?? "Key"}</span><span>{field.valueLabel ?? "Value (JSON or text)"}</span><span className="sr-only">Actions</span>
        </div>
        <div className="flex max-h-80 flex-col gap-2 overflow-y-auto p-2">
            {rows.length === 0 ? <p className="px-2 py-4 text-center text-sm text-muted-foreground">No rows yet.</p> : visibleRows.map((row, index) => { const rowIndex = firstRow + index; return <div key={rowIndex} className="grid grid-cols-[minmax(0,0.65fr)_minmax(0,1.35fr)_2.25rem] items-center gap-2">
                <Input aria-label={`${field.label} row ${rowIndex + 1} key`} inputMode={field.keyMode === "integer" ? "numeric" : undefined} value={row.key} onChange={(event) => update(rowIndex, "key", field.keyMode === "integer" ? event.target.value.replace(/\D/g, "") : event.target.value)} className="min-w-0 font-mono text-xs" />
                <Textarea aria-label={`${field.label} row ${rowIndex + 1} value`} rows={1} value={row.value} placeholder='Text, 42, true, {"name":"value"}…' onChange={(event) => update(rowIndex, "value", event.target.value)} className="min-h-9 min-w-0 resize-y py-2 font-mono text-xs" />
                <Button type="button" variant="ghost" size="icon" aria-label={`${field.removeRowLabel ?? "Delete row"} ${rowIndex + 1}`} title={field.removeRowLabel ?? "Delete row"} onClick={() => remove(rowIndex)}><X aria-hidden /></Button>
            </div> })}
        </div>
        <div className="flex flex-wrap items-center justify-between gap-2 border-t border-border p-2"><Button type="button" variant="outline" size="sm" onClick={add}><Plus aria-hidden />{field.addRowLabel ?? "Add row"}</Button>{pageCount > 1 ? <div className="flex items-center gap-2 text-xs text-muted-foreground"><span>Rows {firstRow + 1}–{Math.min(firstRow + KEY_VALUE_PAGE_SIZE, rows.length)} of {rows.length}</span><Button type="button" variant="outline" size="sm" disabled={visiblePage === 0} onClick={() => setPage((current) => Math.max(0, current - 1))}>Previous</Button><Button type="button" variant="outline" size="sm" disabled={visiblePage >= pageCount - 1} onClick={() => setPage((current) => Math.min(pageCount - 1, current + 1))}>Next</Button></div> : null}</div>
    </div>
}

function VectorField({ id, field, value, error, describedBy, onChange }: {
    id: string
    field: InputField
    value: FieldValue
    error?: string
    describedBy?: string
    onChange: (value: VectorFieldValue) => void
}) {
    const vector = vectorFieldValue(value) ?? { x: "", y: "", z: "", w: "" }
    const axes = ["x", "y", "z", "w"].slice(0, field.dimensions ?? 3) as Array<keyof VectorFieldValue>
    return <div role="group" aria-label={field.label} aria-invalid={Boolean(error)} aria-describedby={describedBy} className="grid grid-cols-2 gap-2 sm:grid-cols-4">
        {axes.map((axis) => <VectorAxisField key={axis} id={axis === "x" ? id : `${id}-${axis}`} label={`${field.label} ${axis.toUpperCase()}`} axis={axis} value={vector[axis]} onChange={(nextValue) => onChange({ ...vector, [axis]: nextValue })} />)}
    </div>
}

function VectorAxisField({ id, label, axis, value, onChange }: {
    id: string
    label: string
    axis: keyof VectorFieldValue
    value: number | string | undefined
    onChange: (value: number | string) => void
}) {
    const [draft, setDraft] = useState(String(value ?? ""))
    useEffect(() => setDraft(String(value ?? "")), [value])
    const update = (next: string) => {
        setDraft(next)
        const parsed = Number(next)
        onChange(next !== "" && Number.isFinite(parsed) ? parsed : next)
    }
    return <label className="grid gap-1 text-xs font-medium uppercase text-muted-foreground"><span>{axis}</span><Input id={id} aria-label={label} type="text" inputMode="decimal" value={draft} onChange={(event) => update(event.target.value)} className="font-mono tabular-nums" /></label>
}

function DateRangeField({ id, field, value, error, describedBy, onChange }: { id: string; field: InputField; value: FieldValue; error?: string; describedBy?: string; onChange: (value: string[]) => void }) {
    const dates = Array.isArray(value) ? value.map(String) : []
    const update = (index: number, next: string) => {
        const range = [String(dates[0] ?? ""), String(dates[1] ?? "")]
        range[index] = next
        onChange(range)
    }

    return <div id={id} className="grid grid-cols-2 gap-2" aria-invalid={Boolean(error)} aria-describedby={describedBy}>
        <Input aria-label={`${field.label} start`} type="date" min={dateInputConstraint(field.dateMin)} max={dateInputConstraint(field.dateMax)} value={String(dates[0] ?? "")} onChange={(event) => update(0, event.target.value)} />
        <Input aria-label={`${field.label} end`} type="date" min={dateInputConstraint(field.dateMin)} max={dateInputConstraint(field.dateMax)} value={String(dates[1] ?? "")} onChange={(event) => update(1, event.target.value)} />
    </div>
}

function NumericKeypad({ value, maxLength, labels, onChange }: { value: string; maxLength?: number; labels?: Partial<AppShellLabels>; onChange: (value: string) => void }) {
    const append = (digit: string) => { const next = `${value}${digit}`; onChange(maxLength === undefined ? next : next.slice(0, maxLength)) }
    return <div className="grid grid-cols-3 gap-1.5">{["1", "2", "3", "4", "5", "6", "7", "8", "9"].map((digit) => <Button key={digit} type="button" variant="outline" className="font-mono" onClick={() => append(digit)}>{digit}</Button>)}<Button type="button" variant="ghost" onClick={() => onChange("")}>{labels?.clear ?? "Clear"}</Button><Button type="button" variant="outline" className="font-mono" onClick={() => append("0")}>0</Button><Button type="button" variant="ghost" aria-label={labels?.backspace ?? "Backspace"} onClick={() => onChange(value.slice(0, -1))}>⌫</Button></div>
}

function NumberField({ id, field, value, error, describedBy, labels, onChange }: { id: string; field: InputField; value: FieldValue; error?: string; describedBy?: string; labels?: Partial<AppShellLabels>; onChange: (value: number | string) => void }) {
    const parsed = typeof value === "number" && Number.isFinite(value) ? value : undefined
    const [draft, setDraft] = useState(value === undefined ? "" : String(value))
    const step = field.step ?? (field.precision === undefined ? 1 : 10 ** -field.precision)
    const adjust = (direction: 1 | -1) => {
        const base = parsed ?? 0
        onChange(Math.min(field.max ?? Infinity, Math.max(field.min ?? -Infinity, base + direction * step)))
    }

    useEffect(() => setDraft(value === undefined ? "" : String(value)), [value])

    const updateDraft = (next: string) => {
        setDraft(next)
        const nextValue = Number(next)
        onChange(next !== "" && Number.isFinite(nextValue) ? nextValue : next)
    }

    return <div className="flex items-center gap-2"><Input id={id} type="text" inputMode="decimal" placeholder={field.placeholder} value={draft} onChange={(event) => updateDraft(event.target.value)} aria-invalid={Boolean(error)} aria-describedby={describedBy} className="number-field min-w-0 flex-1" /><Button type="button" variant="outline" size="icon" aria-label={(labels?.decrease ?? "Decrease %{field}").replace("%{field}", field.label)} disabled={parsed !== undefined && field.min !== undefined && parsed <= field.min} onClick={() => adjust(-1)}><Minus aria-hidden /></Button><Button type="button" variant="outline" size="icon" aria-label={(labels?.increase ?? "Increase %{field}").replace("%{field}", field.label)} disabled={parsed !== undefined && field.max !== undefined && parsed >= field.max} onClick={() => adjust(1)}><Plus aria-hidden /></Button></div>
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
    const selected = Array.isArray(value) ? value.map(String) : []
    const [query, setQuery] = useState("")
    const filteredOptions = useMemo(() => {
        const needle = query.trim().toLowerCase()
        return needle ? options.filter((option) => option.label.toLowerCase().includes(needle) || String(option.value).toLowerCase().includes(needle)) : options
    }, [options, query])
    return <div id={id} role="group" aria-label={field.label} aria-invalid={Boolean(error)} aria-describedby={describedBy} className="grid gap-1 rounded-md border border-input bg-background p-1.5">
        {field.searchable ? <Input aria-label={`Search ${field.label}`} type="search" value={query} placeholder={field.placeholder ?? "Search…"} onChange={(event) => setQuery(event.target.value)} className="mb-0.5" /> : null}
        <div className="grid gap-1 sm:grid-cols-2">{filteredOptions.map((option) => { const optionValue = String(option.value); const checked = selected.includes(optionValue); const atLimit = !checked && field.maxSelectedValues !== undefined && selected.length >= field.maxSelectedValues; return <label key={optionValue} className={cn("focus-within-ring flex min-h-9 items-center gap-2 rounded-sm px-2 text-sm", option.disabled || atLimit ? "cursor-not-allowed opacity-[.48]" : "cursor-pointer hover:bg-surface-hover")}><input type="checkbox" checked={checked} disabled={option.disabled || atLimit} onChange={() => onChange(checked ? selected.filter((entry) => entry !== optionValue) : [...selected, optionValue])} className="h-4 w-4 accent-primary" /><span>{option.label}</span></label> })}</div>
        {filteredOptions.length === 0 ? <p className="px-2 py-3 text-center text-xs text-muted-foreground">No results</p> : null}
    </div>
}

function SearchableSelectField({ id, field, options, value, error, describedBy, onChange }: { id: string; field: InputField; options: InputOption[]; value: FieldValue; error?: string; describedBy?: string; onChange: (value: string) => void }) {
    const [open, setOpen] = useState(false)
    const [query, setQuery] = useState("")
    const selectedValue = String(value ?? "")
    const selected = options.find((option) => String(option.value) === selectedValue)
    const filtered = useMemo(() => {
        const needle = query.trim().toLowerCase()
        return (needle ? options.filter((option) => option.label.toLowerCase().includes(needle) || String(option.value).toLowerCase().includes(needle)) : options).slice(0, COMBOBOX_MAX_SUGGESTIONS)
    }, [options, query])
    const listboxId = `${id}-listbox`

    const choose = (option: InputOption) => {
        if (option.disabled) return
        onChange(String(option.value))
        setQuery("")
        setOpen(false)
    }

    return <div className="flex items-center gap-1"><div className="relative min-w-0 flex-1">
        <Input
            id={id}
            role="combobox"
            aria-autocomplete="list"
            aria-haspopup="listbox"
            aria-controls={listboxId}
            aria-expanded={open}
            aria-invalid={Boolean(error)}
            aria-describedby={describedBy}
            autoComplete="off"
            value={open ? query : selected?.label ?? ""}
            placeholder={field.placeholder}
            onFocus={() => { setQuery(""); setOpen(true) }}
            onChange={(event) => { setQuery(event.target.value); setOpen(true) }}
            onBlur={() => window.setTimeout(() => { setOpen(false); setQuery("") }, 120)}
            onKeyDown={(event) => {
                if (event.key === "Escape" && open) {
                    event.preventDefault()
                    event.stopPropagation()
                    setOpen(false)
                    setQuery("")
                } else if (event.key === "Enter" && open) {
                    const first = filtered.find((option) => !option.disabled)
                    if (first) { event.preventDefault(); choose(first) }
                }
            }}
        />
        {open ? <div id={listboxId} role="listbox" className="absolute left-0 right-0 top-full z-50 mt-1 max-h-48 overflow-y-auto rounded-lg border border-border bg-popover p-1 shadow-low">
            {filtered.map((option) => <button key={String(option.value)} type="button" role="option" aria-selected={String(option.value) === selectedValue} disabled={option.disabled} className="focus-ring flex min-h-10 w-full items-center rounded-sm px-3 py-1.5 text-left text-sm hover:bg-surface-hover disabled:cursor-not-allowed disabled:opacity-[.48]" onMouseDown={(event) => { event.preventDefault(); choose(option) }} onClick={() => choose(option)}>{option.label}</button>)}
            {filtered.length === 0 ? <p className="px-2 py-3 text-center text-xs text-muted-foreground">No results</p> : null}
        </div> : null}
    </div>{field.clearable && selectedValue !== "" ? <Button type="button" variant="ghost" size="icon" aria-label={`Clear ${field.label}`} onClick={() => onChange("")}><X aria-hidden /></Button> : null}</div>
}

function ComboboxField({ id, field, options, value, error, describedBy, onChange }: { id: string; field: InputField; options: InputOption[]; value: FieldValue; error?: string; describedBy?: string; onChange: (value: string) => void }) {
    const [open, setOpen] = useState(false)
    const [activeIndex, setActiveIndex] = useState(-1)
    const text = String(value ?? "")
    const suggestions = useMemo(() => { const needle = text.trim().toLowerCase(); return (needle ? options.filter((option) => option.label.toLowerCase().includes(needle) || String(option.value).toLowerCase().includes(needle)) : options).slice(0, COMBOBOX_MAX_SUGGESTIONS) }, [options, text])
    const listboxId = `${id}-listbox`

    useEffect(() => {
        setActiveIndex(open ? suggestions.findIndex((option) => !option.disabled) : -1)
    }, [open, suggestions])

    const choose = (index: number) => {
        const option = suggestions[index]
        if (!option || option.disabled) return
        onChange(String(option.value))
        setOpen(false)
    }

    const move = (direction: 1 | -1) => {
        if (!suggestions.some((option) => !option.disabled)) return
        let next = activeIndex
        for (let attempts = 0; attempts < suggestions.length; attempts += 1) {
            next = (next + direction + suggestions.length) % suggestions.length
            if (!suggestions[next].disabled) {
                setActiveIndex(next)
                return
            }
        }
    }

    return <div className="relative">
        <Input
            id={id}
            type="text"
            placeholder={field.placeholder}
            value={text}
            minLength={field.minLength}
            maxLength={field.maxLength}
            onChange={(event) => { onChange(event.target.value); setOpen(true) }}
            onFocus={() => setOpen(true)}
            onBlur={() => window.setTimeout(() => setOpen(false), 120)}
            onKeyDown={(event) => {
                if (event.key === "ArrowDown" || event.key === "ArrowUp") {
                    event.preventDefault()
                    setOpen(true)
                    move(event.key === "ArrowDown" ? 1 : -1)
                } else if (event.key === "Enter" && open && activeIndex >= 0) {
                    event.preventDefault()
                    choose(activeIndex)
                } else if (event.key === "Escape" && open) {
                    event.preventDefault()
                    event.stopPropagation()
                    setOpen(false)
                }
            }}
            autoComplete="off"
            role="combobox"
            aria-autocomplete="list"
            aria-haspopup="listbox"
            aria-controls={listboxId}
            aria-activedescendant={open && activeIndex >= 0 ? `${listboxId}-${activeIndex}` : undefined}
            aria-expanded={open && suggestions.length > 0}
            aria-invalid={Boolean(error)}
            aria-describedby={describedBy}
        />
        {open && suggestions.length > 0 ? <div id={listboxId} role="listbox" className="absolute left-0 right-0 top-full z-50 mt-1 max-h-48 overflow-y-auto rounded-lg border border-border bg-popover p-1 shadow-low">
            {suggestions.map((option, index) => {
                const optionValue = String(option.value)
                return <button
                    id={`${listboxId}-${index}`}
                    key={optionValue}
                    type="button"
                    role="option"
                    aria-selected={optionValue === text}
                    disabled={option.disabled}
                    className={cn("focus-ring flex min-h-10 w-full items-center rounded-sm px-3 py-1.5 text-left text-sm hover:bg-surface-hover disabled:cursor-not-allowed disabled:opacity-[.48]", index === activeIndex && "bg-surface-hover")}
                    onMouseEnter={() => { if (!option.disabled) setActiveIndex(index) }}
                    onMouseDown={(event) => { event.preventDefault(); choose(index) }}
                    onClick={() => choose(index)}
                >{option.label}</button>
            })}
        </div> : null}
    </div>
}
