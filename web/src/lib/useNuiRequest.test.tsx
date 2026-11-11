import { act, render } from "@testing-library/react"
import { beforeEach, describe, expect, it, vi } from "vitest"

import { respondToNui } from "@/lib/fetchNui"
import type { NuiWireMessage } from "@/lib/types"
import { useNuiRequest } from "@/lib/useNuiRequest"

vi.mock("@/lib/fetchNui", () => ({
    fetchNui: vi.fn(() => Promise.resolve({})),
    respondToNui: vi.fn(() => Promise.resolve()),
    isBrowserEnv: false,
}))

const respondToNuiMock = vi.mocked(respondToNui)

function open(requestId: number) {
    act(() => window.dispatchEvent(new MessageEvent<NuiWireMessage<unknown>>("message", {
        data: { action: "test:surface", data: { requestId, token: `token-${requestId}`, payload: {} } },
    })))
}

function Surface({ fallback }: { fallback?: { cancelled: true } }) {
    const { isOpen } = useNuiRequest<unknown, { cancelled: true }>("test:surface", undefined, fallback)
    return isOpen ? <div>open</div> : null
}

beforeEach(() => respondToNuiMock.mockClear())

describe("useNuiRequest", () => {
    it("answers a still-open request with the surface's cancel result when it unmounts", () => {
        const { unmount } = render(<Surface fallback={{ cancelled: true }} />)
        open(1)
        unmount()
        expect(respondToNuiMock).toHaveBeenCalledTimes(1)
        expect(respondToNuiMock).toHaveBeenCalledWith(1, "token-1", true, { cancelled: true })
    })

    it("answers with an error when the surface has no cancel result", () => {
        const { unmount } = render(<Surface />)
        open(2)
        unmount()
        expect(respondToNuiMock).toHaveBeenCalledWith(2, "token-2", false, expect.any(String))
    })

    it("does not answer twice or answer when nothing is open", () => {
        const { unmount } = render(<Surface fallback={{ cancelled: true }} />)
        unmount()
        expect(respondToNuiMock).not.toHaveBeenCalled()
    })
})
