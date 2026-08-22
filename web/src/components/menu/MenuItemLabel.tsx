import { resolveIcon } from "@/lib/icon"
import type { MenuItem } from "@/lib/types"

/**
 * The icon + label + optional-description body of a menu row, shared by
 * Menu.tsx's CommandItem and ContextMenu.tsx's button so the two menu
 * surfaces render items identically.
 */
export function MenuItemLabel({ item }: { item: MenuItem }) {
    const Icon = resolveIcon(item.icon)

    return (
        <>
            {Icon ? <Icon aria-hidden className="mt-0.5 h-4 w-4 shrink-0" /> : null}
            <span className="flex min-w-0 flex-col items-start gap-0.5">
                <span className="w-full truncate">{item.label}</span>
                {item.description ? (
                    <span className="w-full text-xs text-muted-foreground">{item.description}</span>
                ) : null}
            </span>
        </>
    )
}
