import { useCallback, useEffect, useState } from "react"

import type { ZoneCreatorConfirmPayload, ZoneCreatorConfirmResult } from "@/lib/types"
import { copyToClipboard } from "@/lib/clipboard"
import { useNuiRequest } from "@/lib/useNuiRequest"
import { Button } from "@/components/ui/button"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"

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
    )

    useEffect(() => {
        if (isOpen) setCopyState("idle")
    }, [isOpen, payload])

    const handleOpenChange = useCallback(
        (open: boolean) => {
            // Closed via Escape/backdrop/X, or "Keep Editing" -- either way the
            // creator session itself isn't cancelled, just this dialog.
            if (!open) respond({ confirmed: false })
        },
        [respond],
    )

    // The snippet IS the output of the creator, so copying it is the primary
    // action -- but it still confirms, because `confirmed: true` is what
    // resolves Kora.zones.startCreator's promise (and builds the real zone).
    // Splitting those apart would mean a player who clicked the obvious button
    // got their text and silently threw the zone away.
    const copySnippet = useCallback(async () => {
        if (!payload) return false

        // The snippet is still visible, so copy failure is feedback rather
        // than a reason to trap the player in this confirmation dialog.
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
                    <DialogTitle>Confirm {payload.type} zone</DialogTitle>
                </DialogHeader>

                <div className="space-y-2">
                    <div className="flex items-center justify-between gap-3">
                        <p className="text-xs font-medium text-muted-foreground">Generated zone data</p>
                        <span className="rounded-xs border border-brand-border bg-brand-soft px-1.5 py-0.5 text-xs font-medium text-foreground">
                            {payload.type}
                        </span>
                    </div>
                    <ScrollArea className="code-frame max-h-72 rounded-lg border">
                        <pre className="whitespace-pre p-3 font-mono text-[11px] leading-5 tabular-nums text-foreground">{payload.snippet}</pre>
                    </ScrollArea>
                    {copyState === "failed" && (
                        <p className="text-xs text-destructive" role="alert">Clipboard copy failed. The zone creator is still open.</p>
                    )}
                </div>

                <DialogFooter>
                    <Button variant="ghost" onClick={() => respond({ confirmed: false })}>
                        Keep Editing
                    </Button>
                    <Button variant="outline" onClick={() => void copySnippet()}>
                        {copyState === "copied" ? "Copied" : copyState === "failed" ? "Copy failed" : "Copy code"}
                    </Button>
                    <Button onClick={handleCopyAndConfirm}>Copy &amp; Confirm</Button>
                </DialogFooter>
                <span className="sr-only" aria-live="polite">
                    {copyState === "copied" ? "Zone data copied to clipboard." : copyState === "failed" ? "Could not copy zone data." : ""}
                </span>
            </DialogContent>
        </Dialog>
    )
}
