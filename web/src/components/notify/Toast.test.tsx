import { act, render, screen } from "@testing-library/react"
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"

import { Toast } from "@/components/notify/Toast"
import type { NuiWireMessage, NotifyPayload } from "@/lib/types"

function notify(payload: NotifyPayload) {
    act(() => window.dispatchEvent(new MessageEvent<NuiWireMessage<NotifyPayload>>("message", {
        data: { action: "notify", data: payload },
    })))
}

describe("Toast", () => {
    beforeEach(() => vi.useFakeTimers())
    afterEach(() => vi.useRealTimers())

    it("honours a positive caller-supplied duration below the default", () => {
        render(<Toast />)
        notify({ message: "Brief update", duration: 250 })

        expect(screen.getByRole("status")).toHaveTextContent("Brief update")
        act(() => vi.advanceTimersByTime(249))
        expect(screen.getByRole("status")).toBeInTheDocument()
        act(() => vi.advanceTimersByTime(1))
        expect(screen.queryByRole("status")).not.toBeInTheDocument()
    })

    it("falls back to the default duration for a non-finite raw NUI payload", () => {
        render(<Toast />)
        notify({ message: "Safe fallback", duration: Number.POSITIVE_INFINITY })

        act(() => vi.advanceTimersByTime(4999))
        expect(screen.getByRole("status")).toBeInTheDocument()
        act(() => vi.advanceTimersByTime(1))
        expect(screen.queryByRole("status")).not.toBeInTheDocument()
    })

    it("replaces an existing toast by id and restarts its lifetime", () => {
        render(<Toast />)
        notify({ id: "job", message: "Starting", duration: 1000 })
        act(() => vi.advanceTimersByTime(900))
        notify({ id: "job", message: "Complete", duration: 1000, position: "center-right" })

        expect(screen.getAllByRole("status")).toHaveLength(1)
        expect(screen.getByRole("status")).toHaveTextContent("Complete")
        act(() => vi.advanceTimersByTime(999))
        expect(screen.getByRole("status")).toBeInTheDocument()
        act(() => vi.advanceTimersByTime(1))
        expect(screen.queryByRole("status")).not.toBeInTheDocument()
    })

    it("renders safe Markdown and vetted nested text styles", () => {
        render(<Toast />)
        notify({
            title: "Update",
            message: "**Ready** <script>bad()</script>",
            icon: "Bell",
            iconAnimation: "shake",
            alignIcon: "top",
            style: {
                backgroundColor: "rgb(1, 2, 3)",
                "& .description": { color: "rgb(4, 5, 6)", pointerEvents: "auto" },
                "& .unknown": { display: "none" },
            },
        })

        expect(screen.getByText("Ready").tagName).toBe("STRONG")
        expect(document.querySelector("script")).toBeNull()
        expect(screen.getByRole("status")).toHaveStyle({ backgroundColor: "rgb(1, 2, 3)" })
        expect(screen.getByText("Ready").closest("div")).toHaveStyle({ color: "rgb(4, 5, 6)" })
        expect(screen.getByText("Ready").closest("div")?.getAttribute("style") ?? "").not.toContain("pointer-events")
        expect(document.querySelector(".icon-animation-shake")).toBeInTheDocument()
    })
})
