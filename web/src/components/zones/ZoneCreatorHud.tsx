import { useState } from "react"

import { EditorControlsHud } from "@/components/editor/EditorControlsHud"
import type { ZoneCreatorHudSnapshot, ZoneCreatorStartPayload, ZoneType } from "@/lib/types"
import { cn } from "@/lib/cn"
import { useNuiEvent } from "@/lib/useNuiEvent"
import { defaultZoneCreatorLabels, formatZoneCreatorLabel } from "@/lib/zoneCreatorLocale"

interface CreatorState {
    type: ZoneType
    snapshot: ZoneCreatorHudSnapshot | null
    labels: typeof defaultZoneCreatorLabels
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

/**
 * Small always-mounted HUD for Kora.zones.startCreator (see
 * modules/zones/client.lua). Deliberately stays pointer-events-none the whole
 * time it's visible -- unlike every other top-level NUI component, this one
 * must never intercept the mouse look/aiming the creator is built around.
 */
export function ZoneCreatorHud() {
    const [state, setState] = useState<CreatorState | null>(null)

    useNuiEvent<ZoneCreatorStartPayload>("zoneCreator:start", (data) => {
        setState({ type: data.type, snapshot: null, labels: data.labels ?? defaultZoneCreatorLabels })
    })

    useNuiEvent<ZoneCreatorHudSnapshot | null | undefined>("zoneCreator:hud", (snapshot) => {
        if (snapshot == null) {
            setState(null)
            return
        }
        setState((prev) => (prev ? { ...prev, snapshot } : { type: snapshot.type, snapshot, labels: defaultZoneCreatorLabels }))
    })

    if (!state) return null

    const { type, snapshot, labels } = state

    return (
        <EditorControlsHud
            title={<span className="capitalize">{formatZoneCreatorLabel(labels.building, labels.types[type])}</span>}
            status={
                <span className="flex items-center gap-2">
                    <AimIndicator aiming={snapshot?.aiming ?? false} />
                    {snapshot ? <ShapeStatus type={type} snapshot={snapshot} labels={labels} /> : labels.starting}
                </span>
            }
        >
            {snapshot && (
                <div className="mt-3 flex flex-wrap items-center gap-1.5">
                    <ActiveParam snapshot={snapshot} labels={labels} />
                    {snapshot.isShiftHeld && (
                        <span className="rounded-sm border border-warning/40 bg-warning/10 px-2 py-1 text-xs font-semibold text-warning">
                            {labels.shiftFast}
                        </span>
                    )}
                    {snapshot.canConfirm && (
                        <span className="rounded-sm border border-brand-border bg-brand-soft px-2 py-1 text-xs font-semibold text-foreground">
                            {labels.enterConfirm}
                        </span>
                    )}
                </div>
            )}
        </EditorControlsHud>
    )
}

function ShapeStatus({ type, snapshot, labels }: { type: ZoneType; snapshot: ZoneCreatorHudSnapshot; labels: typeof defaultZoneCreatorLabels }) {
    if (type === "poly") {
        return (
            <span>
                {formatZoneCreatorLabel(snapshot.pointCount === 1 ? labels.pointOne : labels.pointMany, snapshot.pointCount)}
            </span>
        )
    }

    return (
        <span>
            {snapshot.hasCenter ? (
                <span className="text-success">{labels.centerPlaced}</span>
            ) : (
                <span className="inline-flex items-center gap-1 text-warning">
                    {formatZoneCreatorLabel(labels.aimPlace, "E")}
                </span>
            )}
        </span>
    )
}

function ActiveParam({ snapshot, labels }: { snapshot: ZoneCreatorHudSnapshot; labels: typeof defaultZoneCreatorLabels }) {
    if (snapshot.activeParam === "editPoint") {
        return (
            <span className="rounded-sm border border-brand-border border-l-[3px] border-l-primary bg-brand-soft px-2 py-1 text-xs">
                {snapshot.editIndex > 0 ? (
                    <>
                        {formatZoneCreatorLabel(labels.editingPoint, snapshot.editIndex, snapshot.pointCount, "E")}
                    </>
                ) : snapshot.pointCount === 0 ? (
                    labels.editingPointsEmpty
                ) : (
                    labels.editingPointsAim
                )}
            </span>
        )
    }

    const value = snapshot[snapshot.activeParam]
    if (typeof value !== "number") return null

    return (
        <span className="rounded-sm border border-brand-border border-l-[3px] border-l-primary bg-brand-soft px-2 py-1 text-xs">
            <span className="capitalize">{labels.params[snapshot.activeParam] ?? snapshot.activeParam}</span>:{" "}
            <span className="font-mono tabular-nums">{formatParamValue(snapshot.activeParam, value)}</span>
            <span className="ml-1 text-muted-foreground">
                {formatZoneCreatorLabel(labels.stepScroll, formatStepValue(snapshot.activeParam, snapshot.stepSize))}
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
