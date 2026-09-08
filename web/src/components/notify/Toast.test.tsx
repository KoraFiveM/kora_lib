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
})
