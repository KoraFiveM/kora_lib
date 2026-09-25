import { afterEach, describe, expect, it, vi } from "vitest"

import { copyToClipboard } from "./clipboard"

describe("copyToClipboard", () => {
    afterEach(() => {
        vi.restoreAllMocks()
        Object.defineProperty(navigator, "clipboard", { configurable: true, value: undefined })
        document.body.replaceChildren()
    })

    it("uses the textarea copy path even when the Clipboard API is available", async () => {
        const writeText = vi.fn().mockResolvedValue(undefined)
        Object.assign(navigator, { clipboard: { writeText } })
        const execCommand = vi.fn().mockReturnValue(true)
        Object.defineProperty(document, "execCommand", { configurable: true, value: execCommand })

        await copyToClipboard("zone data")

        expect(writeText).not.toHaveBeenCalled()
        expect(execCommand).toHaveBeenCalledWith("copy")
        expect(document.body.querySelector("textarea")).toBeNull()
    })

    it("selects and removes the textarea after copying", async () => {
        const execCommand = vi.fn().mockReturnValue(true)
        Object.defineProperty(document, "execCommand", { configurable: true, value: execCommand })
        const select = vi.spyOn(HTMLTextAreaElement.prototype, "select")

        await copyToClipboard("zone data")

        expect(select).toHaveBeenCalled()
        expect(execCommand).toHaveBeenCalledWith("copy")
        expect(document.body.querySelector("textarea")).toBeNull()
    })
})
