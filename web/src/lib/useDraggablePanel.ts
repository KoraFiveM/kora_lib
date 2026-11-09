import { useCallback, useLayoutEffect, useRef, useState, type MouseEvent as ReactMouseEvent, type PointerEvent as ReactPointerEvent, type RefObject } from "react"

export interface PanelOffset { x: number; y: number }

const ZERO: PanelOffset = { x: 0, y: 0 }
const INTERACTIVE = "button, input, textarea, select, a, label, [role=button], [contenteditable=true]"

export function loadPanelOffset(key: string | undefined): PanelOffset {
    if (!key) return ZERO
    try {
        const parsed = JSON.parse(window.localStorage.getItem(key) ?? "null")
        if (parsed && Number.isFinite(parsed.x) && Number.isFinite(parsed.y)) return { x: parsed.x, y: parsed.y }
    } catch {  }
    return ZERO
}

function savePanelOffset(key: string | undefined, offset: PanelOffset) {
    if (!key) return
    try {
        if (offset.x === 0 && offset.y === 0) window.localStorage.removeItem(key)
        else window.localStorage.setItem(key, JSON.stringify(offset))
    } catch {  }
}

/**
 * Clamps `target` so the panel stays inside the viewport. `rect` is the panel's current box,
 * which already includes `current`; the default (offset 0) box is derived from it.
 */
export function clampPanelOffset(rect: { left: number; top: number; right: number; bottom: number }, current: PanelOffset, viewport: { width: number; height: number }, target: PanelOffset = current): PanelOffset {
    const clamp = (value: number, min: number, max: number) => Math.round(Math.min(Math.max(value, Math.min(min, 0)), Math.max(max, 0)))
    return {
        x: clamp(target.x, -(rect.left - current.x), viewport.width - (rect.right - current.x)),
        y: clamp(target.y, -(rect.top - current.y), viewport.height - (rect.bottom - current.y)),
    }
}

/**
 * The offset the browser is drawing right now, from the computed left/top. While left/top is
 * mid-transition this is the animated value rather than the state the last render set, so the
 * default box derived from it is right. Deriving it from the rendered state instead made the
 * clamp chase a box that had not moved yet and set a new offset on every pass (React error
 * #185) once the panel was dragged past the left edge.
 */
function appliedOffset(element: HTMLElement): PanelOffset {
    const style = window.getComputedStyle(element)
    const x = parseFloat(style.left)
    const y = parseFloat(style.top)
    return { x: Number.isFinite(x) ? x : 0, y: Number.isFinite(y) ? y : 0 }
}

/**
 * The NUI root is scaled with a CSS transform (main.tsx), so the panel's screen box, the window
 * size and pointer moves are in screen px while left/top are in the root's unscaled px. This is
 * the factor between them, read from the panel's full-screen host (1 when it cannot be measured).
 */
function rootScale(element: HTMLElement): number {
    const host = element.parentElement
    const width = host?.offsetWidth ?? 0
    const scale = host && width > 0 ? host.getBoundingClientRect().width / width : 1
    return Number.isFinite(scale) && scale > 0 ? scale : 1
}

/** The panel's layout box in unscaled px; the entry animation scales it about its centre, so undo that. */
function layoutBox(element: HTMLElement, scale: number) {
    const rect = element.getBoundingClientRect()
    const width = element.offsetWidth || rect.width / scale
    const height = element.offsetHeight || rect.height / scale
    const centreX = (rect.left + rect.right) / 2 / scale
    const centreY = (rect.top + rect.bottom) / 2 / scale
    return { left: centreX - width / 2, right: centreX + width / 2, top: centreY - height / 2, bottom: centreY + height / 2 }
}

/**
 * Makes a panel draggable by a header. The panel keeps its normal layout and is shifted with
 * relative left/top, so it never conflicts with entry animations (which own transform).
 * storageKey (when set) remembers the offset in localStorage.
 */
export function useDraggablePanel(panel: RefObject<HTMLElement | null>, options: { enabled: boolean; active: boolean; storageKey?: string }) {
    const { enabled, active, storageKey } = options
    const [offset, setOffset] = useState<PanelOffset>(ZERO)
    const [dragging, setDragging] = useState(false)
    const offsetRef = useRef(offset)
    const drag = useRef<{ pointerId: number; startX: number; startY: number; scale: number; origin: PanelOffset } | null>(null)
    offsetRef.current = offset

    const clampToViewport = useCallback((target: PanelOffset) => {
        const element = panel.current
        if (!element) return target
        const scale = rootScale(element)
        return clampPanelOffset(layoutBox(element, scale), appliedOffset(element), { width: window.innerWidth / scale, height: window.innerHeight / scale }, target)
    }, [panel])

    useLayoutEffect(() => {
        drag.current = null
        setDragging(false)
        setOffset(active && enabled ? loadPanelOffset(storageKey) : ZERO)
    }, [active, enabled, storageKey])

    useLayoutEffect(() => {
        const element = panel.current
        if (!active || !enabled || !element) return
        const reclamp = () => setOffset((current) => { const next = clampToViewport(current); return next.x === current.x && next.y === current.y ? current : next })
        reclamp()
        window.addEventListener("resize", reclamp)
        const observer = typeof ResizeObserver === "undefined" ? undefined : new ResizeObserver(reclamp)
        observer?.observe(element)
        return () => { window.removeEventListener("resize", reclamp); observer?.disconnect() }
    }, [active, enabled, clampToViewport, panel])

    const onPointerDown = useCallback((event: ReactPointerEvent<HTMLElement>) => {
        if (event.button !== 0 || (event.target as HTMLElement).closest(INTERACTIVE)) return
        drag.current = { pointerId: event.pointerId, startX: event.clientX, startY: event.clientY, scale: panel.current ? rootScale(panel.current) : 1, origin: offsetRef.current }
        event.currentTarget.setPointerCapture?.(event.pointerId)
        setDragging(true)
    }, [panel])
    const onPointerMove = useCallback((event: ReactPointerEvent<HTMLElement>) => {
        const state = drag.current
        if (!state || state.pointerId !== event.pointerId) return
        setOffset(clampToViewport({ x: state.origin.x + (event.clientX - state.startX) / state.scale, y: state.origin.y + (event.clientY - state.startY) / state.scale }))
    }, [clampToViewport])
    const endDrag = useCallback((event: ReactPointerEvent<HTMLElement>) => {
        const state = drag.current
        if (!state || state.pointerId !== event.pointerId) return
        drag.current = null
        setDragging(false)
        event.currentTarget.releasePointerCapture?.(event.pointerId)
        savePanelOffset(storageKey, offsetRef.current)
    }, [storageKey])
    const onDoubleClick = useCallback((event: ReactMouseEvent<HTMLElement>) => {
        if ((event.target as HTMLElement).closest(INTERACTIVE)) return
        drag.current = null
        setDragging(false)
        setOffset(ZERO)
        savePanelOffset(storageKey, ZERO)
    }, [storageKey])

    const handleProps = enabled ? { onPointerDown, onPointerMove, onPointerUp: endDrag, onPointerCancel: endDrag, onDoubleClick } : {}
    return { offset, dragging, handleProps }
}
