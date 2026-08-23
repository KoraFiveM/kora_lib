import { useCallback, useEffect, useMemo, useState, type FormEvent } from "react"
import { Minus, Plus } from "lucide-react"

import type { FieldValue, InputDialogResult, InputField, OpenInputDialogPayload } from "@/lib/types"
import { useNuiRequest } from "@/lib/useNuiRequest"

import { Button } from "@/components/ui/button"
import {
    Dialog,
    DialogContent,
    DialogDescription,
    DialogFooter,
    DialogHeader,
    DialogTitle,
} from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Textarea } from "@/components/ui/textarea"

function defaultValueFor(field: InputField): FieldValue {
    if (field.default !== undefined) {
        return field.default
    }

    switch (field.type) {
        case "number":
            return 0
        case "checkbox":
            return false
        // A slider always sits somewhere, so with no explicit default it starts
        // at its own floor rather than at 0 -- which could be outside the range
        // entirely (min = 10 would render the handle pinned off-scale).
        case "range":
            return field.min ?? RANGE_FALLBACK_MIN
        case "text":
        case "password":
        case "textarea":
        case "select":
        default:
            return ""
    }
}

// Only used when a `range` field omits its bounds, which is really a caller
// mistake -- a slider needs somewhere to slide. Picked over erroring so one
// malformed field can't blank the whole dialog.
const RANGE_FALLBACK_MIN = 0
const RANGE_FALLBACK_MAX = 100

// Every field type whose value is free text, and so can carry a `pattern`.
const TEXTUAL_TYPES = new Set<InputField["type"]>(["text", "password", "textarea"])

// Patterns come from the (trusted, same-server) Lua caller, but the values
// they run against can be player-typed -- and a catastrophic-backtracking
// regex over a long input blocks the CEF main thread. Capping the tested
// length bounds the worst case; anything longer just skips pattern validation
// (the Lua side must re-validate anything that matters regardless).
const MAX_PATTERN_INPUT_LENGTH = 256

// All validation is optional/opt-in (see InputField in lib/types.ts) -- a
// field with none of required/min/max/pattern set always passes. This only
// saves a round trip for obviously-invalid input; it's not a substitute for
// validating on the Lua side too.
function fieldError(field: InputField, value: FieldValue): string | null {
    if (
        field.required &&
        (value === "" || value === undefined || value === null || (field.type === "checkbox" && value !== true))
    ) {
        return "Required."
    }

    // `range` is bounds-checked alongside `number`: the slider itself can't
    // physically leave its track, but a `default` outside min/max can start it
    // out of range, and that should surface rather than submit silently.
    if ((field.type === "number" || field.type === "range") && typeof value === "number") {
        if (field.min !== undefined && value < field.min) return `Must be at least ${field.min}.`
        if (field.max !== undefined && value > field.max) return `Must be at most ${field.max}.`
    }

    if (
        TEXTUAL_TYPES.has(field.type) &&
        field.pattern &&
        typeof value === "string" &&
        value !== "" &&
        value.length <= MAX_PATTERN_INPUT_LENGTH
    ) {
        try {
            if (!new RegExp(field.pattern).test(value)) return "Invalid format."
        } catch {
            // An invalid regex from Lua shouldn't block submission -- treat it
            // as "no pattern" rather than erroring the whole dialog out.
        }
    }

    return null
}

/**
 * Self-contained, always-mounted NUI dialog for the "openInputDialog"
 * request. Invisible (renders null) until Lua sends a request, then shows a
 * form built from `payload.fields` and resolves the request with either
 * `{ values }` (submit) or `{ cancelled: true }` (cancel / escape / backdrop
 * / close button) via useNuiRequest.
 */
export function InputDialogContainer() {
    const [values, setValues] = useState<Record<string, FieldValue>>({})

    const { payload, isOpen, respond } = useNuiRequest<OpenInputDialogPayload, InputDialogResult>(
        "openInputDialog",
        useCallback((openPayload: OpenInputDialogPayload) => {
            const initial: Record<string, FieldValue> = {}
            for (const field of openPayload.fields) {
                initial[field.id] = defaultValueFor(field)
            }
            setValues(initial)
        }, []),
    )

    const fields = payload?.fields ?? []

    const errors = useMemo(() => {
        const result: Record<string, string> = {}
        for (const field of fields) {
            const error = fieldError(field, values[field.id])
            if (error) result[field.id] = error
        }
        return result
    }, [fields, values])

    const hasErrors = Object.keys(errors).length > 0

    const handleCancel = useCallback(() => respond({ cancelled: true }), [respond])

    const handleSubmit = useCallback(
        (event: FormEvent) => {
            event.preventDefault()
            if (hasErrors) return
            respond({ values })
        },
        [respond, values, hasErrors],
    )

    const updateValue = useCallback((id: string, value: FieldValue) => {
        setValues((prev) => ({ ...prev, [id]: value }))
    }, [])

    if (!isOpen || !payload) {
        return null
    }

    return (
        <Dialog
            open
            onOpenChange={(open) => {
                if (!open) handleCancel()
            }}
        >
            <DialogContent className="sm:max-w-md">
                {(payload.title || payload.description) && (
                    <DialogHeader>
                        {payload.title && <DialogTitle>{payload.title}</DialogTitle>}
                        {payload.description && <DialogDescription>{payload.description}</DialogDescription>}
                    </DialogHeader>
                )}

                <form className="flex flex-col gap-3" onSubmit={handleSubmit}>
                    <div className="flex flex-col gap-2">
                        {fields.map((field) => {
                            const error = errors[field.id]
                            const errorId = `${field.id}-error`

                            return (
                                <div key={field.id} className="flex flex-col gap-1">
                                    {field.type === "checkbox" ? (
                                        <label className="focus-within-ring flex min-h-8 cursor-pointer items-center gap-2 rounded-md text-sm font-medium leading-5">
                                            <input
                                                type="checkbox"
                                                className="h-4 w-4 shrink-0 rounded-sm border border-input bg-background text-primary accent-primary transition-colors duration-fast ease-entry hover:border-control-border-hover disabled:cursor-not-allowed disabled:opacity-[0.48] aria-[invalid=true]:border-destructive"
                                                checked={Boolean(values[field.id])}
                                                onChange={(e) => updateValue(field.id, e.target.checked)}
                                                required={field.required}
                                                aria-invalid={Boolean(error)}
                                                aria-describedby={error ? errorId : undefined}
                                            />
                                            {field.label}
                                            {field.required && <span className="text-destructive">*</span>}
                                        </label>
                                    ) : (
                                        <>
                                            <label htmlFor={field.id} className="text-sm font-medium leading-5">
                                                {field.label}
                                                {field.required && <span className="text-destructive"> *</span>}
                                            </label>

                                            {(field.type === "text" || field.type === "password") && (
                                                <Input
                                                    id={field.id}
                                                    type={field.type}
                                                    placeholder={field.placeholder}
                                                    value={String(values[field.id] ?? "")}
                                                    onChange={(e) => updateValue(field.id, e.target.value)}
                                                    required={field.required}
                                                    aria-invalid={Boolean(error)}
                                                    aria-describedby={error ? errorId : undefined}
                                                />
                                            )}

                                            {field.type === "textarea" && (
                                                <Textarea
                                                    id={field.id}
                                                    rows={field.rows ?? 3}
                                                    placeholder={field.placeholder}
                                                    value={String(values[field.id] ?? "")}
                                                    onChange={(e) => updateValue(field.id, e.target.value)}
                                                    required={field.required}
                                                    aria-invalid={Boolean(error)}
                                                    aria-describedby={error ? errorId : undefined}
                                                />
                                            )}

                                            {field.type === "number" && (
                                                <NumberField
                                                    field={field}
                                                    value={values[field.id]}
                                                    error={error}
                                                    errorId={errorId}
                                                    onChange={(value) => updateValue(field.id, value)}
                                                />
                                            )}

                                            {field.type === "range" && (
                                                // The readout is directly editable as well as visible: the
                                                // track is quick for rough adjustments, while this input is
                                                // the reliable way to land on an exact value.
                                                <div className="flex items-center gap-3">
                                                    <input
                                                        id={field.id}
                                                        type="range"
                                                        min={field.min ?? RANGE_FALLBACK_MIN}
                                                        max={field.max ?? RANGE_FALLBACK_MAX}
                                                        step={field.step ?? 1}
                                                        value={Number(values[field.id] ?? field.min ?? RANGE_FALLBACK_MIN)}
                                                        onChange={(e) => updateValue(field.id, Number(e.target.value))}
                                                        aria-invalid={Boolean(error)}
                                                        aria-describedby={error ? errorId : undefined}
                                                        className="h-8 w-full min-w-0 flex-1 cursor-pointer accent-primary"
                                                    />
                                                    <RangeValueInput
                                                        field={field}
                                                        value={Number(values[field.id] ?? field.min ?? RANGE_FALLBACK_MIN)}
                                                        error={error}
                                                        errorId={errorId}
                                                        onChange={(value) => updateValue(field.id, value)}
                                                    />
                                                </div>
                                            )}

                                            {field.type === "select" && (
                                                <Select
                                                    value={String(values[field.id] ?? "")}
                                                    onValueChange={(value) => updateValue(field.id, value)}
                                                    required={field.required}
                                                >
                                                    {/* The trigger inherits pointer-events from DialogContent;
                                                        SelectContent portals to body separately but ui/select.tsx
                                                        bakes pointer-events-auto into it -- no extra classes here. */}
                                                    <SelectTrigger
                                                        id={field.id}
                                                        aria-invalid={Boolean(error)}
                                                        aria-describedby={error ? errorId : undefined}
                                                    >
                                                        <SelectValue placeholder={field.placeholder} />
                                                    </SelectTrigger>
                                                    <SelectContent>
                                                        {field.options?.map((option) => (
                                                            <SelectItem key={option.value} value={option.value}>
                                                                {option.label}
                                                            </SelectItem>
                                                        ))}
                                                    </SelectContent>
                                                </Select>
                                            )}
                                        </>
                                    )}
                                    <span
                                        id={errorId}
                                        role={error ? "status" : undefined}
                                        aria-hidden={!error}
                                        className="min-h-[18px] text-xs text-destructive"
                                    >
                                        {error}
                                    </span>
                                </div>
                            )
                        })}
                    </div>

                    <DialogFooter>
                        <Button type="button" variant="outline" onClick={handleCancel}>
                            Cancel
                        </Button>
                        <Button type="submit" disabled={hasErrors}>
                            Confirm
                        </Button>
                    </DialogFooter>
                </form>
            </DialogContent>
        </Dialog>
    )
}

/**
 * Browser number spinners differ wildly in CEF/Chromium and do not match the
 * rest of the NUI. Keep native numeric keyboard behaviour, but replace the
 * visible arrows with full-size, focusable step controls.
 */
function NumberField({
    field,
    value,
    error,
    errorId,
    onChange,
}: {
    field: InputField
    value: FieldValue
    error: string | undefined
    errorId: string
    onChange: (value: number) => void
}) {
    const parsed = typeof value === "number" && Number.isFinite(value) ? value : 0

    const adjust = (direction: 1 | -1) => {
        const next = parsed + direction
        onChange(Math.min(field.max ?? Number.POSITIVE_INFINITY, Math.max(field.min ?? Number.NEGATIVE_INFINITY, next)))
    }

    return (
        <div className="flex items-center gap-2">
            <Input
                id={field.id}
                type="number"
                min={field.min}
                max={field.max}
                placeholder={field.placeholder}
                value={String(value ?? 0)}
                onChange={(event) => {
                    const next = Number(event.target.value)
                    onChange(Number.isNaN(next) ? 0 : next)
                }}
                required={field.required}
                aria-invalid={Boolean(error)}
                aria-describedby={error ? errorId : undefined}
                className="number-field min-w-0 flex-1"
            />
            <Button
                type="button"
                variant="outline"
                size="icon"
                aria-label={`Decrease ${field.label}`}
                disabled={field.min !== undefined && parsed <= field.min}
                onClick={() => adjust(-1)}
            >
                <Minus aria-hidden />
            </Button>
            <Button
                type="button"
                variant="outline"
                size="icon"
                aria-label={`Increase ${field.label}`}
                disabled={field.max !== undefined && parsed >= field.max}
                onClick={() => adjust(1)}
            >
                <Plus aria-hidden />
            </Button>
        </div>
    )
}

function RangeValueInput({
    field,
    value,
    error,
    errorId,
    onChange,
}: {
    field: InputField
    value: number
    error: string | undefined
    errorId: string
    onChange: (value: number) => void
}) {
    const [draft, setDraft] = useState(String(value))
    const min = field.min ?? RANGE_FALLBACK_MIN
    const max = field.max ?? RANGE_FALLBACK_MAX

    // Slider movement is external to this small field, so keep the displayed
    // number in sync unless the player is actively typing a replacement.
    useEffect(() => {
        setDraft(String(value))
    }, [value])

    const commit = () => {
        const parsed = Number(draft)
        const next = Number.isFinite(parsed) ? Math.min(max, Math.max(min, parsed)) : value
        setDraft(String(next))
        onChange(next)
    }

    return (
        <Input
            type="number"
            min={min}
            max={max}
            step={field.step ?? 1}
            inputMode="decimal"
            value={draft}
            onFocus={(event) => event.currentTarget.select()}
            onChange={(event) => setDraft(event.target.value)}
            onBlur={commit}
            onKeyDown={(event) => {
                if (event.key === "Enter") {
                    event.preventDefault()
                    event.currentTarget.blur()
                }
            }}
            aria-label={`${field.label} value`}
            aria-invalid={Boolean(error)}
            aria-describedby={error ? errorId : undefined}
            className="number-field h-8 w-16 shrink-0 px-2 text-right font-mono text-xs tabular-nums"
        />
    )
}
