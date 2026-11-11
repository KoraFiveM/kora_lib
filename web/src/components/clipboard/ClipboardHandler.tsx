import type { CopyToClipboardPayload, NuiRequestEnvelope } from "@/lib/types"
import { copyToClipboard } from "@/lib/clipboard"
import { respondToNui } from "@/lib/fetchNui"
import { useNuiEvent } from "@/lib/useNuiEvent"

/**
 * Handles Kora.nui.copyToClipboard requests from Lua (see
 * modules/nui/client.lua). Purely a side-effect component -- it never
 * renders anything and should stay mounted once at the app root alongside
 * every other top-level NUI component.
 */
export function ClipboardHandler() {
    useNuiEvent<NuiRequestEnvelope<CopyToClipboardPayload>>("copyToClipboard", async (msg) => {
        try {
            const copied = await copyToClipboard(msg.payload.text)
            respondToNui(msg.requestId, msg.token, true, copied)
        } catch (error) {
            respondToNui(msg.requestId, msg.token, false, "Failed to copy to clipboard: " + String(error))
        }
    })

    return null
}
