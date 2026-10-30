import type { NuiResponseEnvelope } from "./types"

declare global {
    interface Window {
        GetParentResourceName?: () => string
        invokeNative?: (...args: unknown[]) => unknown
    }
}

// True when running outside the CEF NUI frame (e.g. `pnpm dev` in a normal
// browser) -- lets components render/develop without a game to talk to.
export const isBrowserEnv = typeof window.invokeNative !== "function"

function resourceName(): string {
    return window.GetParentResourceName ? window.GetParentResourceName() : "kora_lib"
}

/**
 * Calls an NUI callback registered via QB.nui.registerCallback (Lua side).
 * In a plain browser (isBrowserEnv) this never reaches Lua -- it resolves an
 * empty object so components stay usable in isolation during development.
 */
export async function fetchNui<T = unknown>(callbackName: string, data: unknown = {}): Promise<T> {
    if (isBrowserEnv) {
        return {} as T
    }

    const response = await fetch(`https://${resourceName()}/${callbackName}`, {
        method: "POST",
        headers: { "Content-Type": "application/json; charset=UTF-8" },
        body: JSON.stringify(data),
    })

    if (!response.ok) {
        throw new Error(`NUI callback '${callbackName}' failed: ${response.status}`)
    }

    return (await response.json()) as T
}

/**
 * Resolves the QB.nui.request call on the Lua side that's waiting on
 * `requestId`, via the one shared "kora_lib:nui:response" callback every request
 * flows through (see modules/nui/client.lua). Every component that answers a
 * Lua request (menu selection, input dialog submit, zone creator confirm,
 * clipboard write) should settle it through this, not a bespoke callback name.
 *
 * `token` must be the exact token the request arrived with (NuiRequestEnvelope.token)
 * -- Lua ignores any response whose token doesn't match, since FiveM's NUI
 * callback routing isn't scoped to the frame that issued the request. Always
 * forward the token you received; never invent one.
 *
 * Never rejects: no call site awaits the reply (the Lua side settles its own
 * promise), so a failed POST is logged instead of becoming an unhandled
 * rejection in the NUI console.
 */
export function respondToNui<T = unknown>(requestId: number, token: string, ok: boolean, resultOrError: T | string) {
    const body: NuiResponseEnvelope<T> = ok
        ? { requestId, token, ok: true, result: resultOrError as T }
        : { requestId, token, ok: false, error: String(resultOrError) }

    return fetchNui("kora_lib:nui:response", body).catch((error) => {
        console.error(`[kora_lib] respondToNui failed for request ${requestId}:`, error)
    })
}
