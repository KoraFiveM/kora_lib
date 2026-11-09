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
            if (event.data?.action === action) {
                handlerRef.current(event.data.data)
            }
        }

        window.addEventListener("message", listener)
        return () => window.removeEventListener("message", listener)
    }, [action])
}
