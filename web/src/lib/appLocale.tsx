import { createContext, useContext, useEffect, useRef, useState, type ReactNode } from "react"

import { fetchNui } from "@/lib/fetchNui"
import type { AppShellLabels } from "@/lib/types"
import { useNuiEvent } from "@/lib/useNuiEvent"

const AppLocaleContext = createContext<Partial<AppShellLabels>>({})

function readLabels(value: unknown): Partial<AppShellLabels> {
    if (!value || typeof value !== "object" || Array.isArray(value)) return {}
    return Object.fromEntries(Object.entries(value).filter(([, text]) => typeof text === "string" && text.trim()))
}

export function AppLocaleProvider({ children }: { children: ReactNode }) {
    const [labels, setLabels] = useState<Partial<AppShellLabels>>({})
    const receivedUpdate = useRef(false)

    useNuiEvent<unknown>("kora_lib:nui:locales", (value) => {
        receivedUpdate.current = true
        setLabels(readLabels(value))
    })

    useEffect(() => {
        let mounted = true
        void fetchNui<unknown>("kora_lib:nui:locales").then((value) => {
            if (mounted && !receivedUpdate.current) setLabels(readLabels(value))
        }).catch((error) => {
            globalThis.KoraLogger?.error("lib.nui.locale", "Could not request kora_lib NUI labels", { detail1: String(error) })
        })
        return () => { mounted = false }
    }, [])

    return <AppLocaleContext.Provider value={labels}>{children}</AppLocaleContext.Provider>
}

export function useAppLocale() {
    return useContext(AppLocaleContext)
}
