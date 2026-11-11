import { useState } from "react"

import type { CameraHudPayload } from "@/lib/types"
import { useNuiEvent } from "@/lib/useNuiEvent"

const EMPTY_STATE: CameraHudPayload = {
    active: false,
    mode: "operator",
    title: "SECURE CAMERA NETWORK",
    subtitle: "FIELD OPTICS",
    cameraLabel: "LIVE UNIT",
    cameraIndex: 0,
    totalCameras: 0,
    recording: false,
    timestamp: true,
    elapsed: 0,
}

function formatDuration(milliseconds: number): string {
    const seconds = Math.max(0, Math.floor(milliseconds / 1000))
    const hours = Math.floor(seconds / 3600)
    const minutes = Math.floor((seconds % 3600) / 60)
    const remainder = seconds % 60
    return hours > 0
        ? [hours, minutes, remainder].map((value) => String(value).padStart(2, "0")).join(":")
        : [minutes, remainder].map((value) => String(value).padStart(2, "0")).join(":")
}

function signalBars(mode: CameraHudPayload["mode"]) {
    return mode === "cctv" ? 4 : mode === "helicam" ? 3 : 5
}

export function CameraHud() {
    const [state, setState] = useState<CameraHudPayload | null>(null)

    useNuiEvent<CameraHudPayload>("camera:open", (payload) => {
        setState({ ...EMPTY_STATE, ...payload, active: true })
    })

    useNuiEvent<Partial<CameraHudPayload>>("camera:update", (payload) => {
        setState((current) => current ? { ...current, ...payload } : current)
    })

    useNuiEvent<{ elapsed?: number }>("camera:tick", (payload) => {
        if (typeof payload?.elapsed !== "number") return
        setState((current) => current ? { ...current, elapsed: payload.elapsed! } : current)
    })

    useNuiEvent("camera:close", () => setState(null))

    if (!state) return null

    const bars = signalBars(state.mode)
    const isNetwork = state.mode === "cctv"
    const statusLabel = state.recording ? "TRANSMITTING" : isNetwork ? "MONITORING" : "STANDBY"

    return (
        <div className="camera-hud" aria-label="Camera view">
            <div className="camera-vignette" />
            <div className="camera-scanlines" />
            <div className="camera-frame" aria-hidden="true">
                <i className="camera-corner camera-corner-tl" />
                <i className="camera-corner camera-corner-tr" />
                <i className="camera-corner camera-corner-bl" />
                <i className="camera-corner camera-corner-br" />
            </div>

            <header className="camera-header">
                <div className="camera-heading">
                    <span className="camera-kicker"><i className="camera-live-dot" /> {state.subtitle}</span>
                    <strong>{state.title}</strong>
                    <span className="camera-channel">{state.cameraLabel}</span>
                </div>
                <div className="camera-header-meta">
                    <span className={state.recording ? "camera-rec is-live" : "camera-rec"}>
                        <i /> {state.recording ? "REC" : "LIVE"}
                    </span>
                    {state.timestamp && <span className="camera-timecode">{formatDuration(state.elapsed)}</span>}
                </div>
            </header>

            <div className="camera-reticle" aria-hidden="true">
                <span />
                <i />
            </div>

            <aside className="camera-telemetry">
                <div className="camera-telemetry-title"><span /> SIGNAL / SECURE</div>
                <div className="camera-telemetry-row">
                    <span>LINK</span>
                    <span className="camera-bars" aria-label={`${bars} of 5 signal bars`}>
                        {[1, 2, 3, 4, 5].map((bar) => <i className={bar <= bars ? "is-on" : ""} key={bar} />)}
                    </span>
                </div>
                <div className="camera-telemetry-row"><span>FEED</span><b>{statusLabel}</b></div>
                {state.location && <div className="camera-location">{state.location}</div>}
            </aside>

            <footer className="camera-footer">
                <div className="camera-index">
                    <span className="camera-index-label">CAMERA</span>
                    <strong>{String(Math.max(1, state.cameraIndex)).padStart(2, "0")}</strong>
                    {state.totalCameras > 1 && <small>/ {String(state.totalCameras).padStart(2, "0")}</small>}
                </div>
                <div className="camera-footer-mark"><span>KORA</span><i /></div>
            </footer>
        </div>
    )
}
