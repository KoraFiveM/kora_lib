import { useCallback, useEffect, useState } from "react"

import type { PlacementConfirmPayload, PlacementConfirmResult } from "@/lib/types"
import { copyToClipboard } from "@/lib/clipboard"
import { useNuiEvent } from "@/lib/useNuiEvent"
import { useNuiRequest } from "@/lib/useNuiRequest"
import { Button } from "@/components/ui/button"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"

export function PlacementConfirmDialog() {
    const [copyState, setCopyState] = useState<"idle" | "copied" | "failed">("idle")
    const { payload, isOpen, respond } = useNuiRequest<PlacementConfirmPayload, PlacementConfirmResult>(
        "placement:confirm",
        undefined,
        { confirmed: false },
    )

    useNuiEvent<null | undefined>("placement:closeConfirm", () => {
        respond({ confirmed: false })
    })

    useEffect(() => {
        if (isOpen) setCopyState("idle")
    }, [isOpen, payload])

    const handleOpenChange = useCallback((open: boolean) => {
        if (!open) respond({ confirmed: false })
    }, [respond])

    const copyData = useCallback(async () => {
        if (!payload) return false

        try {
            if (!(await copyToClipboard(payload.snippet))) throw new Error("copy failed")
            setCopyState("copied")
            return true
        } catch {
            setCopyState("failed")
            return false
        }
    }, [payload])

    const copyAndFinish = useCallback(async () => {
        if (await copyData()) respond({ confirmed: true })
    }, [copyData, respond])

    if (!isOpen || !payload) return null

    return (
        <Dialog open onOpenChange={handleOpenChange}>
            <DialogContent className="max-w-xl">
                <DialogHeader>
                    <DialogTitle>Finish entity placement</DialogTitle>
                </DialogHeader>

                <div className="space-y-2">
                    <div className="flex items-center justify-between gap-3">
                        <p className="text-xs font-medium text-muted-foreground">Generated placement data</p>
                        <span className="max-w-64 truncate rounded-xs border border-brand-border bg-brand-soft px-1.5 py-0.5 text-xs font-medium text-foreground" title={payload.model}>
                            {payload.model}
                        </span>
                    </div>
                    <ScrollArea className="code-frame max-h-72 rounded-lg border">
                        <pre className="whitespace-pre p-3 font-mono text-[11px] leading-5 tabular-nums text-foreground">{payload.snippet}</pre>
                    </ScrollArea>
                    {copyState === "failed" && (
                        <p className="text-xs text-destructive" role="alert">Clipboard copy failed. The placement is still open.</p>
                    )}
                </div>

                <DialogFooter>
                    <Button variant="ghost" onClick={() => respond({ confirmed: false })}>Keep Editing</Button>
                    <Button variant="outline" onClick={() => void copyData()}>
                        {copyState === "copied" ? "Copied" : "Copy Data"}
                    </Button>
                    <Button onClick={() => void copyAndFinish()}>Copy &amp; Finish</Button>
                </DialogFooter>
                <span className="sr-only" aria-live="polite">
                    {copyState === "copied" ? "Placement data copied to clipboard." : copyState === "failed" ? "Could not copy placement data." : ""}
                </span>
            </DialogContent>
        </Dialog>
    )
}
