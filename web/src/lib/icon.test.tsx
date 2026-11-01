import { fireEvent, render, waitFor } from "@testing-library/react"
import { Briefcase, Circle, DoorClosed } from "lucide-react"
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

describe("resolveIcon curated set", () => {
    it.each(["Palette", "Camera", "Receipt", "CircleDot", "Armchair", "Lightbulb", "RectangleHorizontal", "Puzzle"])("resolves %s from the bundled Lucide set", (name) => {
        expect(resolveIcon(name)?.displayName ?? "").not.toContain("FontAwesome")
    })
})

describe("resolveIcon extended Lucide names", () => {
    it.each(["FlaskConical", "DoorOpen", "Fish", "Leaf", "Building2", "TrendingUp", "Store", "Shirt", "Landmark", "ShieldCheck", "ArrowDownToLine", "LockKeyhole", "House", "Warehouse", "Tag", "Ruler"])("resolves %s to a bundled Lucide icon", (name) => {
        const Icon = resolveIcon(name)
        expect(Icon).not.toBeNull()
        expect(Icon).not.toBe(Circle)
        expect(Icon?.displayName ?? "").not.toContain("FontAwesome")
    })

    it("resolves casing typos and aliases", () => {
        expect(resolveIcon("BriefCase")).toBe(Briefcase)
        expect(resolveIcon("brief-case")).toBe(Briefcase)
        expect(resolveIcon("Door")).toBe(DoorClosed)
        expect(resolveIcon("door-open")).toBe(resolveIcon("DoorOpen"))
        expect(resolveIcon("building-2")).toBe(resolveIcon("Building2"))
    })
})

describe("resolveIcon fallback", () => {
    it("renders a neutral icon for unknown PascalCase names", () => {
        expect(resolveIcon("NotARealIcon")).toBe(Circle)
        const Icon = resolveIcon("NotARealIcon")!
        const { container } = render(<Icon className="h-5 w-5" />)
        expect(container.querySelector("svg")).not.toBeNull()
    })

    it("renders the fallback when a lowercase name is not a Font Awesome icon", async () => {
        const Icon = resolveIcon("definitely-not-an-icon")!
        const { container } = render(<Icon />)
        await waitFor(() => expect(container.querySelector("svg")).not.toBeNull())
    })

    it("still resolves real Font Awesome names lazily", async () => {
        const Icon = resolveIcon("fire-extinguisher")!
        const { container } = render(<Icon />)
        await waitFor(() => expect(container.querySelector("svg")).not.toBeNull())
    })
})
