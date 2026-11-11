import { act, render, screen } from "@testing-library/react"
import { describe, expect, it } from "vitest"

import { NoclipHud } from "@/components/noclip/NoclipHud"
import type { NoclipHudPayload } from "@/lib/types"

function hud(data: NoclipHudPayload | null) {
    act(() => window.dispatchEvent(new MessageEvent("message", { data: { action: "noclip:hud", data } })))
}

describe("NoclipHud", () => {
    it("hints the A/D behaviour from adMode and hides on a null payload", () => {
        const { container } = render(<NoclipHud />)
        hud({ active: true })
        expect(container).toHaveTextContent("A D strafe")

        hud({ active: true, adMode: "turn" })
        expect(container).toHaveTextContent("A D turn")
        expect(screen.getByText("Noclip")).toBeInTheDocument()

        hud(null)
        expect(container).toBeEmptyDOMElement()
    })
})
