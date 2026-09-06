import { useState } from "react"

import { EditorControlsHud, EditorKey } from "@/components/editor/EditorControlsHud"
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
        <EditorControlsHud
            width="md"
            title={<span className="block truncate" title={session.model}>Placing: {session.model}</span>}
            status={snapshot?.isShiftHeld ? (
                    <span className="shrink-0 rounded-sm border border-warning/40 bg-warning/10 px-2 py-1 text-xs font-semibold text-warning">
                        Fast
                    </span>
            ) : undefined}
            controls={
                <>
                    <p><EditorKey>WASD + mouse</EditorKey> fly camera</p>
                    <p>
                        <EditorKey>
                            {keyLabel(bindings.forward)} {keyLabel(bindings.backward)} {keyLabel(bindings.left)} {keyLabel(bindings.right)}
                        </EditorKey>{" "}move &middot; <EditorKey>{keyLabel(bindings.up)}/{keyLabel(bindings.down)}</EditorKey> height
                    </p>
                    <p>
                        <EditorKey>{keyLabel(bindings.rotateLeft)} {keyLabel(bindings.rotateRight)}</EditorKey> rotate &middot;{" "}
                        <EditorKey>{keyLabel(bindings.cycle)}</EditorKey> axis &middot; <EditorKey>Shift</EditorKey> fast
                    </p>
                    <p>
                        <EditorKey>{keyLabel(bindings.confirm)}</EditorKey> finish &middot;{" "}
                        <EditorKey>{keyLabel(bindings.cancel)}</EditorKey> cancel
                    </p>
                </>
            }
        >

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
        </EditorControlsHud>
    )
}
