import { useState } from "react"

import type { ZoneCreatorHudSnapshot, ZoneCreatorStartPayload, ZoneType } from "@/lib/types"
import { cn } from "@/lib/cn"
import { useNuiEvent } from "@/lib/useNuiEvent"

interface CreatorState {
    type: ZoneType
    snapshot: ZoneCreatorHudSnapshot | null
}

function formatParamValue(param: string, value: number): string {
    if (param === "rotation") return `${value.toFixed(1)}°`
    // zOffset is the one signed parameter, and its sign is the whole point
    // (up vs down from where it was placed) -- an explicit + makes "raised"
    // legible at a glance instead of being inferred from the absence of a -.
    if (param === "zOffset") return `${value >= 0 ? "+" : ""}${value.toFixed(2)}m`
    return value.toFixed(2)
}

// "zOffset" reads as a field name, not a thing you're adjusting.
const PARAM_LABELS: Record<string, string> = {
    zOffset: "height offset",
}

/**
 * Small always-mounted HUD for QB.zones.startCreator (see
 * modules/zones/client.lua). Deliberately stays pointer-events-none the whole
 * time it's visible -- unlike every other top-level NUI component, this one
 * must never intercept the mouse look/aiming the creator is built around.
 */
export function ZoneCreatorHud() {
    const [state, setState] = useState<CreatorState | null>(null)

    useNuiEvent<ZoneCreatorStartPayload>("zoneCreator:start", (data) => {
        setState({ type: data.type, snapshot: null })
    })

    useNuiEvent<ZoneCreatorHudSnapshot | null | undefined>("zoneCreator:hud", (snapshot) => {
        // Nullish check, NOT === null: Lua's teardown send("zoneCreator:hud",
        // nil) serializes to an ABSENT data field (a nil-valued Lua table key
        // doesn't exist), so the teardown arrives here as undefined -- a
        // strict null comparison would leave the HUD mounted forever.
        if (snapshot == null) {
            setState(null)
            return
        }
        setState((prev) => (prev ? { ...prev, snapshot } : { type: snapshot.type, snapshot }))
    })

    if (!state) return null

    const { type, snapshot } = state

    return (
        <div className="pointer-events-none fixed bottom-4 left-4 z-hud w-72 max-w-[calc(100vw-2rem)] select-none rounded-xl border bg-hud p-3 text-card-foreground shadow-low">
            <div className="title-rail flex items-center justify-between gap-3">
                <span className="text-sm font-semibold capitalize">Building: {type}</span>
                <span className="flex items-center gap-2 text-xs text-muted-foreground">
                    <AimIndicator aiming={snapshot?.aiming ?? false} />
                    {snapshot ? <ShapeStatus type={type} snapshot={snapshot} /> : "Starting…"}
                </span>
            </div>

            {snapshot && (
                <div className="mt-3 flex flex-wrap items-center gap-1.5">
                    <ActiveParam snapshot={snapshot} />
                    {snapshot.canConfirm && (
                        <span className="rounded-sm border border-brand-border bg-brand-soft px-2 py-1 text-xs font-semibold text-foreground">
                            Enter confirm
                        </span>
                    )}
                </div>
            )}

            <p className="mt-3 border-t pt-2 text-xs leading-5 text-card-foreground/80">
                <span className="font-medium text-foreground">E</span> place/move &middot; <span className="font-medium text-foreground">Backspace</span> undo &middot; <span className="font-medium text-foreground">Tab</span> cycle &middot; <span className="font-medium text-foreground">Scroll</span> adjust &middot; <span className="font-medium text-foreground">X</span> cancel
            </p>
        </div>
    )
}

function ShapeStatus({ type, snapshot }: { type: ZoneType; snapshot: ZoneCreatorHudSnapshot }) {
    if (type === "poly") {
        return (
            <span>
                <span className="font-mono tabular-nums">{snapshot.pointCount}</span> point{snapshot.pointCount === 1 ? "" : "s"} placed
            </span>
        )
    }

    return (
        <span>
            {snapshot.hasCenter ? (
                <span className="text-success">Center placed</span>
            ) : (
                <span className="text-warning">Aim and press E to place</span>
            )}
        </span>
    )
}

function ActiveParam({ snapshot }: { snapshot: ZoneCreatorHudSnapshot }) {
    // editPoint is a mode rather than a value -- it has no matching number on
    // the snapshot, and what matters is which vertex is currently grabbed.
    if (snapshot.activeParam === "editPoint") {
        return (
            <span className="rounded-sm border border-brand-border border-l-[3px] border-l-primary bg-brand-soft px-2 py-1 text-xs">
                {snapshot.editIndex > 0 ? (
                    <>
                        Editing point <span className="font-mono">{snapshot.editIndex}</span> of{" "}
                        <span className="font-mono">{snapshot.pointCount}</span> &mdash; E moves it here
                    </>
                ) : snapshot.pointCount === 0 ? (
                    "Editing points — place some first"
                ) : (
                    "Editing points — aim near one to grab it"
                )}
            </span>
        )
    }

    // Every other member of the union IS a numeric snapshot field, so the
    // lookup needs no runtime mapping table.
    const value = snapshot[snapshot.activeParam]
    if (typeof value !== "number") return null

    return (
        <span className="rounded-sm border border-brand-border border-l-[3px] border-l-primary bg-brand-soft px-2 py-1 text-xs">
            <span className="capitalize">{PARAM_LABELS[snapshot.activeParam] ?? snapshot.activeParam}</span>:{" "}
            <span className="font-mono tabular-nums">{formatParamValue(snapshot.activeParam, value)}</span>
        </span>
    )
}

function AimIndicator({ aiming }: { aiming: boolean }) {
    return (
        <span
            className={cn(
                "h-2 w-2 shrink-0 rounded-full",
                aiming ? "bg-success" : "bg-muted-foreground/50"
            )}
            aria-hidden
        />
    )
}
