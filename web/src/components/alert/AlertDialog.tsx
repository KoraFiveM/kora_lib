import { useCallback, useEffect, useState } from "react"

import type { AlertResult, OpenAlertPayload } from "@/lib/types"
import { useNuiRequest } from "@/lib/useNuiRequest"
import { Button } from "@/components/ui/button"
import { useOxLocale } from "@/lib/oxLocale"
import {
    Dialog,
    DialogContent,
    DialogDescription,
    DialogFooter,
    DialogHeader,
    DialogTitle,
} from "@/components/ui/dialog"
import { Markdown } from "@/components/ui/markdown"
import { cn } from "@/lib/cn"
import { dialogSizeClass } from "@/lib/dialogSize"

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
    const [imageFailed, setImageFailed] = useState(false)
    const locale = useOxLocale()

    useEffect(() => {
        setImageFailed(false)
    }, [payload?.image])

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
    const showCancel = cancellable && (payload.showCancel ?? true)
    const showClose = cancellable && (payload.showClose ?? true)
    const image = typeof payload.image === "string" && payload.image.length > 0 ? payload.image : undefined

    return (
        <Dialog open onOpenChange={handleOpenChange}>
            <DialogContent
                className={cn(
                    dialogSizeClass(payload.size),
                    payload.centered === false && "top-8 translate-y-0",
                    payload.overflow && "grid max-h-[calc(100dvh-2rem)] grid-rows-[auto_minmax(0,1fr)_auto] overflow-hidden",
                )}
                // Radix renders a close "X" in the corner; for a
                // non-cancellable alert that's another way out we don't want.
                hideClose={!showClose}
                onPointerDownOutside={(event) => {
                    if (!cancellable || payload.dismissOnBackdrop === false) event.preventDefault()
                }}
                onEscapeKeyDown={(event) => {
                    if (!cancellable) event.preventDefault()
                }}
            >
                {image && !imageFailed && (
                    <div className="flex h-40 items-center justify-center overflow-hidden rounded-lg border bg-surface-raised p-2">
                        <img
                            aria-hidden
                            src={image}
                            className="h-full w-full object-contain"
                            onError={() => setImageFailed(true)}
                        />
                    </div>
                )}
                <DialogHeader>
                    <DialogTitle className={payload.title ? undefined : "sr-only"}><Markdown inline>{payload.title ?? "Confirmation"}</Markdown></DialogTitle>
                </DialogHeader>

                <DialogDescription asChild>
                    <div className={cn("min-h-0 text-left", payload.overflow && "overflow-y-auto pr-2")}>
                        <Markdown allowImages>{payload.message}</Markdown>
                    </div>
                </DialogDescription>

                <DialogFooter>
                    {showCancel && (
                        <Button variant="ghost" onClick={() => respond({ confirmed: false })}>
                            {payload.cancelLabel ?? locale.cancel}
                        </Button>
                    )}
                    <Button
                        variant={payload.destructive ? "destructive" : "default"}
                        onClick={() => respond({ confirmed: true })}
                    >
                        {payload.confirmLabel ?? locale.confirm}
                    </Button>
                </DialogFooter>
            </DialogContent>
        </Dialog>
    )
}
