import { act, render, screen } from "@testing-library/react"
import { expect, it, vi } from "vitest"

import { AppLocaleProvider, useAppLocale } from "@/lib/appLocale"
import { fetchNui } from "@/lib/fetchNui"

vi.mock("@/lib/fetchNui", () => ({ fetchNui: vi.fn() }))

function LocaleProbe() {
    const labels = useAppLocale()
    return <span>{labels.cancel ?? "Cancel"}|{labels.confirm ?? "Confirm"}</span>
}

it("uses pushed labels and ignores an older callback response", async () => {
    let respond!: (labels: unknown) => void
    vi.mocked(fetchNui).mockReturnValue(new Promise((resolve) => { respond = resolve }))
    render(<AppLocaleProvider><LocaleProbe /></AppLocaleProvider>)
    expect(fetchNui).toHaveBeenCalledWith("kora_lib:nui:locales")

    act(() => window.dispatchEvent(new MessageEvent("message", {
        data: { action: "kora_lib:nui:locales", data: { cancel: "Annuler", confirm: " " } },
    })))
    expect(screen.getByText("Annuler|Confirm")).toBeInTheDocument()

    await act(async () => respond({ cancel: "Stale" }))
    expect(screen.getByText("Annuler|Confirm")).toBeInTheDocument()
})
