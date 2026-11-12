import { act, render, screen } from "@testing-library/react"
import { afterEach, describe, expect, it, vi } from "vitest"

import { ErrorBoundary } from "@/components/ErrorBoundary"

function Surface({ crash }: { crash: boolean }) {
    if (crash) throw new Error("simulated render failure")
    return <p>Recovered surface</p>
}

describe("ErrorBoundary", () => {
    afterEach(() => vi.restoreAllMocks())

    it("isolates one surface and remounts it after a later NUI message", () => {
        vi.spyOn(console, "error").mockImplementation(() => undefined)
        const view = render(<>
            <ErrorBoundary surface="test"><Surface crash /></ErrorBoundary>
            <p>Healthy sibling</p>
        </>)

        expect(screen.getByText("Healthy sibling")).toBeInTheDocument()
        view.rerender(<>
            <ErrorBoundary surface="test"><Surface crash={false} /></ErrorBoundary>
            <p>Healthy sibling</p>
        </>)
        expect(screen.queryByText("Recovered surface")).not.toBeInTheDocument()

        act(() => window.dispatchEvent(new MessageEvent("message", { data: { action: "healthcheck" } })))
        expect(screen.getByText("Recovered surface")).toBeInTheDocument()
    })
})
