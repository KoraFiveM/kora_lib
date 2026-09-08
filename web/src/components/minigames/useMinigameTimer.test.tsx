import { render } from "@testing-library/react"
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"

import { useMinigameTimeout } from "@/components/minigames/useMinigameTimer"

function Timer({ timeLimit, onTimeout }: { timeLimit: number; onTimeout: () => void }) {
    useMinigameTimeout(timeLimit, onTimeout)
    return null
}

describe("useMinigameTimeout", () => {
    beforeEach(() => vi.useFakeTimers())
    afterEach(() => vi.useRealTimers())

    it("keeps one deadline while using the latest completion callback", () => {
        const first = vi.fn()
        const latest = vi.fn()
        const { rerender } = render(<Timer timeLimit={1000} onTimeout={first} />)

        vi.advanceTimersByTime(600)
        rerender(<Timer timeLimit={1000} onTimeout={latest} />)
        vi.advanceTimersByTime(399)
        expect(first).not.toHaveBeenCalled()
        expect(latest).not.toHaveBeenCalled()

        vi.advanceTimersByTime(1)
        expect(first).not.toHaveBeenCalled()
        expect(latest).toHaveBeenCalledOnce()
    })

    it("cancels the deadline when the game unmounts", () => {
        const onTimeout = vi.fn()
        const { unmount } = render(<Timer timeLimit={1000} onTimeout={onTimeout} />)

        unmount()
        vi.advanceTimersByTime(1000)

        expect(onTimeout).not.toHaveBeenCalled()
    })
})
