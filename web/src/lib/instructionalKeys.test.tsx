import { act, render, screen } from "@testing-library/react"
import { describe, expect, it } from "vitest"

import { InstructionalKeysSource, StandaloneKeyHints } from "@/components/editor/InstructionalKeys"
import { EditorControlsHud } from "@/components/editor/EditorControlsHud"

const send = (buttons: unknown[]) =>
    act(() => {
        window.dispatchEvent(new MessageEvent("message", { data: { action: "instructional:set", data: { buttons } } }))
    })

describe("instructional keys", () => {
    it("shows kbd rows standalone and hides when emptied", () => {
        render(<><InstructionalKeysSource /><StandaloneKeyHints /></>)
        send([{ label: "Place point", keys: ["E", "LMB"] }])
        expect(screen.getByText("Place point")).toBeTruthy()
        expect(screen.getByText("LMB").tagName).toBe("KBD")
        send([])
        expect(screen.queryByText("Place point")).toBeNull()
    })

    it("renders inside the editor HUD instead of the standalone pill", () => {
        render(<><InstructionalKeysSource /><StandaloneKeyHints /><EditorControlsHud title="T" /></>)
        send([{ label: "Undo", keys: ["BACK"] }])
        expect(screen.getAllByText("Undo")).toHaveLength(1)
        expect(screen.getByLabelText("Editor controls").textContent).toContain("Undo")
    })
})
