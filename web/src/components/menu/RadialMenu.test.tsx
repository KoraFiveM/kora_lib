import { act, render, screen } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { describe, expect, it } from "vitest"

import { RadialMenuContainer } from "@/components/menu/RadialMenu"
import type { NuiRequestEnvelope, NuiWireMessage, OpenRadialMenuPayload } from "@/lib/types"

const envelope = (payload: OpenRadialMenuPayload): NuiRequestEnvelope<OpenRadialMenuPayload> => ({
    requestId: 31,
    token: "radial-token",
    payload,
})

function message(action: string, payload: OpenRadialMenuPayload) {
    act(() => window.dispatchEvent(new MessageEvent<NuiWireMessage<NuiRequestEnvelope<OpenRadialMenuPayload>>>("message", {
        data: { action, data: envelope(payload) },
    })))
}

describe("RadialMenuContainer live updates", () => {
    it("preserves the deepest valid submenu and backs up when it is removed", async () => {
        const user = userEvent.setup()
        render(<RadialMenuContainer />)
        const root = {
            items: [{
                id: "tools",
                label: "Open tools",
                submenu: { title: "Tools", items: [{ id: "repair", label: "Repair" }] },
            }],
        }
        message("openRadialMenu", root)
        await user.click(screen.getByRole("menuitem", { name: "Open tools" }))
        expect(screen.getByRole("menuitem", { name: "Repair" })).toBeInTheDocument()

        message("updateRadialMenu", {
            items: [{
                id: "tools",
                label: "Open tools",
                submenu: { title: "Tools", items: [{ id: "repair", label: "Repair updated" }] },
            }],
        })
        expect(screen.getByRole("menuitem", { name: "Repair updated" })).toBeInTheDocument()

        message("updateRadialMenu", { items: [{ id: "status", label: "Status" }] })
        expect(screen.getByRole("menuitem", { name: "Status" })).toBeInTheDocument()
        expect(screen.queryByRole("menuitem", { name: "Repair updated" })).not.toBeInTheDocument()
    })
})

describe("RadialMenuContainer long labels", () => {
    it("wraps and clamps tile labels, keeping the full label in title and the hub", () => {
        render(<RadialMenuContainer />)
        message("openRadialMenu", { items: [{ id: "emote", label: "TurtleDoeTest1.0" }, { id: "b", label: "Short" }] })
        const tile = screen.getByRole("menuitem", { name: "TurtleDoeTest1.0" })
        expect(tile).toHaveAttribute("title", "TurtleDoeTest1.0")
        const label = tile.querySelector("span.overflow-hidden") as HTMLElement
        expect(label.className).not.toContain("truncate")
        expect(label.style.webkitLineClamp).toBe("3")
        expect(screen.getAllByText("TurtleDoeTest1.0").length).toBe(2)
    })

    it("honours labelLines from the payload", () => {
        render(<RadialMenuContainer />)
        message("openRadialMenu", { labelLines: 2, items: [{ id: "v", label: "Vehicle Doors" }] })
        const label = screen.getByRole("menuitem", { name: "Vehicle Doors" }).querySelector("span.overflow-hidden") as HTMLElement
        expect(label.style.webkitLineClamp).toBe("2")
    })
})
