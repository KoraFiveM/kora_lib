import { act, render, screen } from "@testing-library/react"
import { describe, expect, it } from "vitest"

import { OxLocaleProvider, useOxLocale } from "@/lib/oxLocale"
import type { NuiWireMessage } from "@/lib/types"

function LocaleProbe() {
    const locale = useOxLocale()
    return <span>{locale.cancel}|{locale.confirm}|{locale.more}</span>
}

describe("OxLocaleProvider", () => {
    it("applies live ox_lib locale catalogs and falls back per missing key", () => {
        render(<OxLocaleProvider><LocaleProbe /></OxLocaleProvider>)

        act(() => window.dispatchEvent(new MessageEvent<NuiWireMessage>("message", {
            data: {
                action: "oxLocale",
                data: { cancel: "Abbrechen", confirm: "Bestaetigen" },
            },
        })))

        expect(screen.getByText("Abbrechen|Bestaetigen|More...")).toBeInTheDocument()
    })
})
