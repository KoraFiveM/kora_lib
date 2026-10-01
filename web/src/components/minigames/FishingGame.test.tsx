import { act, fireEvent, render, screen } from "@testing-library/react"
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"

import { FishingGame } from "@/components/minigames/FishingGame"
import type { FishingPuzzle } from "@/lib/types"

let elapsed = 0
const puzzle: FishingPuzzle = { gameCount: 2, speed: 1, zoneSize: .2, targets: [.2, .8] }
const reel = (milliseconds: number, code = "Space") => {
    elapsed = milliseconds
    fireEvent.keyDown(window, { key: code === "Space" ? " " : "Enter", code })
}

beforeEach(() => {
    elapsed = 0
    vi.useFakeTimers()
    vi.spyOn(performance, "now").mockImplementation(() => elapsed)
    vi.stubGlobal("requestAnimationFrame", vi.fn(() => 1))
    vi.stubGlobal("cancelAnimationFrame", vi.fn())
})
afterEach(() => {
    vi.useRealTimers()
    vi.restoreAllMocks()
    vi.unstubAllGlobals()
})

describe("FishingGame displayed target feedback", () => {
    it("scores consecutive off-center displayed windows and preserves reel timestamps", () => {
        const respond = vi.fn()
        render(<FishingGame puzzle={puzzle} attempt={1} attempts={3} timeLimit={10000} respond={respond} />)
        expect(document.querySelector(".border-brand-border")).toHaveStyle({ bottom: "10%", height: "20%" })
        reel(100)
        expect(document.querySelectorAll(".bg-success")).toHaveLength(1)
        expect(screen.getByText("Game 2 of 2")).toBeInTheDocument()
        expect(document.querySelector(".border-brand-border")).toHaveStyle({ bottom: "70%" })
        fireEvent.keyDown(window, { code: "Space", repeat: true })
        expect(respond).not.toHaveBeenCalled()
        reel(400, "Enter")
        expect(document.querySelectorAll(".bg-success")).toHaveLength(2)
        expect(respond).toHaveBeenCalledOnce()
        expect(respond).toHaveBeenCalledWith({ reels: [{ index: 1, elapsed: 100 }, { index: 2, elapsed: 400 }] })
        reel(450)
        act(() => vi.advanceTimersByTime(10000))
        expect(respond).toHaveBeenCalledOnce()
    })

    it("marks a center reel outside the visible off-center target as a miss", () => {
        const respond = vi.fn()
        render(<FishingGame puzzle={{ ...puzzle, gameCount: 1, targets: [.2] }} attempt={1} attempts={3} timeLimit={10000} respond={respond} />)
        reel(250)
        expect(document.querySelectorAll(".bg-destructive")).toHaveLength(1)
        expect(document.querySelectorAll(".bg-success")).toHaveLength(0)
        expect(respond).toHaveBeenCalledOnce()
        expect(respond).toHaveBeenCalledWith({ reels: [{ index: 1, elapsed: 250 }] })
    })

    it("retains inclusive target boundaries", () => {
        const respond = vi.fn()
        render(<FishingGame puzzle={{ ...puzzle, zoneSize: .25, targets: [.25, .25] }} attempt={1} attempts={3} timeLimit={10000} respond={respond} />)
        reel(1062.5)
        reel(2187.5)
        expect(document.querySelectorAll(".bg-success")).toHaveLength(2)
        expect(respond).toHaveBeenCalledOnce()
        expect(respond).toHaveBeenCalledWith({ reels: [{ index: 1, elapsed: 1062.5 }, { index: 2, elapsed: 2187.5 }] })
    })

    it("keeps timeout partial reels and Escape cancellation contracts", () => {
        const respond = vi.fn()
        const { unmount } = render(<FishingGame puzzle={puzzle} attempt={1} attempts={3} timeLimit={10000} respond={respond} />)
        reel(100)
        act(() => vi.advanceTimersByTime(10000))
        expect(respond).toHaveBeenCalledOnce()
        expect(respond).toHaveBeenCalledWith({ reels: [{ index: 1, elapsed: 100 }] })
        unmount()
        const cancelled = vi.fn()
        render(<FishingGame puzzle={puzzle} attempt={1} attempts={3} timeLimit={10000} respond={cancelled} />)
        fireEvent.keyDown(document, { key: "Escape", code: "Escape" })
        expect(cancelled).toHaveBeenCalledOnce()
        expect(cancelled).toHaveBeenCalledWith({ cancelled: true })
        act(() => vi.advanceTimersByTime(10000))
        expect(cancelled).toHaveBeenCalledOnce()
    })
})
