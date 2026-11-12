import { afterEach, describe, expect, it, vi } from "vitest"

import { copyToClipboard } from "./clipboard"

describe("copyToClipboard", () => {
    afterEach(() => {
        vi.restoreAllMocks()
        Object.defineProperty(navigator, "clipboard", { configurable: true, value: undefined })
        document.body.replaceChildren()
    })

    it("uses the textarea copy path and never the Clipboard API", async () => {
        const writeText = vi.fn().mockResolvedValue(undefined)
        Object.assign(navigator, { clipboard: { writeText } })
        const execCommand = vi.fn().mockReturnValue(true)
        Object.defineProperty(document, "execCommand", { configurable: true, value: execCommand })

        await expect(copyToClipboard("zone data")).resolves.toBe(true)

        expect(writeText).not.toHaveBeenCalled()
        expect(execCommand).toHaveBeenCalledWith("copy")
        expect(document.body.querySelector("textarea")).toBeNull()
    })

    it("selects an attached, laid-out textarea holding the text and removes it after copying", async () => {
        let seen: { value: string; connected: boolean; display: string } | undefined
        Object.defineProperty(document, "execCommand", { configurable: true, value: vi.fn(() => {
            const textarea = document.activeElement as HTMLTextAreaElement
            seen = { value: textarea.value, connected: textarea.isConnected, display: textarea.style.display }
            return true
        }) })
        const select = vi.spyOn(HTMLTextAreaElement.prototype, "select")

        await copyToClipboard("prop_bench_01a")

        expect(select).toHaveBeenCalled()
        expect(seen).toEqual({ value: "prop_bench_01a", connected: true, display: "" })
        expect(document.body.querySelector("textarea")).toBeNull()
    })

    it("puts the text on the copy event's clipboardData", async () => {
        const setData = vi.fn()
        Object.defineProperty(document, "execCommand", { configurable: true, value: vi.fn(() => {
            const event = new Event("copy", { bubbles: true, cancelable: true }) as ClipboardEvent
            Object.defineProperty(event, "clipboardData", { value: { setData } })
            document.activeElement?.dispatchEvent(event)
            return event.defaultPrevented
        }) })

        await expect(copyToClipboard("adder")).resolves.toBe(true)
        expect(setData).toHaveBeenCalledWith("text/plain", "adder")
    })

    it("copies repeatedly and gives focus and caret back to a focused input", async () => {
        Object.defineProperty(document, "execCommand", { configurable: true, value: vi.fn().mockReturnValue(true) })
        const input = document.createElement("input")
        input.value = "search text"
        document.body.appendChild(input)
        input.focus()
        input.setSelectionRange(2, 5)

        await expect(copyToClipboard("first")).resolves.toBe(true)
        await expect(copyToClipboard("second")).resolves.toBe(true)

        expect(document.activeElement).toBe(input)
        expect([input.selectionStart, input.selectionEnd]).toEqual([2, 5])
        expect(document.body.querySelectorAll("textarea")).toHaveLength(0)
    })

    it("resolves false instead of throwing when the browser refuses", async () => {
        const writeText = vi.fn().mockResolvedValue(undefined)
        Object.assign(navigator, { clipboard: { writeText } })
        Object.defineProperty(document, "execCommand", { configurable: true, value: vi.fn().mockReturnValue(false) })

        await expect(copyToClipboard("zone data")).resolves.toBe(false)
        expect(writeText).not.toHaveBeenCalled()
        expect(document.body.querySelector("textarea")).toBeNull()
    })

    it("resolves false when execCommand throws", async () => {
        Object.defineProperty(document, "execCommand", { configurable: true, value: vi.fn(() => { throw new Error("nope") }) })

        await expect(copyToClipboard("zone data")).resolves.toBe(false)
        expect(document.body.querySelector("textarea")).toBeNull()
    })
})
