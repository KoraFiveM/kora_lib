import { useState } from "react"

import type { MenuItem } from "@/lib/types"
import { useNuiEvent } from "@/lib/useNuiEvent"
import { MenuItemLabel } from "@/components/menu/MenuItemLabel"

/** Read-only legacy qb-menu header. It never takes focus or intercepts gameplay. */
export function MenuHeader() {
    const [items, setItems] = useState<MenuItem[] | null>(null)
    useNuiEvent<MenuItem[] | null>("showMenuHeader", setItems)
    useNuiEvent("hideMenuHeader", () => setItems(null))

    if (!items?.length) return null

    return (
        <aside className="pointer-events-none absolute left-6 top-6 grid w-80 gap-1 rounded-[var(--radius)] border border-border bg-popover/95 p-2 shadow-[0_8px_24px_rgb(0_0_0_/_45%)]">
            {items.map((item) => (
                <div key={item.id} className="grid min-h-10 grid-cols-[auto_minmax(0,1fr)] items-start gap-2 rounded-md px-2 py-2 text-sm font-medium">
                    <MenuItemLabel item={item} />
                </div>
            ))}
        </aside>
    )
}
