import { useCallback, useMemo, useState, type FormEvent } from "react"

import { FormFields, createFieldValues, submissionValues, validateFields } from "@/components/input/FormFields"
import { Button } from "@/components/ui/button"
import { useOxLocale } from "@/lib/oxLocale"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import type { FieldValue, InputDialogResult, OpenInputDialogPayload } from "@/lib/types"
import { useNuiRequest } from "@/lib/useNuiRequest"
import { cn } from "@/lib/cn"
import { dialogSizeClass } from "@/lib/dialogSize"

export function InputDialogContainer() {
    const locale = useOxLocale()
    const [values, setValues] = useState<Record<string, FieldValue>>({})
    const { payload, isOpen, respond } = useNuiRequest<OpenInputDialogPayload, InputDialogResult>(
        "openInputDialog",
        useCallback((open: OpenInputDialogPayload) => setValues(createFieldValues(open.fields)), []),
        { cancelled: true },
    )
    const fields = payload?.fields ?? []
    const errors = useMemo(() => validateFields(fields, values, payload?.labels), [fields, payload?.labels, values])
    const hasErrors = Object.keys(errors).length > 0
    const cancel = useCallback(() => {
        if (payload?.allowCancel !== false) respond({ cancelled: true })
    }, [payload?.allowCancel, respond])
    const submit = (event: FormEvent) => {
        event.preventDefault()
        if (!hasErrors) respond({ values: submissionValues(fields, values) })
    }

    if (!isOpen || !payload) return null
    const hasCombobox = fields.some((field) => field.type === "combobox")

    return (
        <Dialog open onOpenChange={(open) => { if (!open) cancel() }}>
            <DialogContent
                className={cn(dialogSizeClass(payload.size), hasCombobox && !payload.size && "overflow-visible sm:max-w-2xl")}
                onPointerDownOutside={(event) => { if (payload.dismissOnBackdrop === false) event.preventDefault() }}
                onEscapeKeyDown={(event) => { if (payload.allowCancel === false) event.preventDefault() }}
            >
                {payload.title || payload.description ? (
                    <DialogHeader>
                        {payload.title ? <DialogTitle>{payload.title}</DialogTitle> : null}
                        {payload.description ? <DialogDescription>{payload.description}</DialogDescription> : null}
                    </DialogHeader>
                ) : <DialogTitle className="sr-only">Input</DialogTitle>}
                <form className="flex flex-col gap-3" onSubmit={submit}>
                    <FormFields fields={fields} values={values} errors={errors} labels={payload.labels} onChange={setValues} idPrefix="dialog" />
                    <DialogFooter>
                        {payload.allowCancel !== false ? <Button type="button" variant="outline" onClick={cancel}>{payload.labels?.cancel ?? locale.cancel}</Button> : null}
                        <Button type="submit" disabled={hasErrors}>{payload.labels?.confirm ?? locale.confirm}</Button>
                    </DialogFooter>
                </form>
            </DialogContent>
        </Dialog>
    )
}
