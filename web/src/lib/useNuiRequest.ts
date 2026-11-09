import { useCallback, useEffect, useRef, useState } from "react"

import { respondToNui } from "./fetchNui"
import type { NuiRequestEnvelope } from "./types"
import { useNuiEvent } from "./useNuiEvent"

interface PendingRequest<TPayload> {
    requestId: number
    token: string
    payload: TPayload
}

interface CancelledRequest {
    requestId: number
    token: string
}

/**
 * Shared "listen for a Lua Kora.nui.request, track it, respond exactly once"
 * primitive used by the dialog-shaped NUI components (menus, the input
 * dialog, the zone creator's confirm dialog). Centralizes the requestId/token
 * bookkeeping and the double-response guard so each component only has to
 * describe its own payload-specific state. (ClipboardHandler intentionally
 * doesn't use this -- it's a fire-through side effect with no open/closed
 * state, so it answers via respondToNui directly.)
 *
 * If a new request for the same action arrives while one is still pending,
 * the old one is answered with an error immediately -- otherwise the earlier
 * Lua caller would sit waiting for its full timeout on a request whose UI was
 * silently replaced.
 *
 * `onOpen` (optional) runs once per incoming request, for components that
 * need to seed their own local state from the payload (e.g. InputDialog's
 * editable `values`) -- it is NOT a dependency of the returned callbacks, so
 * an inline arrow is fine to pass here.
 *
 * If the component unmounts with a request still unanswered (a render crash:
 * the ErrorBoundary renders nothing), the request is answered with
 * `unmountResult` (the surface's own cancel shape), or an error when none is
 * given, so Lua releases NUI focus instead of an invisible surface keeping
 * the cursor.
 */
export function useNuiRequest<TPayload, TResult = unknown>(
    action: string,
    onOpen?: (payload: TPayload) => void,
    unmountResult?: TResult
) {
    const [request, setRequest] = useState<PendingRequest<TPayload> | null>(null)
    const respondedRef = useRef(false)
    const pendingRef = useRef<PendingRequest<TPayload> | null>(null)
    const onOpenRef = useRef(onOpen)
    onOpenRef.current = onOpen
    const unmountResultRef = useRef(unmountResult)
    unmountResultRef.current = unmountResult

    useEffect(() => () => {
        const pending = pendingRef.current
        if (respondedRef.current || !pending) return
        respondedRef.current = true
        pendingRef.current = null
        const result = unmountResultRef.current
        if (result === undefined) respondToNui(pending.requestId, pending.token, false, "The NUI surface closed unexpectedly.")
        else respondToNui<TResult>(pending.requestId, pending.token, true, result)
    }, [])

    const handleOpen = useCallback((msg: NuiRequestEnvelope<TPayload>) => {
        const previous = pendingRef.current
        if (previous && !respondedRef.current) {
            respondToNui(previous.requestId, previous.token, false, "Superseded by a newer request.")
        }

        const next = { requestId: msg.requestId, token: msg.token, payload: msg.payload }
        pendingRef.current = next
        respondedRef.current = false
        setRequest(next)
        onOpenRef.current?.(msg.payload)
    }, [])

    useNuiEvent<NuiRequestEnvelope<TPayload>>(action, handleOpen)

    const handleCancellation = useCallback((message: CancelledRequest) => {
        const pending = pendingRef.current
        if (!pending || pending.requestId !== message.requestId || pending.token !== message.token) return

        respondedRef.current = true
        pendingRef.current = null
        setRequest(null)
    }, [])

    useNuiEvent<CancelledRequest>("cancelNuiRequest", handleCancellation)

    const settle = useCallback(
        (ok: boolean, resultOrError: TResult | string) => {
            const pending = pendingRef.current
            if (respondedRef.current || !pending) return
            respondedRef.current = true
            pendingRef.current = null
            respondToNui<TResult>(pending.requestId, pending.token, ok, resultOrError)
            setRequest(null)
        },
        []
    )

    const respond = useCallback((result: TResult) => settle(true, result), [settle])
    const respondError = useCallback((message: string) => settle(false, message), [settle])

    return {
        payload: request?.payload ?? null,
        requestId: request?.requestId ?? null,
        token: request?.token ?? null,
        isOpen: request !== null,
        respond,
        respondError,
    }
}
