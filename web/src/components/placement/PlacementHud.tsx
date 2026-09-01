import { useState } from "react"

import type { PlacementHudSnapshot, PlacementStartPayload } from "@/lib/types"
import { useNuiEvent } from "@/lib/useNuiEvent"

interface PlacementHudState {
    session: PlacementStartPayload
    snapshot: PlacementHudSnapshot | null
}

const KEY_LABELS: Record<string, string> = {
    UP: "↑",
    DOWN: "↓",
    LEFT: "←",
    RIGHT: "→",
    PAGEUP: "PgUp",
    PAGEDOWN: "PgDn",
    LBRACKET: "[",
    RBRACKET: "]",
    RETURN: "Enter",
    TAB: "Tab",
}

function keyLabel(value: string): string {
    return KEY_LABELS[value.toUpperCase()] ?? value
}

function NumberValue({ value, suffix = "" }: { value: number; suffix?: string }) {
    return <span className="font-mono tabular-nums text-foreground">{value.toFixed(3)}{suffix}</span>
}

/** Pointer-transparent live state for QB.placement's free-camera editor. */
export function PlacementHud() {
    const [state, setState] = useState<PlacementHudState | null>(null)

    useNuiEvent<PlacementStartPayload>("placement:start", (session) => {
        setState({ session, snapshot: null })
    })

    useNuiEvent<PlacementHudSnapshot | null | undefined>("placement:hud", (snapshot) => {
        if (snapshot == null) {
            setState(null)
            return
        }

        setState((previous) => previous ? { ...previous, snapshot } : previous)
    })

    if (!state) return null

    const { session, snapshot } = state
    const bindings = session.bindings

    return (
        <div className="pointer-events-none fixed bottom-4 left-4 z-hud w-80 max-w-[calc(100vw-2rem)] select-none rounded-xl border bg-hud p-3 text-card-foreground shadow-low">
            <div className="title-rail flex min-w-0 items-center justify-between gap-3">
                <span className="truncate text-sm font-semibold" title={session.model}>Placing: {session.model}</span>
                {snapshot?.isShiftHeld && (
                    <span className="shrink-0 rounded-sm border border-warning/40 bg-warning/10 px-2 py-1 text-xs font-semibold text-warning">
                        Fast
                    </span>
                )}
            </div>

            {snapshot ? (
                <>
                    <div className="mt-3 grid grid-cols-3 gap-x-3 gap-y-1 text-xs text-muted-foreground">
                        <span>X <NumberValue value={snapshot.coords.x} /></span>
                        <span>Y <NumberValue value={snapshot.coords.y} /></span>
                        <span>Z <NumberValue value={snapshot.coords.z} /></span>
                    </div>

                    <div className="mt-2 grid grid-cols-3 gap-1.5">
                        {(["yaw", "pitch", "roll"] as const).map((axis) => (
                            <span
                                key={axis}
                                className={snapshot.activeAxis === axis
                                    ? "rounded-sm border border-brand-border border-l-[3px] border-l-primary bg-brand-soft px-2 py-1 text-xs"
                                    : "rounded-sm border bg-surface-raised px-2 py-1 text-xs text-muted-foreground"}
                            >
                                <span className="capitalize">{axis}</span>{" "}
                                <NumberValue value={snapshot.rotation[axis]} suffix="°" />
                            </span>
                        ))}
                    </div>
                </>
            ) : (
                <p className="mt-3 text-xs text-muted-foreground">Starting preview…</p>
            )}

            <div className="mt-3 space-y-1 border-t pt-2 text-xs leading-5 text-card-foreground/80">
                <p><b className="font-medium text-foreground">WASD + mouse</b> fly camera</p>
                <p>
                    <b className="font-medium text-foreground">
                        {keyLabel(bindings.forward)} {keyLabel(bindings.backward)} {keyLabel(bindings.left)} {keyLabel(bindings.right)}
                    </b>{" "}move · <b className="font-medium text-foreground">{keyLabel(bindings.up)}/{keyLabel(bindings.down)}</b> height
                </p>
                <p>
                    <b className="font-medium text-foreground">{keyLabel(bindings.rotateLeft)} {keyLabel(bindings.rotateRight)}</b> rotate ·{" "}
                    <b className="font-medium text-foreground">{keyLabel(bindings.cycle)}</b> axis · <b className="font-medium text-foreground">Shift</b> fast
                </p>
                <p>
                    <b className="font-medium text-foreground">{keyLabel(bindings.confirm)}</b> finish ·{" "}
                    <b className="font-medium text-foreground">{keyLabel(bindings.cancel)}</b> cancel
                </p>
            </div>
        </div>
    )
}
