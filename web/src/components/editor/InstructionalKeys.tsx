import { useEffect, useSyncExternalStore } from "react"

import { Kbd, KbdGroup } from "@/components/ui/kbd"
import type { InstructionalPayload, InstructionalRow } from "@/lib/types"
import { useNuiEvent } from "@/lib/useNuiEvent"

let rows: InstructionalRow[] = []
let hosts = 0
const listeners = new Set<() => void>()
const emit = () => listeners.forEach((l) => l())
const subscribe = (l: () => void) => {
    listeners.add(l)
    return () => void listeners.delete(l)
}

/** Mounted by <InstructionalKeysSource /> once, in App. */
export function InstructionalKeysSource() {
    useNuiEvent<InstructionalPayload | undefined>("instructional:set", (data) => {
        rows = Array.isArray(data?.buttons) ? data.buttons : []
        emit()
    })
    return null
}

export function useInstructionalRows() {
    return useSyncExternalStore(subscribe, () => rows)
}

/** Editor HUDs mount this so the standalone pill knows to stay hidden. */
export function useClaimInstructionalHost() {
    useEffect(() => {
        hosts += 1
        emit()
        return () => {
            hosts -= 1
            emit()
        }
    }, [])
}

export function KeyHints() {
    const list = useInstructionalRows()
    if (list.length === 0) return null
    return (
        <ul className="grid grid-cols-[1fr_max-content] items-center gap-x-4 gap-y-1.5">
            {list.map((row) => (
                <li key={row.label} className="contents text-xs text-card-foreground/80">
                    <span className="min-w-0 text-xs leading-4">{row.label}</span>
                    <KbdGroup className="justify-self-end">
                        {row.keys.map((k) => (
                            <Kbd key={k}>{k}</Kbd>
                        ))}
                    </KbdGroup>
                </li>
            ))}
        </ul>
    )
}

/** Fallback for resources (camera, cards, multichar) that have no editor box to host the keys. */
export function StandaloneKeyHints() {
    const list = useInstructionalRows()
    const hasHost = useSyncExternalStore(subscribe, () => hosts > 0)
    if (hasHost || list.length === 0) return null
    return (
        <section
            aria-label="Controls"
            className="pointer-events-none fixed bottom-4 left-4 z-hud w-72 max-w-[calc(100vw-2rem)] select-none rounded-xl border bg-hud p-3 shadow-low"
        >
            <KeyHints />
        </section>
    )
}
