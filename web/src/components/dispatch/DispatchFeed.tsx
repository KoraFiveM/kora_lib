import { useEffect, useRef, useState, type CSSProperties } from "react"
import { Banknote, BellOff, Flame, HeartPulse, PersonStanding, Siren, Stethoscope, Users } from "lucide-react"

import { cn } from "@/lib/cn"
import { resolveIcon } from "@/lib/icon"
import { fetchNui } from "@/lib/fetchNui"
import type { DispatchFeedCall, DispatchFeedPayload } from "@/lib/types"
import { useNuiEvent } from "@/lib/useNuiEvent"

const positions: Record<string, string> = {
    "left-center": "left-4 top-1/2 -translate-y-1/2",
    "top-left": "left-4 top-4",
    "top-center": "left-1/2 top-4 -translate-x-1/2",
}
// Preserve the original call vocabulary/fallback, using the shared resolver
// for icons already in its curated set and six fixed Lucides for the rest.
const sharedIcons: Record<string, string> = {
    car: "Car",
    crosshair: "Crosshair",
    home: "Home",
    package: "Package",
    radio: "Radio",
    truck: "Truck",
    wrench: "Wrench",
}
const extraIcons = {
    banknote: Banknote,
    fire: Flame,
    "heart-pulse": HeartPulse,
    person: PersonStanding,
    siren: Siren,
    stethoscope: Stethoscope,
}
const responseText = {
    en_route: "You are en route",
    on_scene: "You are on scene",
    clear: "You have cleared",
}

function isLive(call: DispatchFeedCall, now: number) {
    return !call.closedAt && now < call.expiresAt
}

function elapsed(call: DispatchFeedCall, now: number) {
    const seconds = Math.max(0, Math.floor((now - call.createdAt) / 1000))
    return seconds < 60 ? `${seconds}s` : `${Math.floor(seconds / 60)}m ${String(seconds % 60).padStart(2, "0")}s`
}

function tint(hex: string) {
    const raw = hex.replace("#", "")
    const full = raw.length === 3 ? raw.split("").map((char) => char + char).join("") : raw
    const value = Number.parseInt(full, 16)
    return Number.isFinite(value) && full.length === 6
        ? `rgba(${(value >> 16) & 255}, ${(value >> 8) & 255}, ${value & 255}, 0.14)`
        : "rgba(148, 148, 148, 0.14)"
}

function KeyChip({ label }: { label: string }) {
    return (
        <kbd className="rounded-xs border border-border-strong bg-surface-raised px-1 py-px font-mono text-[10px] font-medium leading-[14px] tracking-wide text-muted-foreground">
            {label}
        </kbd>
    )
}

function CallCard({ call, payload, now }: { call: DispatchFeedCall; payload: DispatchFeedPayload; now: number }) {
    const priorities = payload.config?.priorities
    const priority = Array.isArray(priorities) ? priorities[call.priority - 1] : priorities?.[String(call.priority)]
    const iconName = call.icon ?? ""
    const Icon = Object.hasOwn(extraIcons, iconName)
        ? extraIcons[iconName as keyof typeof extraIcons]
        : resolveIcon(Object.hasOwn(sharedIcons, iconName) ? sharedIcons[iconName] : "AlertTriangle")!
    const units = Array.isArray(call.units) ? call.units : []
    const mine = payload.me ? units.find((unit) => unit.src === payload.me!.src) : undefined
    const selected = call.id === payload.selected

    return (
        <article
            aria-label={call.title}
            style={{ background: "hsl(var(--card))", borderColor: selected ? "hsl(var(--brand-border))" : undefined }}
            className={cn(
                "hud-chip relative w-full overflow-hidden text-left",
                !isLive(call, now) && "opacity-60",
            )}
        >
            <span
                aria-hidden
                className="absolute inset-y-0 left-0 w-1"
                style={{ background: priority?.color ?? "hsl(var(--muted-foreground))" }}
            />
            <div className="flex items-start gap-2 py-2 pl-3 pr-2.5">
                <span
                    className="mt-px flex h-6 w-6 shrink-0 items-center justify-center rounded-full"
                    style={{ background: tint(priority?.color ?? "#949494"), color: priority?.color ?? "hsl(var(--muted-foreground))" }}
                >
                    <Icon aria-hidden size={14} strokeWidth={2} />
                </span>
                <div className="min-w-0 flex-1">
                    <div className="flex items-baseline gap-1.5">
                        {call.code ? <span className="font-mono text-[11px] font-semibold leading-[18px]">{call.code}</span> : null}
                        <span className="truncate text-[13px] font-semibold leading-[18px]">{call.title}</span>
                    </div>
                    <div className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-0.5 text-[11px] leading-[15px] text-muted-foreground">
                        <span>{priority?.label ?? `P${call.priority}`}</span>
                        {selected ? <span className="font-medium text-foreground">Selected</span> : null}
                        <span aria-hidden>·</span>
                        <span className="font-mono tabular-nums">{elapsed(call, now)}</span>
                        {call.data?.street ? (
                            <>
                                <span aria-hidden>·</span>
                                <span className="truncate">{String(call.data.street)}</span>
                            </>
                        ) : null}
                        {units.length ? (
                            <span className="ml-auto inline-flex items-center gap-1">
                                <Users aria-hidden size={11} />
                                <span className="tabular-nums">{units.length}</span>
                            </span>
                        ) : null}
                    </div>
                </div>
            </div>
            {mine ? (
                <div className="border-t border-border bg-brand-soft px-3 py-1 text-[11px] font-medium leading-[15px]">
                    {responseText[mine.state]}
                </div>
            ) : null}
        </article>
    )
}

/** Display-only persistent dispatch surface; game keys remain owned by Lua. */
export function DispatchFeed() {
    const [payload, setPayload] = useState<DispatchFeedPayload | null>(null)
    const [now, setNow] = useState(0)
    const clock = useRef({ now: 0, at: 0 })

    useNuiEvent<DispatchFeedPayload | false>("qbdispatch:feed", (data) => {
        if (!data || typeof data.now !== "number") {
            setPayload(null)
            return
        }
        clock.current = { now: data.now, at: performance.now() }
        setNow(data.now)
        setPayload({ ...data, calls: Array.isArray(data.calls) ? data.calls : [] })
    })
    useEffect(() => {
        void fetchNui("kora_lib:dispatchfeed:ready").catch((error) => console.error("[kora_lib] dispatch feed ready failed:", error))
    }, [])

    const live = payload?.calls.filter((call) => isLive(call, now)).slice(0, payload.config?.feed?.maxVisible ?? 4) ?? []
    const selected = payload?.calls.find((call) => call.id === payload.selected)
    const showing = selected && !live.some((call) => call.id === selected.id) ? [selected, ...live] : live
    const ticking = !!payload && !payload.hidden && showing.length > 0

    useEffect(() => {
        if (!ticking) return
        const id = window.setInterval(() => setNow(clock.current.now + performance.now() - clock.current.at), 500)
        return () => window.clearInterval(id)
    }, [ticking])

    if (!payload) return null
    const configuredPosition = payload.config?.feed?.position ?? "left-center"
    const position = positions[Object.hasOwn(positions, configuredPosition) ? configuredPosition : "left-center"]
    // Scope only the approved service brand tokens; the shared frame's palette,
    // other prompts and AppShell must retain their own theme.
    const style = Object.fromEntries(
        ["primary", "brand-soft", "brand-border"].flatMap((key) => payload.theme?.[key] ? [[`--${key}`, payload.theme[key]]] : []),
    ) as CSSProperties

    if (payload.hidden) {
        return (
            <aside aria-label="Dispatch muted" className={`pointer-events-none fixed z-hud ${position}`} style={style}>
                <div className="hud-chip flex items-center gap-2 px-2.5 py-1.5">
                    <BellOff aria-hidden size={13} className="text-muted-foreground" />
                    <span className="overlay-text text-[11px] leading-[15px] text-muted-foreground">Dispatch muted</span>
                    <KeyChip label={payload.keybinds.toggle} />
                </div>
            </aside>
        )
    }
    if (!showing.length) return null
    const mine = selected && Array.isArray(selected.units) ? selected.units.find((unit) => unit.src === payload.me?.src) : undefined
    const respondLabel = mine?.state === "en_route" ? "On scene" : mine?.state === "on_scene" ? "Clear" : "Accept"

    return (
        <section aria-live="polite" aria-label="Dispatch calls" className={`pointer-events-none fixed z-hud w-[300px] ${position}`} style={style}>
            <div className="flex flex-col gap-1.5">
                {showing.map((call) => <CallCard key={call.id} call={call} payload={payload} now={now} />)}
            </div>
            {selected ? (
                <div className="hud-chip mt-1.5 flex items-center gap-2.5 px-2.5 py-1.5">
                    <span className="inline-flex items-center gap-1">
                        <KeyChip label={payload.keybinds.previous} />
                        <KeyChip label={payload.keybinds.next} />
                        <span className="overlay-text text-[10px] leading-[14px] text-muted-foreground">Browse</span>
                    </span>
                    <span className="inline-flex items-center gap-1">
                        <KeyChip label={payload.keybinds.respond} />
                        <span className="overlay-text text-[10px] leading-[14px]">{respondLabel}</span>
                    </span>
                    <span className="ml-auto inline-flex items-center gap-1">
                        <KeyChip label={payload.keybinds.tablet} />
                        <span className="overlay-text text-[10px] leading-[14px] text-muted-foreground">Map</span>
                    </span>
                </div>
            ) : null}
        </section>
    )
}
