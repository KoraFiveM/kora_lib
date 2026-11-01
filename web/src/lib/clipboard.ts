/**
 * Copies `text` via a focused, selected textarea and `execCommand("copy")`.
 * CEF only honours this while the document has focus, so the textarea is
 * focused explicitly (Kora.nui.copyToClipboard also grants a brief focus lease).
 */
function copyWithTextarea(text: string): boolean {
    const textarea = document.createElement("textarea")
    textarea.value = text
    textarea.setAttribute("readonly", "")
    textarea.style.position = "fixed"
    textarea.style.top = "0"
    textarea.style.left = "0"
    textarea.style.opacity = "0"
    textarea.style.pointerEvents = "none"
    document.body.appendChild(textarea)

    try {
        textarea.focus({ preventScroll: true })
        textarea.select()
        textarea.setSelectionRange(0, text.length)
        return document.execCommand("copy") === true
    } catch {
        return false
    } finally {
        document.body.removeChild(textarea)
    }
}

/**
 * Copies `text` to the system clipboard. Tries the textarea path first (works
 * in NUI frames), then falls back to the async Clipboard API when available.
 * Resolves true on success and false when every path fails; never rejects.
 */
export async function copyToClipboard(text: string): Promise<boolean> {
    if (copyWithTextarea(text)) return true

    try {
        if (typeof navigator !== "undefined" && navigator.clipboard?.writeText) {
            await navigator.clipboard.writeText(text)
            return true
        }
    } catch {
        // fall through: reported to Lua as a failed copy
    }
    return false
}
