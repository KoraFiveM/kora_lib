import { useEffect } from "react"

import { fetchNui } from "@/lib/fetchNui"
import type { NuiThemePayload } from "@/lib/types"
import { useNuiEvent } from "@/lib/useNuiEvent"

const HEX_COLOR = /^#[0-9a-f]{6}$/i
const DEFAULT_ACCENT = "#DC143C"
const DARK_SURFACE_LUMINANCE = relativeLuminance(16, 16, 16)

function relativeLuminance(red: number, green: number, blue: number) {
    const channel = (value: number) => {
        const normalized = value / 255
        return normalized <= 0.04045 ? normalized / 12.92 : ((normalized + 0.055) / 1.055) ** 2.4
    }

    return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
}

function hslFromHex(hex: string) {
    const red = Number.parseInt(hex.slice(1, 3), 16) / 255
    const green = Number.parseInt(hex.slice(3, 5), 16) / 255
    const blue = Number.parseInt(hex.slice(5, 7), 16) / 255
    const max = Math.max(red, green, blue)
    const min = Math.min(red, green, blue)
    const delta = max - min
    const lightness = (max + min) / 2

    let hue = 0
    if (delta !== 0) {
        if (max === red) hue = ((green - blue) / delta) % 6
        else if (max === green) hue = (blue - red) / delta + 2
        else hue = (red - green) / delta + 4
        hue *= 60
        if (hue < 0) hue += 360
    }

    const saturation = delta === 0 ? 0 : delta / (1 - Math.abs(2 * lightness - 1))
    const round = (value: number) => Math.round(value * 10) / 10

    return { hue: round(hue), saturation: round(saturation * 100), lightness: round(lightness * 100) }
}

function hslToken(hue: number, saturation: number, lightness: number, alpha?: number) {
    return `${hue} ${saturation}% ${lightness}%${alpha === undefined ? "" : ` / ${alpha}`}`
}

function applyAccentColor(accentColor: string | undefined) {
    const hex = accentColor && HEX_COLOR.test(accentColor) ? accentColor : DEFAULT_ACCENT
    const red = Number.parseInt(hex.slice(1, 3), 16)
    const green = Number.parseInt(hex.slice(3, 5), 16)
    const blue = Number.parseInt(hex.slice(5, 7), 16)
    const { hue, saturation, lightness } = hslFromHex(hex)
    const primary = hslToken(hue, saturation, lightness)
    const root = document.documentElement.style
    const luminance = relativeLuminance(red, green, blue)
    const whiteContrast = 1.05 / (luminance + 0.05)
    const darkContrast = (luminance + 0.05) / (DARK_SURFACE_LUMINANCE + 0.05)

    root.setProperty("--primary", primary)
    root.setProperty("--ring", primary)
    root.setProperty("--brand-hover", hslToken(hue, saturation, Math.max(0, lightness - 5.1)))
    root.setProperty("--brand-pressed", hslToken(hue, saturation, Math.max(0, lightness - 10.6)))
    root.setProperty("--brand-soft", hslToken(hue, saturation, lightness, 0.14))
    root.setProperty("--brand-border", hslToken(hue, saturation, lightness, 0.45))
    root.setProperty("--primary-foreground", whiteContrast >= darkContrast ? "0 0% 100%" : "0 0% 6.3%")
}

/** Keeps every semantic brand token in sync with Config.ui.accentColor. */
export function ThemeSynchronizer() {
    useNuiEvent<NuiThemePayload>("qblib:theme", (payload) => applyAccentColor(payload?.accentColor))

    useEffect(() => {
        void fetchNui<NuiThemePayload>("qblib:nui:theme")
            .then((payload) => applyAccentColor(payload?.accentColor))
            .catch((error) => console.error("[qblib] could not load NUI theme:", error))
    }, [])

    return null
}
