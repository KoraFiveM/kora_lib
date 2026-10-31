import { useEffect, useRef } from "react"

import type { NuiWireMessage } from "./types"

/**
 * Subscribes to messages sent from Lua via Kora.nui.send/Kora.nui.request for a
 * single `action` name. `handler` receives the message's `data` verbatim --
 * for a request/response action that's a NuiRequestEnvelope ({ requestId,
 * token, payload }), for a fire-and-forget action it's the raw payload.
 *
 * The `window` listener is only ever attached/removed when `action` changes
 * (or on mount/unmount) -- the latest `handler` is called via a ref rather
 * than being a dependency itself, so passing a fresh inline arrow every
 * render (as most callers do) doesn't tear down and re-add the listener on
 * every re-render.
 */
export function useNuiEvent<T = unknown>(action: string, handler: (data: T) => void) {
    const handlerRef = useRef(handler)
    handlerRef.current = handler

    useEffect(() => {
        function listener(event: MessageEvent<NuiWireMessage<T>>) {
            // DELIBERATELY no event.source / event.origin check here.
            //
            // FiveM does NOT deliver SendNUIMessage from this frame: it posts
            // from the game's own NUI window, which arrives with
            // origin "nui://game" and an event.source that is a real window
            // object but is NOT this one. Verified in-game -- the same message
            // posted in-page arrives as { origin: "https://cfx-nui-<res>",
            // source: window } while the identical message from Lua arrives as
            // { origin: "nui://game", source: <other window> }.
            //
            // So ANY form of source/origin gate (`!== window`, or a
            // null-tolerant `source && source !== window`) silently discards
            // every real message from Lua while still letting in-page test
            // posts through -- which presents in-game as "the NUI is
            // completely broken" with no error anywhere, and is exactly the
            // trap this comment exists to stop someone re-introducing.
            //
            // Nothing is lost by omitting it: another resource's NUI page has
            // no window handle to post here with, and the actual
            // response-spoofing concern is handled by the per-request token in
            // lib/fetchNui.ts (see modules/nui/AGENTS.md).
            if (event.data?.action === action) {
                handlerRef.current(event.data.data)
            }
        }

        window.addEventListener("message", listener)
        return () => window.removeEventListener("message", listener)
    }, [action])
}
