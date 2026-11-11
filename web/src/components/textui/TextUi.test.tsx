import { act, render, screen } from "@testing-library/react"
import { describe, expect, it } from "vitest"

import { TextUi } from "@/components/textui/TextUi"
import type { NuiWireMessage, TextUiPayload } from "@/lib/types"

function showText(payload: TextUiPayload) {
    act(() => window.dispatchEvent(new MessageEvent<NuiWireMessage<TextUiPayload>>("message", {
        data: { action: "textui:set", data: payload },
    })))
}

describe("TextUi", () => {
    it("renders safe Markdown and ox-compatible icon presentation without enabling input", () => {
        render(<TextUi />)
        showText({
            id: 1,
            text: "Press **now** <script>bad()</script>",
            icon: "Bell",
            iconColor: "#22c55e",
            iconAnimation: "pulse",
            alignIcon: "top",
            style: { backgroundColor: "rgb(1, 2, 3)", pointerEvents: "auto" },
            position: "right-center",
        })

        expect(screen.getByText("now").tagName).toBe("STRONG")
        expect(document.querySelector("script")).toBeNull()
        expect(screen.getByRole("status").firstElementChild).toHaveStyle({ backgroundColor: "rgb(1, 2, 3)" })
        expect(screen.getByRole("status").firstElementChild?.getAttribute("style") ?? "").not.toContain("pointer-events")
        expect(document.querySelector(".icon-animation-pulse")).toBeInTheDocument()
    })

    it("parses CSS declaration strings as scoped inline styles", () => {
        render(<TextUi />)
        showText({
            id: 2,
            text: "Scoped",
            style: "background-color: rgb(4, 5, 6); color: rgb(250, 250, 250); pointer-events: auto; } body { display: none;",
            position: "left-center",
        })

        const surface = screen.getByRole("status").firstElementChild
        expect(surface).toHaveStyle({ backgroundColor: "rgb(4, 5, 6)", color: "rgb(250, 250, 250)" })
        expect(surface?.getAttribute("style") ?? "").not.toContain("pointer-events")
        expect(document.body).not.toHaveStyle({ display: "none" })
        expect(document.styleSheets).toHaveLength(0)
    })
})
