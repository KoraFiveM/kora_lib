import { act, render, screen } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { describe, expect, it } from "vitest"

import { AlertDialogContainer } from "@/components/alert/AlertDialog"
import type { NuiRequestEnvelope, NuiWireMessage, OpenAlertPayload } from "@/lib/types"

function openAlert(payload: OpenAlertPayload) {
    act(() => window.dispatchEvent(new MessageEvent<NuiWireMessage<NuiRequestEnvelope<OpenAlertPayload>>>("message", {
        data: { action: "openAlert", data: { requestId: 23, token: "alert-token", payload } },
    })))
}

describe("AlertDialogContainer", () => {
    it("separates cancel-button visibility from Escape dismissal and renders safe Markdown", async () => {
        const user = userEvent.setup()
        render(<AlertDialogContainer />)
        openAlert({
            title: "**Notice**",
            message: "Use *care* <script>bad()</script>",
            cancellable: true,
            showCancel: false,
            showClose: false,
            dismissOnBackdrop: false,
            size: "lg",
            overflow: true,
        })

        expect(screen.getByText("Notice").tagName).toBe("STRONG")
        expect(screen.getByText("care").tagName).toBe("EM")
        expect(screen.queryByRole("button", { name: "Cancel" })).not.toBeInTheDocument()
        expect(screen.queryByRole("button", { name: "Close" })).not.toBeInTheDocument()
        expect(document.querySelector("script")).toBeNull()

        await user.keyboard("{Escape}")
        expect(screen.queryByText("Notice")).not.toBeInTheDocument()
    })
})
