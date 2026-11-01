import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from "react"
import { Crosshair, MapPin, Minus, Plus } from "lucide-react"

import { cn } from "@/lib/cn"
import { resolveIcon } from "@/lib/icon"
import type { AppBlock, AppMapMarker, AppShellLabels, AppTone } from "@/lib/types"

type MapBlock = Extract<AppBlock, { type: "map" }>
const toneClasses: Record<AppTone, string> = {
    neutral: "border-border bg-card text-foreground",
    primary: "border-primary bg-primary text-primary-foreground",
    success: "border-success bg-success text-background",
    warning: "border-warning bg-warning text-background",
    destructive: "border-destructive bg-destructive text-destructive-foreground",
}

export default function AppMapBlock({ block, labels, disabled, onSelect }: { block: MapBlock; labels: AppShellLabels; disabled?: boolean; onSelect: (marker: AppMapMarker) => void }) {
    const minZoom = block.minZoom ?? 0
    const maxZoom = block.maxZoom ?? 3
    const tileSize = block.tiles.tileSize ?? 256
    const grid = block.tiles.grid ?? { x: 2 ** maxZoom, y: 2 ** maxZoom }
    const size = { width: grid.x * tileSize, height: grid.y * tileSize }
    const project = useMemo(() => projection(block), [block.tiles.calibration])
    const container = useRef<HTMLDivElement>(null)
    const drag = useRef<{ x: number; y: number; cx: number; cy: number }>()
    const [viewport, setViewport] = useState({ width: 0, height: 0 })
    const [scale, setScale] = useState(block.initialZoom ?? 0.5)
    const [centre, setCentre] = useState(() => block.recenter ? project(block.recenter) : { x: size.width / 2, y: size.height / 2 })
    const [following, setFollowing] = useState(block.follow ?? true)

    useLayoutEffect(() => {
        const element = container.current
        if (!element) return
        const update = () => setViewport({ width: element.clientWidth, height: element.clientHeight })
        update()
        const observer = typeof ResizeObserver === "undefined" ? undefined : new ResizeObserver(update)
        observer?.observe(element)
        return () => observer?.disconnect()
    }, [])

    const selected = block.markers.find((marker) => marker.id === block.selectedId)
    const focus = selected ? project(selected) : block.recenter ? project(block.recenter) : undefined
    useEffect(() => { if (following && focus) setCentre(focus) }, [following, focus?.x, focus?.y])

    useEffect(() => {
        const move = (event: PointerEvent) => {
            const start = drag.current
            if (!start || Math.hypot(event.clientX - start.x, event.clientY - start.y) < 3) return
            setFollowing(false)
            setCentre({ x: start.cx - (event.clientX - start.x) / scale, y: start.cy - (event.clientY - start.y) / scale })
        }
        const up = () => { drag.current = undefined }
        window.addEventListener("pointermove", move)
        window.addEventListener("pointerup", up)
        window.addEventListener("pointercancel", up)
        return () => { window.removeEventListener("pointermove", move); window.removeEventListener("pointerup", up); window.removeEventListener("pointercancel", up) }
    }, [scale])

    const zoomBy = useCallback((factor: number) => setScale((current) => Math.min(4, Math.max(0.12, current * factor))), [])
    const captureWheel = block.captureWheel ?? true

    // React registers wheel listeners as passive, so preventDefault() there is ignored; attach a native non-passive one.
    useEffect(() => {
        const element = container.current
        if (!element || !captureWheel) return
        const wheel = (event: WheelEvent) => {
            event.preventDefault()
            event.stopPropagation()
            zoomBy(event.deltaY < 0 ? 1.15 : 1 / 1.15)
        }
        element.addEventListener("wheel", wheel, { passive: false })
        return () => element.removeEventListener("wheel", wheel)
    }, [captureWheel, zoomBy])
    const toScreen = useCallback((point: { x: number; y: number }) => ({ x: (point.x - centre.x) * scale + viewport.width / 2, y: (point.y - centre.y) * scale + viewport.height / 2 }), [centre, scale, viewport])
    const visibleMarkers = block.markers.filter((marker) => !marker.expiresAt || block.now === undefined || marker.expiresAt > block.now - (marker.fadeDuration ?? block.fadeDuration ?? 0))

    return <section className="overflow-hidden rounded-lg border border-border bg-card">
        {block.title ? <h3 className="border-b border-border px-4 py-3 text-sm font-semibold">{block.title}</h3> : null}
        <div ref={container} role="application" aria-label={block.title ?? labels.map} className="relative h-[clamp(20rem,52vh,42rem)] w-full cursor-grab select-none overflow-hidden overscroll-contain bg-background active:cursor-grabbing" onPointerDown={(event) => { drag.current = { x: event.clientX, y: event.clientY, cx: centre.x, cy: centre.y } }}>
            <TileLayer block={block} centre={centre} scale={scale} viewport={viewport} minZoom={minZoom} maxZoom={maxZoom} tileSize={tileSize} grid={grid} />
            {visibleMarkers.map((marker) => {
                const at = toScreen(project(marker))
                const Icon = resolveIcon(marker.icon) ?? MapPin
                const fadeDuration = marker.fadeDuration ?? block.fadeDuration
                const fade = marker.expiresAt && block.now !== undefined && fadeDuration ? Math.max(0, Math.min(1, (marker.expiresAt - block.now) / fadeDuration)) : 1
                return <button key={marker.id} type="button" disabled={disabled || (!marker.action && !block.action)} onClick={() => onSelect(marker)} title={marker.description ? `${marker.label} · ${marker.description}` : marker.label} className="focus-ring pointer-events-auto absolute -translate-x-1/2 -translate-y-1/2 rounded-full disabled:pointer-events-none" style={{ left: at.x, top: at.y, opacity: fade }}>
                    <span className={cn("flex h-7 w-7 items-center justify-center rounded-full border-2 shadow-low", toneClasses[marker.tone ?? "primary"], marker.id === block.selectedId && "ring-4 ring-ring/40")} style={{ transform: marker.heading === undefined ? undefined : `rotate(${marker.heading}deg)` }}><Icon aria-hidden className="h-3.5 w-3.5" /></span>
                    <span className="overlay-text absolute left-1/2 top-full mt-1 -translate-x-1/2 whitespace-nowrap text-[10px] font-medium text-foreground">{marker.label}</span>
                </button>
            })}
            {visibleMarkers.length === 0 ? <p className="absolute inset-0 flex items-center justify-center text-sm text-muted-foreground">{block.empty ?? labels.nothingHere}</p> : null}
            <div className="pointer-events-auto absolute bottom-3 right-3 flex flex-col gap-1">
                <MapButton label={labels.zoomIn} onClick={() => zoomBy(1.4)}><Plus aria-hidden className="h-4 w-4" /></MapButton>
                <MapButton label={labels.zoomOut} onClick={() => zoomBy(1 / 1.4)}><Minus aria-hidden className="h-4 w-4" /></MapButton>
                <MapButton label={labels.recenter} active={following} onClick={() => { if (focus) setCentre(focus); setFollowing(true) }}><Crosshair aria-hidden className="h-4 w-4" /></MapButton>
            </div>
        </div>
    </section>
}

function projection(block: MapBlock) {
    const calibration = block.tiles.calibration
    if (!calibration) return (point: { x: number; y: number }) => point
    const worldWidth = calibration.b.world.x - calibration.a.world.x
    const worldHeight = calibration.b.world.y - calibration.a.world.y
    const scaleX = worldWidth === 0 ? 1 : (calibration.b.image.x - calibration.a.image.x) / worldWidth
    const scaleY = worldHeight === 0 ? -1 : (calibration.b.image.y - calibration.a.image.y) / worldHeight
    return (point: { x: number; y: number }) => ({
        x: calibration.a.image.x + (point.x - calibration.a.world.x) * scaleX,
        y: calibration.a.image.y + (point.y - calibration.a.world.y) * scaleY,
    })
}

function MapButton({ label, active, onClick, children }: { label: string; active?: boolean; onClick: () => void; children: React.ReactNode }) {
    return <button type="button" aria-label={label} title={label} onClick={onClick} className={cn("focus-ring flex h-9 w-9 items-center justify-center rounded-md border", active ? "border-brand-border bg-brand-soft text-foreground" : "border-border bg-card text-muted-foreground hover:bg-surface-hover hover:text-foreground")}>{children}</button>
}

function TileLayer({ block, centre, scale, viewport, minZoom, maxZoom, tileSize, grid }: { block: MapBlock; centre: { x: number; y: number }; scale: number; viewport: { width: number; height: number }; minZoom: number; maxZoom: number; tileSize: number; grid: { x: number; y: number } }) {
    if (!viewport.width || !viewport.height) return null
    const zoom = Math.max(minZoom, Math.min(maxZoom, Math.round(maxZoom + Math.log2(scale))))
    return <div aria-hidden>{zoom > minZoom ? <TileGrid block={block} zoom={zoom - 1} centre={centre} scale={scale} viewport={viewport} maxZoom={maxZoom} tileSize={tileSize} grid={grid} /> : null}<TileGrid block={block} zoom={zoom} centre={centre} scale={scale} viewport={viewport} maxZoom={maxZoom} tileSize={tileSize} grid={grid} /></div>
}

function TileGrid({ block, zoom, centre, scale, viewport, maxZoom, tileSize, grid }: { block: MapBlock; zoom: number; centre: { x: number; y: number }; scale: number; viewport: { width: number; height: number }; maxZoom: number; tileSize: number; grid: { x: number; y: number } }) {
    const levels = 2 ** (maxZoom - zoom)
    const tilesX = Math.ceil(grid.x / levels)
    const tilesY = Math.ceil(grid.y / levels)
    const tileSpan = tileSize * levels
    const screenSpan = tileSpan * scale
    const left = centre.x - viewport.width / 2 / scale
    const top = centre.y - viewport.height / 2 / scale
    const firstX = Math.max(0, Math.floor(left / tileSpan) - 1)
    const lastX = Math.min(tilesX - 1, Math.floor((left + viewport.width / scale) / tileSpan) + 1)
    const firstY = Math.max(0, Math.floor(top / tileSpan) - 1)
    const lastY = Math.min(tilesY - 1, Math.floor((top + viewport.height / scale) / tileSpan) + 1)
    const tiles = []
    for (let x = firstX; x <= lastX; x++) for (let y = firstY; y <= lastY; y++) {
        const url = block.tiles.url.replace("{z}", String(zoom)).replace("{x}", String(x)).replace("{y}", String(y))
        tiles.push(<img key={`${zoom}/${x}/${y}`} src={url} alt="" draggable={false} onError={(event) => { event.currentTarget.style.visibility = "hidden" }} className="pointer-events-none absolute max-h-none max-w-none origin-top-left select-none" style={{ left: Math.round((x * tileSpan - left) * scale), top: Math.round((y * tileSpan - top) * scale), width: Math.ceil(screenSpan) + 1, height: Math.ceil(screenSpan) + 1 }} />)
    }
    return <>{tiles}</>
}
