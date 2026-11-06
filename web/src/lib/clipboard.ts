type TextSelection = { start: number | null; end: number | null; direction: "forward" | "backward" | "none" | null }

function textSelection(element: Element | null): TextSelection | undefined {
    if (!(element instanceof HTMLInputElement || element instanceof HTMLTextAreaElement)) return undefined
    try {
        return { start: element.selectionStart, end: element.selectionEnd, direction: element.selectionDirection }
    } catch {
        return undefined // input types without a text selection (number, email, ...)
    }
}

/**
 * Copies `text` to the system clipboard the way FiveM NUI allows it, the same way ox_lib's
 * lib.setClipboard does: a temporary textarea in the page, selected, then
 * `document.execCommand("copy")`. It needs no NUI focus.
 *
 * - A one-shot `copy` listener also puts the text on the event's clipboardData, so the write
 *   does not depend on the textarea's selection surviving (a focused input elsewhere in the UI
 *   or another frame holding focus can leave it collapsed, which used to copy nothing or leave
 *   the previous clipboard contents).
 * - Whatever kora_lib's own UI had focused (e.g. a search box) gets its focus and caret back.
 * - The async Clipboard API is never used: NUI's permissions policy always blocks it, and the
 *   attempt only logs a "Permissions policy violation" error.
 *
 * Resolves true when the browser accepted the copy and false otherwise; never rejects.
 */
export async function copyToClipboard(text: string): Promise<boolean> {
    if (typeof document === "undefined" || !document.body) return false

    const previous = document.activeElement instanceof HTMLElement && document.activeElement !== document.body ? document.activeElement : null
    const previousSelection = textSelection(previous)
    let written = false
    const onCopy = (event: ClipboardEvent) => {
        if (!event.clipboardData) return
        event.clipboardData.setData("text/plain", text)
        event.preventDefault()
        written = true
    }
    // Cancelling beforecopy tells the browser a page handler supplies the data, which enables
    // the copy command even when the selection is empty.
    const onBeforeCopy = (event: Event) => event.preventDefault()

    // Laid out (never display:none or off-DOM) so select() produces a real selection.
    const textarea = document.createElement("textarea")
    textarea.value = text
    textarea.setAttribute("aria-hidden", "true")
    textarea.tabIndex = -1
    textarea.style.cssText = "position:fixed;top:0;left:0;width:1px;height:1px;padding:0;border:0;margin:0;opacity:0;"

    document.addEventListener("beforecopy", onBeforeCopy, true)
    document.addEventListener("copy", onCopy, true)
    document.body.appendChild(textarea)
    try {
        textarea.focus({ preventScroll: true })
        textarea.select()
        textarea.setSelectionRange(0, text.length)
        return document.execCommand("copy") === true || written
    } catch {
        return written
    } finally {
        document.removeEventListener("beforecopy", onBeforeCopy, true)
        document.removeEventListener("copy", onCopy, true)
        textarea.remove()
        if (previous?.isConnected) {
            try {
                previous.focus({ preventScroll: true })
                if (previousSelection && previousSelection.start !== null && previousSelection.end !== null) {
                    ;(previous as HTMLInputElement | HTMLTextAreaElement).setSelectionRange(previousSelection.start, previousSelection.end, previousSelection.direction ?? undefined)
                }
            } catch {
                // the previous element may no longer accept focus; nothing else to restore
            }
        }
    }
}
