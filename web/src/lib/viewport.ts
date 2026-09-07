// NUI is designed at 1080p, then enlarged as the available physical viewport
// grows. Keeping these calculations in one place means components that receive
// screen-pixel coordinates can convert them into the scaled root's coordinate
// space before positioning themselves.
const DESIGN_WIDTH = 1920
const DESIGN_HEIGHT = 1080
const MIN_SCALE = 0.5
const MAX_SCALE = 2

export function getNuiScale(): number {
    return Math.min(
        MAX_SCALE,
        Math.max(MIN_SCALE, Math.min(window.innerWidth / DESIGN_WIDTH, window.innerHeight / DESIGN_HEIGHT)),
    )
}

export function getNuiViewport() {
    const scale = getNuiScale()

    return {
        scale,
        width: window.innerWidth / scale,
        height: window.innerHeight / scale,
    }
}
