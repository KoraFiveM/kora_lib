import { useCallback, useEffect, useState } from "react"

import type { ZoneCreatorConfirmPayload, ZoneCreatorConfirmResult } from "@/lib/types"
import { copyToClipboard } from "@/lib/clipboard"
import { useNuiRequest } from "@/lib/useNuiRequest"
import { Button } from "@/components/ui/button"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { defaultZoneCreatorLabels, formatZoneCreatorLabel } from "@/lib/zoneCreatorLocale"

/**
 * Summary dialog for Kora.zones.startCreator's confirm step (see
 * modules/zones/client.lua's openConfirmDialog). Always mounted alongside
 * every other top-level NUI component; renders nothing until Lua sends
 * "zoneCreator:confirm". DialogOverlay/DialogContent already carry
 * pointer-events-auto (see components/ui/dialog.tsx) so the standard
 * wrapper works here same as everywhere else.
 */
export function ZoneConfirmDialog() {
    const [copyState, setCopyState] = useState<"idle" | "copied" | "failed">("idle")
    const { payload, isOpen, respond } = useNuiRequest<ZoneCreatorConfirmPayload, ZoneCreatorConfirmResult>(
        "zoneCreator:confirm",
        undefined,
        { confirmed: false },
    )

    useEffect(() => {
        if (isOpen) setCopyState("idle")
    }, [isOpen, payload])

    const handleOpenChange = useCallback(
        (open: boolean) => {
            if (!open) respond({ confirmed: false })
        },
        [respond],
    )

    const copySnippet = useCallback(async () => {
        if (!payload) return false

        const copied = await copyToClipboard(payload.snippet)
        setCopyState(copied ? "copied" : "failed")
        return copied
    }, [payload])

    const handleCopyAndConfirm = useCallback(async () => {
        if (await copySnippet()) respond({ confirmed: true })
    }, [copySnippet, respond])

    if (!isOpen || !payload) return null

    return (
        <Dialog open onOpenChange={handleOpenChange}>
            <DialogContent className="max-w-xl">
                <DialogHeader>
                    <DialogTitle>{formatZoneCreatorLabel(payload.labels?.confirmTitle ?? defaultZoneCreatorLabels.confirmTitle, (payload.labels ?? defaultZoneCreatorLabels).types[payload.type])}</DialogTitle>
                </DialogHeader>

                <div className="space-y-2">
                    <div className="flex items-center justify-between gap-3">
                        <p className="text-xs font-medium text-muted-foreground">{payload.labels?.generatedData ?? defaultZoneCreatorLabels.generatedData}</p>
                        <span className="rounded-xs border border-brand-border bg-brand-soft px-1.5 py-0.5 text-xs font-medium text-foreground">
                            {(payload.labels ?? defaultZoneCreatorLabels).types[payload.type]}
                        </span>
                    </div>
                    <ScrollArea className="code-frame max-h-72 rounded-lg border">
                        <pre className="whitespace-pre p-3 font-mono text-[11px] leading-5 tabular-nums text-foreground">{payload.snippet}</pre>
                    </ScrollArea>
                    {copyState === "failed" && (
                        <p className="text-xs text-destructive" role="alert">{payload.labels?.clipboardFailed ?? defaultZoneCreatorLabels.clipboardFailed}</p>
                    )}
                </div>

                <DialogFooter>
                    <Button variant="ghost" onClick={() => respond({ confirmed: false })}>
                        {payload.labels?.keepEditing ?? defaultZoneCreatorLabels.keepEditing}
                    </Button>
                    <Button variant="outline" onClick={() => void copySnippet()}>
                        {copyState === "copied" ? (payload.labels?.copied ?? defaultZoneCreatorLabels.copied) : copyState === "failed" ? (payload.labels?.copyFailed ?? defaultZoneCreatorLabels.copyFailed) : (payload.labels?.copyCode ?? defaultZoneCreatorLabels.copyCode)}
                    </Button>
                    <Button onClick={handleCopyAndConfirm}>{payload.labels?.copyConfirm ?? defaultZoneCreatorLabels.copyConfirm}</Button>
                </DialogFooter>
                <span className="sr-only" aria-live="polite">
                    {copyState === "copied" ? (payload.labels?.copiedAnnouncement ?? defaultZoneCreatorLabels.copiedAnnouncement) : copyState === "failed" ? (payload.labels?.copyFailedAnnouncement ?? defaultZoneCreatorLabels.copyFailedAnnouncement) : ""}
                </span>
            </DialogContent>
        </Dialog>
    )
}
