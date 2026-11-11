import { useState } from "react"

import { Kbd } from "@/components/ui/kbd"
import { EditorControlsHud } from "@/components/editor/EditorControlsHud"
import type { ZoneCreatorHudSnapshot, ZoneCreatorStartPayload, ZoneType } from "@/lib/types"
import { cn } from "@/lib/cn"
import { useNuiEvent } from "@/lib/useNuiEvent"

interface CreatorState {
    type: ZoneType
    snapshot: ZoneCreatorHudSnapshot | null
}

function formatParamValue(param: string, value: number): string {
    if (param === "rotation") return `${value.toFixed(1)}°`
    if (param === "zOffset") return `${value >= 0 ? "+" : ""}${value.toFixed(2)}m`
    return value.toFixed(2)
}

function formatStepValue(param: string, value: number): string {
    if (param === "rotation") return `${value.toFixed(1)}°`
    if (param === "zOffset") return `${value.toFixed(2)}m`
    return value.toFixed(2)
}

const PARAM_LABELS: Record<string, string> = {
    zOffset: "height offset",
}

/**
 * Small always-mounted HUD for Kora.zones.startCreator (see
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
        if (snapshot == null) {
            setState(null)
            return
        }
        setState((prev) => (prev ? { ...prev, snapshot } : { type: snapshot.type, snapshot }))
    })

    if (!state) return null

    const { type, snapshot } = state

    return (
        <EditorControlsHud
            title={<span className="capitalize">Building: {type}</span>}
            status={
                <span className="flex items-center gap-2">
                    <AimIndicator aiming={snapshot?.aiming ?? false} />
                    {snapshot ? <ShapeStatus type={type} snapshot={snapshot} /> : "Starting…"}
                </span>
            }
        >
            {snapshot && (
                <div className="mt-3 flex flex-wrap items-center gap-1.5">
                    <ActiveParam snapshot={snapshot} />
                    {snapshot.isShiftHeld && (
                        <span className="rounded-sm border border-warning/40 bg-warning/10 px-2 py-1 text-xs font-semibold text-warning">
                            Shift: fast adjust
                        </span>
                    )}
                    {snapshot.canConfirm && (
                        <span className="rounded-sm border border-brand-border bg-brand-soft px-2 py-1 text-xs font-semibold text-foreground">
                            Enter confirm
                        </span>
                    )}
                </div>
            )}
        </EditorControlsHud>
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
                <span className="inline-flex items-center gap-1 text-warning">
                    Aim and press <Kbd>E</Kbd> to place
                </span>
            )}
        </span>
    )
}

function ActiveParam({ snapshot }: { snapshot: ZoneCreatorHudSnapshot }) {
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

    const value = snapshot[snapshot.activeParam]
    if (typeof value !== "number") return null

    return (
        <span className="rounded-sm border border-brand-border border-l-[3px] border-l-primary bg-brand-soft px-2 py-1 text-xs">
            <span className="capitalize">{PARAM_LABELS[snapshot.activeParam] ?? snapshot.activeParam}</span>:{" "}
            <span className="font-mono tabular-nums">{formatParamValue(snapshot.activeParam, value)}</span>
            <span className="ml-1 text-muted-foreground">
                (±{formatStepValue(snapshot.activeParam, snapshot.stepSize)}/scroll)
            </span>
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
