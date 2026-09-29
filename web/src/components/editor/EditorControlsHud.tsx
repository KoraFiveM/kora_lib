import type { ReactNode } from "react"

import { cn } from "@/lib/cn"

interface EditorControlsHudProps {
    title: ReactNode
    status?: ReactNode
    children?: ReactNode
    controls?: ReactNode
    width?: "sm" | "md"
}

/** Shared, pointer-transparent shell for qblib's in-world editing tools. */
export function EditorControlsHud({
    title,
    status,
    children,
    controls,
    width = "sm",
}: EditorControlsHudProps) {
    return (
        <section
            aria-label="Editor controls"
            className={cn(
                "pointer-events-none fixed bottom-4 left-4 z-hud max-w-[calc(100vw-2rem)] select-none rounded-xl border bg-hud p-3 text-card-foreground shadow-low",
                width === "md" ? "w-80" : "w-72"
            )}
        >
            <header className="title-rail flex min-w-0 items-center justify-between gap-3">
                <div className="min-w-0 text-sm font-semibold">{title}</div>
                {status && <div className="shrink-0 text-xs text-muted-foreground">{status}</div>}
            </header>

            {children}

            {controls && (
                <div className="mt-3 border-t pt-2">
                    <p className="mb-1 text-[10px] font-semibold uppercase tracking-wide text-muted-foreground">
                        Editor controls
                    </p>
                    <div className="space-y-1 text-xs leading-5 text-card-foreground/80">{controls}</div>
                </div>
            )}
        </section>
    )
}

export function EditorKey({ children }: { children: ReactNode }) {
    return <b className="font-medium text-foreground">{children}</b>
}
