import { act, render, screen } from "@testing-library/react"
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"

import { ProgressBar } from "@/components/progressbar/ProgressBar"
import type { NuiWireMessage, ProgressStartPayload } from "@/lib/types"

function startProgress(payload: ProgressStartPayload) {
    act(() => window.dispatchEvent(new MessageEvent<NuiWireMessage<ProgressStartPayload>>("message", {
        data: { action: "progressStart", data: payload },
    })))
}

describe("ProgressBar", () => {
    let now = 0

    beforeEach(() => {
        now = 0
        vi.useFakeTimers()
        vi.spyOn(performance, "now").mockImplementation(() => now)
    })
    afterEach(() => {
        vi.restoreAllMocks()
        vi.useRealTimers()
    })

    it("exposes semantic progress without re-rendering on every frame", () => {
        render(<ProgressBar />)
        startProgress({ label: "Repairing", duration: 1000 })
        const progress = screen.getByRole("progressbar", { name: "Repairing" })

        expect(progress).toHaveAttribute("aria-valuenow", "0")
        now = 250
        act(() => vi.advanceTimersByTime(250))
        expect(progress).toHaveAttribute("aria-valuenow", "250")

        act(() => vi.advanceTimersByTime(750))
        expect(screen.queryByRole("progressbar", { name: "Repairing" })).not.toBeInTheDocument()
    })

    it("renders ox-compatible circular progress in the requested position", () => {
        render(<ProgressBar />)
        startProgress({ label: "Searching", duration: 1000, presentation: "circle", position: "middle" })

        const progress = screen.getByRole("progressbar", { name: "Searching" })
        expect(progress.closest(".fixed")).toHaveClass("top-1/2")
        expect(progress.querySelector(".progress-circle")).toBeInTheDocument()
    })

    it("sits above kora_hud's vitals by default and follows Config.progressbar.bottomOffset", () => {
        render(<ProgressBar />)
        startProgress({ label: "Repairing", duration: 1000 })
        expect(screen.getByRole("progressbar", { name: "Repairing" }).closest(".fixed")).toHaveStyle({ bottom: "10rem" })

        startProgress({ label: "Lockpicking", duration: 1000, bottomOffset: 12 })
        expect(screen.getByRole("progressbar", { name: "Lockpicking" }).closest(".fixed")).toHaveStyle({ bottom: "12rem" })

        startProgress({ label: "Searching", duration: 1000, presentation: "circle", position: "bottom", bottomOffset: 8 })
        expect(screen.getByRole("progressbar", { name: "Searching" }).closest(".fixed")).toHaveStyle({ bottom: "8rem" })
    })
})
