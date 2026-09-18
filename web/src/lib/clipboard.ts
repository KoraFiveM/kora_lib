/**
 * Copies `text` to the system clipboard using the modern async Clipboard API,
 * falling back to the classic hidden-textarea + execCommand("copy") technique
 * when that throws or silently fails -- CEF's Clipboard API can be
 * permission-gated depending on how the NUI frame was loaded, so the fallback
 * is what makes this reliable in-game rather than just in a regular browser.
 * Throws if both paths fail, so callers can tell success from failure.
 */
export async function copyToClipboard(text: string): Promise<void> {
    try {
        await navigator.clipboard?.writeText(text)
        return
    } catch {
        // Fall through to the legacy fallback below.
    }

    const previousActiveElement = document.activeElement as HTMLElement | null
    const textarea = document.createElement("textarea")
    textarea.value = text
    textarea.setAttribute("readonly", "")
    textarea.style.position = "fixed"
    textarea.style.left = "-9999px"
    textarea.style.top = "0"
    textarea.style.opacity = "0.01"
    document.body.appendChild(textarea)

    try {
        // CEF's execCommand implementation requires the selection to belong
        // to the focused document. A select() alone can report success while
        // leaving the system clipboard unchanged.
        textarea.focus({ preventScroll: true })
        textarea.select()
        textarea.setSelectionRange(0, textarea.value.length)
        const succeeded = document.execCommand("copy")
        if (!succeeded) throw new Error("execCommand('copy') returned false")
    } finally {
        document.body.removeChild(textarea)
        previousActiveElement?.focus({ preventScroll: true })
    }
}
