import { createContext, useContext, useEffect, useRef, useState, type ReactNode } from "react"

import { fetchNui } from "@/lib/fetchNui"
import { useNuiEvent } from "@/lib/useNuiEvent"

export interface OxLocaleLabels {
    cancel: string
    close: string
    confirm: string
    more: string
}

const defaults: OxLocaleLabels = {
    cancel: "Cancel",
    close: "Close",
    confirm: "Confirm",
    more: "More...",
}

const OxLocaleContext = createContext<OxLocaleLabels>(defaults)

function normalizeLocale(value: unknown): OxLocaleLabels {
    const source = value && typeof value === "object" ? value as Partial<OxLocaleLabels> : {}
    return {
        cancel: typeof source.cancel === "string" && source.cancel ? source.cancel : defaults.cancel,
        close: typeof source.close === "string" && source.close ? source.close : defaults.close,
        confirm: typeof source.confirm === "string" && source.confirm ? source.confirm : defaults.confirm,
        more: typeof source.more === "string" && source.more ? source.more : defaults.more,
    }
}

export function OxLocaleProvider({ children }: { children: ReactNode }) {
    const [labels, setLabels] = useState(defaults)
    const receivedUpdate = useRef(false)

    useNuiEvent<unknown>("oxLocale", (value) => {
        receivedUpdate.current = true
        setLabels(normalizeLocale(value))
    })

    useEffect(() => {
        void fetchNui<unknown>("qblib:oxLocale").then((value) => {
            if (!receivedUpdate.current) setLabels(normalizeLocale(value))
        }).catch((error) => {
            console.error("[qblib] failed to load the ox locale catalog:", error)
        })
    }, [])

    return <OxLocaleContext.Provider value={labels}>{children}</OxLocaleContext.Provider>
}

export function useOxLocale() {
    return useContext(OxLocaleContext)
}
