/**
 * Copies `text` to the system clipboard using CEF's textarea-based copy path.
 * This avoids the permission-gated Clipboard API used by NUI frames.
 */
export async function copyToClipboard(text: string): Promise<void> {
    const textarea = document.createElement("textarea")
    textarea.value = text
    document.body.appendChild(textarea)

    try {
        textarea.select()
        const succeeded = document.execCommand("copy")
        if (!succeeded) throw new Error("execCommand('copy') returned false")
    } finally {
        document.body.removeChild(textarea)
    }
}
