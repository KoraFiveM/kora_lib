import { fireEvent, render } from "@testing-library/react"
import { describe, expect, it } from "vitest"

import { resolveIcon } from "@/lib/icon"

describe("resolveIcon image compatibility", () => {
    it("renders recognized web/NUI image URLs and hides a failed image", () => {
        const Icon = resolveIcon("nui://inventory/html/icon.png")
        expect(Icon).not.toBeNull()
        const { container } = render(Icon ? <Icon aria-hidden className="h-5 w-5" /> : null)
        const image = container.querySelector("img")
        expect(image).toHaveAttribute("src", "nui://inventory/html/icon.png")
        expect(image).toHaveClass("h-5", "w-5")

        fireEvent.error(image!)
        expect(container.querySelector("img")).toBeNull()
    })

    it("does not treat active-content protocols as images", () => {
        expect(resolveIcon("javascript:alert(1)")).toBeNull()
        expect(resolveIcon("data:text/html,bad")).toBeNull()
    })
})
