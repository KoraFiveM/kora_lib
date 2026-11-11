import type { ComponentProps } from "react"

import { cn } from "@/lib/cn"

/** shadcn-style <kbd>: a small raised key cap. Themed via the shared tokens only. */
function Kbd({ className, ...props }: ComponentProps<"kbd">) {
    return (
        <kbd
            className={cn(
                "pointer-events-none inline-flex h-5 min-w-5 select-none items-center justify-center rounded-sm border border-b-2 bg-muted px-1.5 font-mono text-[11px] font-medium leading-none text-foreground",
                className
            )}
            {...props}
        />
    )
}

function KbdGroup({ className, ...props }: ComponentProps<"span">) {
    return <span className={cn("inline-flex items-center gap-1", className)} {...props} />
}

export { Kbd, KbdGroup }
