import { act, render, screen } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { describe, expect, it, vi } from "vitest"

const fetchNuiMock = vi.hoisted(() => vi.fn(async () => ({})))
vi.mock("@/lib/fetchNui", async (importOriginal) => ({
    ...await importOriginal<typeof import("@/lib/fetchNui")>(),
    fetchNui: fetchNuiMock,
}))

import { MenuContainer } from "@/components/menu/Menu"
import type { NuiRequestEnvelope, NuiWireMessage, OpenMenuPayload } from "@/lib/types"

function openMenu(payload: OpenMenuPayload) {
    act(() => window.dispatchEvent(new MessageEvent<NuiWireMessage<NuiRequestEnvelope<OpenMenuPayload>>>("message", {
        data: { action: "openMenu", data: { requestId: 17, token: "menu-token", payload } },
    })))
}

function updateMenu(payload: OpenMenuPayload, requestId = 17, token = "menu-token") {
    act(() => window.dispatchEvent(new MessageEvent<NuiWireMessage<NuiRequestEnvelope<OpenMenuPayload>>>("message", {
        data: { action: "updateMenu", data: { requestId, token, payload } },
    })))
}

describe("MenuContainer interactive controls", () => {
    it("honours the initial item and keeps checkbox rows mounted when toggled", async () => {
        const user = userEvent.setup()
        render(<MenuContainer />)
        openMenu({
            title: "Settings",
            startIndex: 2,
            items: [
                { id: "plain", label: "Plain" },
                { id: "checked", label: "Enabled", checked: false },
            ],
        })

        expect(screen.getByText("Enabled").closest("[cmdk-item]")).toHaveAttribute("data-selected", "true")
        await user.click(screen.getByText("Enabled"))
        expect(screen.getByText("Enabled")).toBeInTheDocument()
        expect(screen.getByLabelText("On")).toBeInTheDocument()
    })

    it("keeps close=false confirmations visible and closes terminal rows", async () => {
        const user = userEvent.setup()
        render(<MenuContainer />)
        openMenu({
            items: [
                { id: "keep", label: "Keep open", close: false },
                { id: "close", label: "Close" },
            ],
        })

        await user.click(screen.getByText("Keep open"))
        expect(screen.getByText("Keep open")).toBeInTheDocument()
        await user.click(screen.getByRole("option", { name: "Close" }))
        expect(screen.queryByRole("option", { name: "Close" })).not.toBeInTheDocument()
    })

    it("renders rich context detail and leaves read-only rows inert", async () => {
        const user = userEvent.setup()
        render(<MenuContainer />)
        openMenu({
            title: "**Vehicle** details",
            items: [{
                id: "information",
                label: "**Engine** status",
                description: "Safe <script>bad()</script> *Markdown*",
                readOnly: true,
                arrow: true,
                metadata: [
                    { label: "Oil", value: "30%", progress: 30, colorScheme: "#22c55e" },
                    "Recently serviced",
                ],
            }],
        })

        expect(screen.getByText("Vehicle").tagName).toBe("STRONG")
        expect(screen.getByText("Engine").tagName).toBe("STRONG")
        expect(screen.getByText("Oil")).toBeInTheDocument()
        expect(screen.getByText("Recently serviced")).toBeInTheDocument()
        expect(document.querySelector("script")).toBeNull()

        await user.click(screen.getByText("Engine"))
        expect(screen.getByText("Engine")).toBeInTheDocument()
    })

    it("renders compact panels without a modal backdrop and backs out before Escape closes", async () => {
        const user = userEvent.setup()
        render(<MenuContainer />)
        openMenu({
            title: "Actions",
            presentation: "panel",
            position: { horizontal: "right", vertical: "top" },
            items: [{ id: "tools", label: "Tools", submenu: { items: [{ id: "repair", label: "Repair" }] } }],
        })

        expect(screen.getByRole("dialog", { name: "Actions" })).toHaveAttribute("aria-modal", "false")
        expect(document.querySelector(".bg-modal-overlay")).toBeNull()
        expect(screen.queryByRole("textbox")).not.toBeInTheDocument()
        const hiddenInput = document.querySelector<HTMLInputElement>("[cmdk-input]")
        expect(hiddenInput).not.toBeNull()
        expect(hiddenInput).toHaveAttribute("readonly")
        await user.type(hiddenInput!, "no matches")
        expect(screen.getByText("Tools")).toBeInTheDocument()

        await user.click(screen.getByText("Tools"))
        expect(screen.getByText("Repair")).toBeInTheDocument()
        await user.keyboard("{Escape}")
        expect(screen.getByText("Tools")).toBeInTheDocument()
        await user.keyboard("{Escape}")
        expect(screen.queryByText("Tools")).not.toBeInTheDocument()
    })

    it("uses a compact panel header for external context navigation", async () => {
        const user = userEvent.setup()
        render(<MenuContainer />)
        openMenu({
            title: "Vehicle",
            presentation: "panel",
            back: true,
            items: [{ id: "repair", label: "Repair" }],
        })

        expect(screen.getByRole("button", { name: "Back" })).toBeInTheDocument()
        expect(screen.queryByRole("option", { name: "Back" })).not.toBeInTheDocument()
        await user.click(screen.getByRole("button", { name: "Back" }))
        expect(fetchNuiMock).toHaveBeenCalledWith("kora_lib:nui:event", {
            requestId: 17,
            token: "menu-token",
            event: "back",
            data: {},
        })
        expect(screen.getByText("Repair")).toBeInTheDocument()
    })

    it("updates an authenticated panel in place without replacing its request", () => {
        render(<MenuContainer />)
        openMenu({ title: "Vehicle", presentation: "panel", items: [{ id: "repair", label: "Repair" }] })

        updateMenu({ title: "Garage", presentation: "panel", back: true, startIndex: 2, items: [
            { id: "store", label: "Store" },
            { id: "retrieve", label: "Retrieve" },
        ] })
        expect(screen.queryByText("Repair")).not.toBeInTheDocument()
        expect(screen.getByRole("dialog", { name: "Garage" })).toBeInTheDocument()
        expect(screen.getByText("Retrieve").closest("[cmdk-item]")).toHaveAttribute("data-selected", "true")
        expect(screen.getByRole("button", { name: "Back" })).toBeInTheDocument()

        updateMenu({ title: "Spoofed", presentation: "panel", items: [{ id: "bad", label: "Bad" }] }, 18)
        expect(screen.queryByText("Bad")).not.toBeInTheDocument()
        expect(screen.getByText("Store")).toBeInTheDocument()
    })
})
