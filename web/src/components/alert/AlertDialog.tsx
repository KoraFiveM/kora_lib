import { useCallback } from "react"

import type { AlertResult, OpenAlertPayload } from "@/lib/types"
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

/**
 * Confirmation dialog for the "openAlert" request (QB.nui.openAlert, see
 * modules/nui/client.lua). Always mounted alongside every other top-level NUI
 * component; renders nothing until Lua asks for it.
 *
 * Deliberately a plain Dialog rather than a second primitive: the only thing
 * radix's AlertDialog adds over this is a focus trap that refuses to close on
 * backdrop click, and `cancellable: false` already covers that case here
 * without pulling in another dependency.
 */
export function AlertDialogContainer() {
    const { payload, isOpen, respond } = useNuiRequest<OpenAlertPayload, AlertResult>("openAlert")

    // Escape and backdrop clicks route here. For a non-cancellable alert they
    // must NOT resolve: the whole point is that the player has to pick the
    // button, so silently answering "no" for them would defeat it.
    const handleOpenChange = useCallback(
        (open: boolean) => {
            if (open) return
            if (payload?.cancellable === false) return

            respond({ confirmed: false })
        },
        [payload, respond],
    )

    if (!isOpen || !payload) return null

    const cancellable = payload.cancellable !== false

    return (
        <Dialog open onOpenChange={handleOpenChange}>
            <DialogContent
                className="sm:max-w-sm"
                // Radix renders a close "X" in the corner; for a
                // non-cancellable alert that's another way out we don't want.
                hideClose={!cancellable}
            >
                <DialogHeader>
                    {payload.title && <DialogTitle>{payload.title}</DialogTitle>}
                    <DialogDescription className="whitespace-pre-line">{payload.message}</DialogDescription>
                </DialogHeader>

                <DialogFooter>
                    {cancellable && (
                        <Button variant="ghost" onClick={() => respond({ confirmed: false })}>
                            {payload.cancelLabel ?? "Cancel"}
                        </Button>
                    )}
                    <Button
                        variant={payload.destructive ? "destructive" : "default"}
                        onClick={() => respond({ confirmed: true })}
                    >
                        {payload.confirmLabel ?? "Confirm"}
                    </Button>
                </DialogFooter>
            </DialogContent>
        </Dialog>
    )
}
