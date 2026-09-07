import { useCallback, useMemo, useState, type FormEvent } from "react"

import { FormFields, createFieldValues, validateFields } from "@/components/input/FormFields"
import { Button } from "@/components/ui/button"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import type { FieldValue, InputDialogResult, OpenInputDialogPayload } from "@/lib/types"
import { useNuiRequest } from "@/lib/useNuiRequest"

export function InputDialogContainer() {
    const [values, setValues] = useState<Record<string, FieldValue>>({})
    const { payload, isOpen, respond } = useNuiRequest<OpenInputDialogPayload, InputDialogResult>(
        "openInputDialog",
        useCallback((open: OpenInputDialogPayload) => setValues(createFieldValues(open.fields)), []),
    )
    const fields = payload?.fields ?? []
    const errors = useMemo(() => validateFields(fields, values, payload?.labels), [fields, payload?.labels, values])
    const hasErrors = Object.keys(errors).length > 0
    const cancel = useCallback(() => respond({ cancelled: true }), [respond])
    const submit = (event: FormEvent) => {
        event.preventDefault()
        if (!hasErrors) respond({ values })
    }

    if (!isOpen || !payload) return null
    const hasCombobox = fields.some((field) => field.type === "combobox")

    return (
        <Dialog open onOpenChange={(open) => { if (!open) cancel() }}>
            <DialogContent className={hasCombobox ? "overflow-visible sm:max-w-2xl" : "sm:max-w-md"}>
                {payload.title || payload.description ? (
                    <DialogHeader>
                        {payload.title ? <DialogTitle>{payload.title}</DialogTitle> : null}
                        {payload.description ? <DialogDescription>{payload.description}</DialogDescription> : null}
                    </DialogHeader>
                ) : null}
                <form className="flex flex-col gap-3" onSubmit={submit}>
                    <FormFields fields={fields} values={values} errors={errors} labels={payload.labels} onChange={setValues} idPrefix="dialog" />
                    <DialogFooter>
                        <Button type="button" variant="outline" onClick={cancel}>{payload.labels?.cancel ?? "Cancel"}</Button>
                        <Button type="submit" disabled={hasErrors}>{payload.labels?.confirm ?? "Confirm"}</Button>
                    </DialogFooter>
                </form>
            </DialogContent>
        </Dialog>
    )
}
