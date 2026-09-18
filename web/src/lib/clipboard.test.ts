import { afterEach, describe, expect, it, vi } from "vitest"

import { copyToClipboard } from "./clipboard"

describe("copyToClipboard", () => {
    afterEach(() => {
        vi.restoreAllMocks()
        Object.defineProperty(navigator, "clipboard", { configurable: true, value: undefined })
        document.body.replaceChildren()
    })

    it("uses the modern clipboard API when it is available", async () => {
        const writeText = vi.fn().mockResolvedValue(undefined)
        Object.assign(navigator, { clipboard: { writeText } })

        await copyToClipboard("zone data")

        expect(writeText).toHaveBeenCalledWith("zone data")
        expect(document.body.querySelector("textarea")).toBeNull()
    })

    it("focuses and selects the fallback textarea for CEF copy", async () => {
        Object.defineProperty(navigator, "clipboard", {
            configurable: true,
            value: { writeText: vi.fn().mockRejectedValue(new Error("CEF fallback")) },
        })
        const execCommand = vi.fn().mockReturnValue(true)
        Object.defineProperty(document, "execCommand", { configurable: true, value: execCommand })
        const focus = vi.spyOn(HTMLTextAreaElement.prototype, "focus")
        const select = vi.spyOn(HTMLTextAreaElement.prototype, "select")
        const setSelectionRange = vi.spyOn(HTMLTextAreaElement.prototype, "setSelectionRange")

        await copyToClipboard("zone data")

        expect(focus).toHaveBeenCalled()
        expect(select).toHaveBeenCalled()
        expect(setSelectionRange).toHaveBeenCalledWith(0, "zone data".length)
        expect(execCommand).toHaveBeenCalledWith("copy")
        expect(document.body.querySelector("textarea")).toBeNull()
    })
})
