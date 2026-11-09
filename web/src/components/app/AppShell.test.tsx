import { act, fireEvent, render, screen, within } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"

import { AppShell } from "@/components/app/AppShell"
import { InputDialogContainer } from "@/components/input/InputDialog"
import type { AppDefinition, NuiWireMessage } from "@/lib/types"
import { fetchNui, respondToNui } from "@/lib/fetchNui"

vi.mock("@/lib/fetchNui", () => ({
    fetchNui: vi.fn(),
    respondToNui: vi.fn(() => Promise.resolve()),
    isBrowserEnv: false,
}))

const fetchNuiMock = vi.mocked(fetchNui)
const respondToNuiMock = vi.mocked(respondToNui)
let requestId = 0

function dispatch<T>(action: string, data: T) {
    act(() => window.dispatchEvent(new MessageEvent<NuiWireMessage<T>>("message", { data: { action, data } })))
}

function openApp(app: AppDefinition, viewId?: string, tabId?: string) {
    requestId += 1
    dispatch("openApp", { requestId, token: `token-${requestId}`, payload: { app, viewId, tabId } })
    return `token-${requestId}`
}

function baseApp(content: AppDefinition["navigation"][number]["content"], extras: Partial<AppDefinition> = {}): AppDefinition {
    return { id: "test:app", title: "Test App", navigation: [{ id: "home", label: "Home", content }], ...extras }
}

beforeEach(() => {
    fetchNuiMock.mockReset()
    fetchNuiMock.mockResolvedValue({ ok: true })
    respondToNuiMock.mockReset()
    respondToNuiMock.mockResolvedValue(undefined)
})

describe("shared fields", () => {
    it("keeps optional number fields blank and omits them on submit", async () => {
        const user = userEvent.setup()
        render(<InputDialogContainer />)
        dispatch("openInputDialog", { requestId: 28, token: "optional-token", payload: { fields: [
            { id: "report_id", label: "Initial report # (optional)", type: "number", min: 1 },
        ] } })

        expect(screen.getByLabelText("Initial report # (optional)")).toHaveValue("")
        await user.click(screen.getByRole("button", { name: "Confirm" }))
        expect(respondToNuiMock).toHaveBeenCalledWith(28, "optional-token", true, { values: {} })
    })

    it("requires an explicit number and lets Enter submit a valid value", async () => {
        const user = userEvent.setup()
        render(<InputDialogContainer />)
        dispatch("openInputDialog", { requestId: 27, token: "required-token", payload: { fields: [
            { id: "amount", label: "Amount", type: "number", required: true, min: 1 },
        ] } })

        expect(screen.getByRole("button", { name: "Confirm" })).toBeDisabled()
        await user.type(screen.getByLabelText(/^Amount/), "7{enter}")
        expect(respondToNuiMock).toHaveBeenCalledWith(27, "required-token", true, { values: { amount: 7 } })
    })

    it("keeps decimal number drafts intact while they are being typed", async () => {
        const user = userEvent.setup()
        render(<InputDialogContainer />)
        dispatch("openInputDialog", { requestId: 29, token: "decimal-token", payload: { title: "Door settings", fields: [
            { id: "tolerance", label: "Lockpick tolerance", type: "number", min: 0.03, max: 0.35, default: 0.14 },
        ] } })

        const tolerance = screen.getByLabelText("Lockpick tolerance")
        await user.clear(tolerance)
        await user.type(tolerance, "0.14")
        expect(tolerance).toHaveValue("0.14")
        expect(screen.getByRole("button", { name: "Confirm" })).toBeEnabled()
    })

    it("applies the same validation, conditional fields, and multiselect behavior in dialogs", async () => {
        const user = userEvent.setup()
        render(<InputDialogContainer />)
        dispatch("openInputDialog", { requestId: 30, token: "dialog-token", payload: { title: "Profile", fields: [
            { id: "name", label: "Name", type: "text", required: true, minLength: 3 },
            { id: "kind", label: "Team entry", type: "checkbox" },
            { id: "roles", label: "Roles", type: "multiselect", required: true, options: [{ value: "medic", label: "Medic" }, { value: "pilot", label: "Pilot" }], visibleWhen: { fieldId: "kind", equals: true } },
        ] } })

        expect(screen.getByText("Required.")).toBeInTheDocument()
        expect(screen.queryByText("Roles")).not.toBeInTheDocument()
        await user.type(screen.getByLabelText(/Name/), "Al")
        expect(screen.getByText("Must be at least 3 characters.")).toBeInTheDocument()
        await user.click(screen.getByLabelText("Team entry"))
        expect(screen.getByText("Roles")).toBeInTheDocument()
        await user.click(screen.getByText("Medic"))
        expect(screen.getByRole("button", { name: "Confirm" })).toBeDisabled()
        await user.type(screen.getByLabelText(/Name/), "ex")
        expect(screen.getByRole("button", { name: "Confirm" })).toBeEnabled()
    })
})

describe("AppShell", () => {
    it.each(["replace", "close", "cancel"])("ignores a successful action after %s while the next app is busy", async (retire) => {
        const user = userEvent.setup()
        const pending: ((response: unknown) => void)[] = []
        fetchNuiMock.mockImplementation(() => new Promise((resolve) => pending.push(resolve)))
        render(<AppShell />)
        const old = baseApp({ actions: [{ id: "old", label: "Old action" }] })
        const token = openApp(old)
        await user.click(screen.getByRole("button", { name: "Old action" }))
        if (retire === "close") await user.click(screen.getByRole("button", { name: "Close Test App" }))
        if (retire === "cancel") dispatch("cancelNuiRequest", { requestId, token })
        const next = baseApp({ actions: [{ id: "next", label: "Next action" }] }, { id: "next:app", title: "Next App" })
        const nextToken = openApp(next)
        await user.click(screen.getByRole("button", { name: "Next action" }))
        const settled = respondToNuiMock.mock.calls.length
        await act(async () => pending[0]({ ok: true, result: { app: { ...old, title: "Retired result" }, navigate: { viewId: "home" }, notice: { tone: "success", message: "Retired notice" }, close: true } }))
        expect(screen.getByRole("main")).toHaveAccessibleName("Next App")
        expect(screen.queryByText("Retired notice")).not.toBeInTheDocument()
        expect(screen.getByRole("button", { name: "Working…" })).toBeDisabled()
        expect(respondToNuiMock).toHaveBeenCalledTimes(settled)
        expect(fetchNuiMock).toHaveBeenLastCalledWith("kora_lib:app:action", expect.objectContaining({ appId: "next:app", token: nextToken }))
        await act(async () => pending[1]({ ok: true, result: { notice: { tone: "success", message: "Current result" } } }))
        expect(screen.getByRole("status")).toHaveTextContent("Current result")
        expect(screen.getByRole("button", { name: "Next action" })).toBeEnabled()
    })

    it("ignores a rejected action from the replaced app", async () => {
        const user = userEvent.setup()
        let reject!: (error: Error) => void
        fetchNuiMock.mockImplementationOnce(() => new Promise((_, fail) => { reject = fail }))
        render(<AppShell />)
        openApp(baseApp({ actions: [{ id: "old", label: "Old action" }] }))
        await user.click(screen.getByRole("button", { name: "Old action" }))
        openApp(baseApp({ title: "Current content" }, { title: "Next App" }))
        await act(async () => reject(new Error("Retired failure")))
        expect(screen.getByRole("main")).toHaveAccessibleName("Next App")
        expect(screen.queryByRole("alert")).not.toBeInTheDocument()
    })

    it("updates a price from range edits without submitting or resetting drafts", async () => {
        const makeApp = (price: string) => baseApp({ blocks: [
            { type: "stats", items: [{ label: "Total Price", value: price }] },
            { type: "form", id: "fuel", action: { id: "fill", label: "Fill up", closeBeforeAction: true }, fields: [
                { id: "quantity", label: "Amount", type: "range", min: 1, max: 50, default: 50 },
                { id: "account", label: "Account", type: "text", default: "bank" },
            ] },
        ] }, { onChange: true })
        fetchNuiMock.mockResolvedValue({ ok: true, result: { app: makeApp("$30") } })
        render(<AppShell />)
        const token = openApp(makeApp("$150"))
        expect(fetchNuiMock).not.toHaveBeenCalled()
        fireEvent.change(screen.getByRole("slider"), { target: { value: "10" } })
        expect(await screen.findByText("$30")).toBeInTheDocument()
        expect(screen.getByRole("slider")).toHaveValue("10")
        expect(screen.getByLabelText("Account")).toHaveValue("bank")
        expect(screen.getByRole("button", { name: "Fill up" })).toBeEnabled()
        expect(fetchNuiMock).toHaveBeenCalledTimes(1)
        expect(fetchNuiMock).toHaveBeenCalledWith("kora_lib:app:change", {
            appId: "test:app", token, actionId: "fill", viewId: "home", tabId: undefined, itemId: undefined,
            value: { quantity: 10, account: "bank" },
        })
        expect(respondToNuiMock).not.toHaveBeenCalled()
    })

    it("reports action-form edits with their item context and keeps the form open", async () => {
        const user = userEvent.setup()
        render(<AppShell />)
        openApp(baseApp({ blocks: [{ type: "list", items: [{ id: "alpha", label: "Alpha", actions: [
            { id: "rename", label: "Rename", fields: [{ id: "name", label: "Name", type: "text" }] },
        ] }] }] }, { onChange: true }))
        await user.click(screen.getByRole("button", { name: "Rename" }))
        expect(fetchNuiMock).not.toHaveBeenCalled()
        await user.type(screen.getByLabelText("Name"), "A")
        expect(fetchNuiMock).toHaveBeenCalledWith("kora_lib:app:change", expect.objectContaining({ actionId: "rename", itemId: "alpha", value: { name: "A" } }))
        expect(screen.getByLabelText("Name")).toHaveValue("A")
    })

    it("ignores older change responses and changes from a superseded session", async () => {
        const pending: ((response: unknown) => void)[] = []
        fetchNuiMock.mockImplementation(() => new Promise((resolve) => pending.push(resolve)))
        const app = baseApp({ blocks: [{ type: "form", id: "fuel", action: { id: "fill", label: "Fill" }, fields: [
            { id: "quantity", label: "Amount", type: "range", min: 1, max: 50, default: 50 },
        ] }] }, { onChange: true })
        render(<AppShell />)
        openApp(app)
        fireEvent.change(screen.getByRole("slider"), { target: { value: "10" } })
        fireEvent.change(screen.getByRole("slider"), { target: { value: "20" } })
        await act(async () => pending[1]({ ok: true, result: { app: { ...app, footer: "Latest price" } } }))
        await act(async () => pending[0]({ ok: true, result: { app: { ...app, footer: "Old price" } } }))
        expect(screen.getByText("Latest price")).toBeInTheDocument()
        expect(screen.queryByText("Old price")).not.toBeInTheDocument()
        fireEvent.change(screen.getByRole("slider"), { target: { value: "30" } })
        openApp({ ...app, title: "Reopened" })
        await act(async () => pending[2]({ ok: true, result: { app: { ...app, footer: "Closed price" } } }))
        expect(screen.getByRole("main")).toHaveAccessibleName("Reopened")
        expect(screen.queryByText("Closed price")).not.toBeInTheDocument()
    })

    it("omits an optional blank number from an action payload", async () => {
        const user = userEvent.setup()
        render(<AppShell />)
        openApp(baseApp({ actions: [{ id: "create", label: "Create", fields: [
            { id: "report_id", label: "Initial report # (optional)", type: "number", min: 1 },
        ] }] }))

        await user.click(screen.getByRole("button", { name: "Create" }))
        await user.click(screen.getByRole("button", { name: "Run action" }))
        expect(fetchNuiMock).toHaveBeenCalledWith("kora_lib:app:action", expect.objectContaining({ value: {} }))
    })

    it("uses an action's submitLabel for its in-shell form button", async () => {
        const user = userEvent.setup()
        render(<AppShell />)
        openApp(baseApp({ actions: [
            { id: "sell", label: "Sell materials", submitLabel: "Sell", fields: [{ id: "amount", label: "Amount", type: "number", min: 1 }] },
            { id: "scrap", label: "Scrap", confirm: "Scrap it?", submitLabel: "Scrap now" },
        ] }))

        await user.click(screen.getByRole("button", { name: "Sell materials" }))
        expect(screen.getByRole("button", { name: "Sell" })).toHaveAttribute("type", "submit")
        expect(screen.queryByRole("button", { name: "Run action" })).not.toBeInTheDocument()
        await user.click(screen.getByRole("button", { name: "Cancel" }))
        await user.click(screen.getByRole("button", { name: "Scrap" }))
        expect(screen.getByRole("button", { name: "Scrap now" })).toHaveAttribute("type", "submit")
        expect(screen.queryByRole("button", { name: "Confirm" })).not.toBeInTheDocument()
    })

    it("renders a bounded progress graph with accessible values", () => {
        render(<AppShell />)
        openApp(baseApp({ blocks: [{ type: "progress", title: "Skills", items: [
            { label: "Mining", value: 25, max: 100, detail: "250 / 1,000 XP", icon: "Hammer" },
        ] }] }))
        expect(screen.getByRole("progressbar", { name: "Mining" })).toHaveAttribute("aria-valuenow", "25")
        expect(screen.getByText("250 / 1,000 XP")).toBeInTheDocument()
    })

    it("renders a header action form exactly once below the header", async () => {
        const user = userEvent.setup()
        render(<AppShell />)
        openApp(baseApp({ actions: [{ id: "create", label: "Create", fields: [{ id: "title", label: "Title", type: "text" }] }], blocks: [{ type: "actions", title: "Other", actions: [{ id: "refresh", label: "Refresh" }] }] }))
        await user.click(screen.getByRole("button", { name: "Create" }))
        expect(screen.getAllByLabelText("Title")).toHaveLength(1)
        const form = screen.getByLabelText("Title").closest("form")
        expect(form).toBeTruthy()
        expect(screen.getByText("Other").compareDocumentPosition(form!) & Node.DOCUMENT_POSITION_PRECEDING).toBeTruthy()
    })

    it("shows a toggle action's current state and exposes it to assistive technology", () => {
        render(<AppShell />)
        openApp(baseApp({ actions: [{ id: "duty", label: "Turn Admin Duty Off", state: true }] }))
        const action = screen.getByRole("button", { name: /Turn Admin Duty Off/ })
        expect(action).toHaveAttribute("aria-pressed", "true")
        expect(action).toHaveAttribute("data-state", "on")
        expect(action).toHaveTextContent("On")
    })

    it("keeps controlling values while atomically resetting dependent choices", async () => {
        const user = userEvent.setup()
        render(<AppShell />)
        openApp(baseApp({ blocks: [{
            type: "form", id: "assignment", action: { id: "save", label: "Save" }, fields: [
                { id: "specialist", label: "Specialist team", type: "checkbox", default: false },
                { id: "role", label: "Role", type: "multiselect", default: ["patrol"], dependsOn: "specialist", optionsByValue: {
                    false: [{ value: "patrol", label: "Patrol" }],
                    true: [{ value: "swat", label: "SWAT" }],
                } },
            ],
        }] }))

        expect(screen.getByRole("checkbox", { name: "Patrol" })).toBeChecked()
        await user.click(screen.getByRole("checkbox", { name: "Specialist team" }))
        expect(screen.getByRole("checkbox", { name: "Specialist team" })).toBeChecked()
        expect(screen.queryByRole("checkbox", { name: "Patrol" })).not.toBeInTheDocument()
        expect(screen.getByRole("checkbox", { name: "SWAT" })).not.toBeChecked()
    })

    it("renders list and timeline action forms only beneath their owning item", async () => {
        const user = userEvent.setup()
        render(<AppShell />)
        openApp(baseApp({ blocks: [
            { type: "list", id: "people", items: [{ id: "alpha", label: "Alpha", actions: [{ id: "rename", label: "Rename Alpha", fields: [{ id: "name", label: "New name", type: "text" }] }] }] },
            { type: "timeline", id: "history", items: [{ id: "event-1", title: "Created", actions: [{ id: "remove", label: "Remove entry", confirm: "Remove this audit entry?", variant: "destructive" }] }] },
        ] }))

        await user.click(screen.getByRole("button", { name: "Rename Alpha" }))
        const listForm = screen.getByLabelText("New name").closest("form")!
        expect(screen.getAllByLabelText("New name")).toHaveLength(1)
        expect(listForm.closest("article")).toHaveTextContent("Alpha")
        await user.click(within(listForm).getByRole("button", { name: "Cancel" }))

        await user.click(screen.getByRole("button", { name: "Remove entry" }))
        const timelineForm = screen.getByText("Remove this audit entry?").closest("form")!
        expect(screen.getAllByText("Remove this audit entry?")).toHaveLength(1)
        expect(timelineForm.closest("li")).toHaveTextContent("Created")
    })

    it("preserves action and always-visible form drafts across live updates", async () => {
        const user = userEvent.setup()
        render(<AppShell />)
        const makeApp = (footer?: string) => baseApp({ actions: [{ id: "edit", label: "Edit", fields: [{ id: "note", label: "Note", type: "text" }] }], blocks: [{ type: "form", id: "filter", title: "Filter", fields: [{ id: "query", label: "Query", type: "text" }], action: { id: "apply", label: "Apply" } }] }, { footer })
        const token = openApp(makeApp())
        await user.click(screen.getByRole("button", { name: "Edit" }))
        await user.type(screen.getByLabelText("Note"), "keep me")
        await user.type(screen.getByLabelText("Query"), "also keep")
        dispatch("updateApp", { appId: "test:app", token, app: makeApp("Updated") })
        expect(screen.getByLabelText("Note")).toHaveValue("keep me")
        expect(screen.getByLabelText("Query")).toHaveValue("also keep")
        expect(fetchNuiMock).not.toHaveBeenCalled()
    })

    it("renders a chat block as text, sends with Enter, keeps rejected drafts and clears accepted ones", async () => {
        const user = userEvent.setup()
        render(<AppShell />)
        const chat = (messages: { id: string; author: string; text: string; mine?: boolean; unread?: boolean }[]) => baseApp({ blocks: [{ type: "chat", id: "conv", title: "Conversation", messages, composer: { action: { id: "send", label: "Send" }, placeholder: "Write a reply", maxLength: 20 } }] })
        const token = openApp(chat([{ id: "1", author: "Player", text: "<b>hi</b>" }, { id: "2", author: "Staff", text: "hello", mine: true, unread: true }]))
        expect(screen.getByText("<b>hi</b>")).toBeInTheDocument()
        expect(document.querySelector("b")).toBeNull()
        expect(screen.getByText("New")).toBeInTheDocument()
        fetchNuiMock.mockResolvedValueOnce({ ok: true, result: { notice: { tone: "destructive", message: "Slow down" } } })
        await user.type(screen.getByLabelText("Write a reply"), "first{enter}")
        expect(fetchNuiMock).toHaveBeenLastCalledWith("kora_lib:app:action", expect.objectContaining({ actionId: "send", value: { message: "first" } }))
        expect(screen.getByLabelText("Write a reply")).toHaveValue("first")
        fetchNuiMock.mockResolvedValueOnce({ ok: true, result: {} })
        await user.click(screen.getByRole("button", { name: "Send" }))
        expect(screen.getByLabelText("Write a reply")).toHaveValue("")
        await user.type(screen.getByLabelText("Write a reply"), "draft")
        dispatch("updateApp", { appId: "test:app", token, app: chat([{ id: "1", author: "Player", text: "<b>hi</b>" }, { id: "3", author: "Player", text: "new one" }]) })
        expect(screen.getByText("new one")).toBeInTheDocument()
        expect(screen.getByLabelText("Write a reply")).toHaveValue("draft")
    })

    it("draws sent, delivered and seen ticks on the viewer's own messages only", () => {
        render(<AppShell />)
        openApp(baseApp({ blocks: [{ type: "chat", id: "conv", messages: [
            { id: "1", author: "Staff", text: "a", mine: true, status: "sent" },
            { id: "2", author: "Staff", text: "b", mine: true, status: "delivered" },
            { id: "3", author: "Staff", text: "c", mine: true, status: "seen" },
            { id: "4", author: "Player", text: "d", status: "seen" },
        ] }] }))
        const status = (id: string) => document.querySelector(`[data-chat-message="${id}"] [data-chat-status]`)
        expect(status("1")).toHaveAttribute("data-chat-status", "sent")
        expect(status("2")).toHaveAttribute("data-chat-status", "delivered")
        expect(status("3")).toHaveAttribute("data-chat-status", "seen")
        expect(status("3")).toHaveClass("text-primary")
        expect(status("2")).not.toHaveClass("text-primary")
        expect(status("3")).toHaveTextContent("Seen")
        expect(status("4")).toBeNull()
    })

    it("lets a scrollable chat fill a fixed layout and follow every new message", () => {
        render(<AppShell />)
        const chat = (ids: string[]) => baseApp({ scrollable: false, blocks: [{ type: "chat", id: "conv", title: "Conversation", scrollable: true, follow: true, messages: ids.map((id) => ({ id, author: "Player", text: `message ${id}` })), composer: { action: { id: "send", label: "Send" }, placeholder: "Write a reply" } }] })
        const token = openApp(chat(["1", "2"]))
        const log = screen.getByRole("log")
        expect(log).toHaveClass("min-h-0", "flex-1", "overflow-y-auto")
        expect(log).not.toHaveClass("max-h-[420px]")
        expect(log.closest("[data-chat-block]")).toHaveClass("min-h-0", "flex-1")
        expect(screen.getByLabelText("Write a reply").closest("form")).toHaveClass("shrink-0")
        Object.defineProperty(log, "scrollHeight", { configurable: true, value: 900 })
        Object.defineProperty(log, "clientHeight", { configurable: true, value: 200 })
        log.scrollTop = 100
        fireEvent.scroll(log)
        dispatch("updateApp", { appId: "test:app", token, app: chat(["1", "2", "3"]) })
        expect(log.scrollTop).toBe(900)
        expect(screen.queryByRole("button", { name: /new message/ })).not.toBeInTheDocument()
    })

    it("shows a closed chat composer as its note", () => {
        render(<AppShell />)
        openApp(baseApp({ blocks: [{ type: "chat", id: "conv", messages: [], empty: "No messages yet", composer: { action: { id: "send", label: "Send" }, disabled: true, note: "This report is closed." } }] }))
        expect(screen.getByText("No messages yet")).toBeInTheDocument()
        expect(screen.getByText("This report is closed.")).toBeInTheDocument()
        expect(screen.queryByRole("button", { name: "Send" })).not.toBeInTheDocument()
    })

    it("applies navigation and notices returned by actions", async () => {
        const user = userEvent.setup()
        fetchNuiMock.mockResolvedValue({ ok: true, result: { navigate: { viewId: "records", tabId: "recent" }, notice: { tone: "success", message: "Moved" } } })
        render(<AppShell />)
        openApp({ id: "test:app", title: "Test App", navigation: [
            { id: "home", label: "Home", content: { actions: [{ id: "go", label: "Go" }] } },
            { id: "records", label: "Records", tabs: [{ id: "recent", label: "Recent", content: { title: "Recent records" } }] },
        ] })
        await user.click(screen.getByRole("button", { name: "Go" }))
        expect(await screen.findByText("Recent records")).toBeInTheDocument()
        expect(screen.getByRole("status")).toHaveTextContent("Moved")
        await user.click(screen.getByRole("button", { name: "Back" }))
        expect(screen.getByRole("heading", { name: "Home" })).toBeInTheDocument()
    })

    const tabbedApp = (tabs: NonNullable<AppDefinition["navigation"][number]["tabs"]>): AppDefinition => ({ id: "test:app", title: "Test App", navigation: [
        { id: "players", label: "Online player management", tabs },
        { id: "reports", label: "Reports", content: { title: "Open reports" } },
    ] })
    const playerTabs = [
        { id: "list", label: "Online Players", content: { title: "Players list", actions: [{ id: "open-player", label: "Open player" }] } },
        { id: "profile", label: "Profile", content: { title: "Player profile" } },
        { id: "tools", label: "Player Tools", content: { title: "Player tools" } },
        { id: "moderation", label: "Moderation", content: { title: "Player moderation" } },
    ]
    async function openPlayer(user: ReturnType<typeof userEvent.setup>) {
        fetchNuiMock.mockResolvedValueOnce({ ok: true, result: { navigate: { viewId: "players", tabId: "profile" } } })
        await user.click(screen.getByRole("button", { name: "Open player" }))
        expect(await screen.findByText("Player profile")).toBeInTheDocument()
    }

    it("tab bar switches are not back steps", async () => {
        const user = userEvent.setup()
        render(<AppShell />)
        openApp(tabbedApp(playerTabs))

        await user.click(screen.getByRole("tab", { name: "Profile" }))
        await user.click(screen.getByRole("tab", { name: "Player Tools" }))
        expect(screen.getByText("Player tools")).toBeInTheDocument()
        expect(screen.queryByRole("button", { name: "Back" })).not.toBeInTheDocument()
    })

    it("returns from any profile tab to the list in one press", async () => {
        const user = userEvent.setup()
        render(<AppShell />)
        openApp(tabbedApp(playerTabs))

        await openPlayer(user)
        await user.click(screen.getByRole("tab", { name: "Player Tools" }))
        await user.click(screen.getByRole("tab", { name: "Moderation" }))
        await user.click(screen.getByRole("tab", { name: "Profile" }))
        await user.click(screen.getByRole("tab", { name: "Moderation" }))
        expect(screen.getByText("Player moderation")).toBeInTheDocument()
        await user.click(screen.getByRole("button", { name: "Back" }))
        expect(screen.getByText("Players list")).toBeInTheDocument()
        expect(screen.queryByRole("button", { name: "Back" })).not.toBeInTheDocument()
    })

    it("opening players repeatedly from the list keeps one back step", async () => {
        const user = userEvent.setup()
        render(<AppShell />)
        openApp(tabbedApp(playerTabs))

        await openPlayer(user)
        await user.click(screen.getByRole("tab", { name: "Online Players" }))
        await openPlayer(user)
        await user.click(screen.getByRole("button", { name: "Back" }))
        expect(screen.getByText("Players list")).toBeInTheDocument()
        expect(screen.queryByRole("button", { name: "Back" })).not.toBeInTheDocument()
    })

    it("hides the back arrow when the recorded tab no longer exists", async () => {
        const user = userEvent.setup()
        render(<AppShell />)
        const token = openApp(tabbedApp(playerTabs))

        await openPlayer(user)
        expect(screen.getByRole("button", { name: "Back" })).toBeInTheDocument()
        dispatch("updateApp", { appId: "test:app", token, app: tabbedApp(playerTabs.slice(1)) })
        expect(screen.queryByRole("button", { name: "Back" })).not.toBeInTheDocument()
    })

    it("runs a tab's own back action from the header arrow and shows no arrow on tabs without one", async () => {
        const user = userEvent.setup()
        render(<AppShell />)
        const listOnly = tabbedApp([playerTabs[0]])
        const selected = tabbedApp([playerTabs[0], ...playerTabs.slice(1).map((tab) => ({ ...tab, back: "player:back" }))])
        openApp(listOnly)
        fetchNuiMock.mockResolvedValueOnce({ ok: true, result: { app: selected, navigate: { viewId: "players", tabId: "profile", replace: true } } })
        await user.click(screen.getByRole("button", { name: "Open player" }))
        expect(await screen.findByText("Player profile")).toBeInTheDocument()
        await user.click(screen.getByRole("tab", { name: "Moderation" }))
        await user.click(screen.getByRole("tab", { name: "Online Players" }))
        expect(screen.queryByRole("button", { name: "Back" })).not.toBeInTheDocument()
        await user.click(screen.getByRole("tab", { name: "Player Tools" }))

        fetchNuiMock.mockResolvedValueOnce({ ok: true, result: { app: listOnly, navigate: { viewId: "players", tabId: "list", replace: true } } })
        await user.click(screen.getByRole("button", { name: "Back" }))
        expect(fetchNuiMock).toHaveBeenLastCalledWith("kora_lib:app:action", expect.objectContaining({ actionId: "player:back", tabId: "tools" }))
        expect(await screen.findByText("Players list")).toBeInTheDocument()
        expect(screen.queryByRole("tab", { name: "Player Tools" })).not.toBeInTheDocument()
        expect(screen.queryByRole("button", { name: "Back" })).not.toBeInTheDocument()
    })

    it("drops the back trail when another top-level view is picked", async () => {
        const user = userEvent.setup()
        render(<AppShell />)
        openApp(tabbedApp(playerTabs))

        await openPlayer(user)
        expect(screen.getByRole("button", { name: "Back" })).toBeInTheDocument()
        await user.click(screen.getAllByRole("button", { name: "Reports" })[0])
        expect(screen.getByText("Open reports")).toBeInTheDocument()
        expect(screen.queryByRole("button", { name: "Back" })).not.toBeInTheDocument()
    })

    it.each([true, false])("sends the destination context for a lazy-load view with tabs=%s", async (withTabs) => {
        const user = userEvent.setup()
        render(<AppShell />)
        openApp({ id: "test:app", title: "Test App", navigation: [
            { id: "home", label: "Home", tabs: [{ id: "old", label: "Old tab" }] },
            { id: "resource:sample", label: "Sample", onOpen: "load-resource", content: { title: "Loading" }, defaultTab: withTabs ? "selected" : undefined,
                tabs: withTabs ? [{ id: "first", label: "First" }, { id: "selected", label: "Selected" }] : undefined },
        ] })

        await user.click(screen.getAllByRole("button", { name: "Sample" })[0])
        expect(fetchNuiMock).toHaveBeenCalledWith("kora_lib:app:action", expect.objectContaining({
            actionId: "load-resource",
            itemId: "resource:sample",
            viewId: "resource:sample",
            tabId: withTabs ? "selected" : undefined,
        }))
    })

    it("navigates against a definition returned by the same action", async () => {
        const user = userEvent.setup()
        const updated = { id: "test:app", title: "Test App", navigation: [
            { id: "home", label: "Home" },
            { id: "records", label: "Records", tabs: [{ id: "new", label: "New", content: { title: "Fresh result" } }] },
        ] } satisfies AppDefinition
        fetchNuiMock.mockResolvedValue({ ok: true, result: { app: updated, navigate: { viewId: "records", tabId: "new" } } })
        render(<AppShell />)
        openApp(baseApp({ actions: [{ id: "load", label: "Load" }] }))

        await user.click(screen.getByRole("button", { name: "Load" }))
        expect(await screen.findByText("Fresh result")).toBeInTheDocument()
    })

    it("uses compact layout without a sidebar and exposes horizontal navigation", () => {
        const { container } = render(<AppShell />)
        openApp({ id: "test:compact", title: "ATM", layout: "compact", navigation: [{ id: "cash", label: "Cash" }, { id: "accounts", label: "Accounts" }] })
        expect(container.querySelector("main")).toHaveAttribute("data-layout", "compact")
        expect(container.querySelector("aside")).not.toBeInTheDocument()
        expect(screen.getByRole("button", { name: "Accounts" })).toBeInTheDocument()
    })

    it("can place a compact app against the right edge of the screen", () => {
        const { container } = render(<AppShell />)
        openApp({ id: "test:right", title: "Roster", layout: "compact", placement: "right", navigation: [{ id: "jobs", label: "Jobs" }] })
        expect(container.querySelector("main")).toHaveAttribute("data-placement", "right")
        expect(container.querySelector("main")?.parentElement).toHaveClass("justify-end")
    })

    it("can place a compact app against the left edge of the screen", () => {
        const { container } = render(<AppShell />)
        openApp({ id: "test:left", title: "Roster", layout: "compact", placement: "left", navigation: [{ id: "jobs", label: "Jobs" }] })
        expect(container.querySelector("main")).toHaveAttribute("data-placement", "left")
        expect(container.querySelector("main")?.parentElement).toHaveClass("justify-start")
    })

    describe("draggable panels", () => {
        const rect = (left: number, top: number, width: number, height: number) => ({ left, top, right: left + width, bottom: top + height, width, height, x: left, y: top, toJSON() {} }) as DOMRect
        const pointer = (target: HTMLElement, type: string, x: number, y: number) => {
            const event = new MouseEvent(type, { bubbles: true, cancelable: true, button: 0, clientX: x, clientY: y })
            Object.defineProperty(event, "pointerId", { value: 1 })
            fireEvent(target, event)
        }
        const drag = (header: HTMLElement, from: [number, number], to: [number, number]) => {
            pointer(header, "pointerdown", ...from)
            pointer(header, "pointermove", ...to)
            pointer(header, "pointerup", ...to)
        }
        beforeEach(() => {
            window.localStorage.clear()
            vi.spyOn(HTMLElement.prototype, "getBoundingClientRect").mockImplementation(function (this: HTMLElement) {
                const style = this.style
                if (this.tagName !== "MAIN") return rect(0, 0, 0, 0)
                return rect(400 + (parseFloat(style.left) || 0), 300 + (parseFloat(style.top) || 0), 400, 300)
            })
        })
        afterEach(() => vi.restoreAllMocks())

        it("does not move apps that do not opt in", () => {
            const { container } = render(<AppShell />)
            openApp(baseApp({ title: "Home" }))
            const header = container.querySelector("section > header") as HTMLElement
            drag(header, [10, 10], [60, 60])
            expect(container.querySelector("main")?.style.left).toBe("")
            expect(header.className).not.toContain("cursor-grab")
        })

        it("moves by the header, ignores buttons, clamps to the viewport and resets on double click", () => {
            const { container } = render(<AppShell />)
            openApp(baseApp({ title: "Home" }, { draggable: true }))
            const main = container.querySelector("main") as HTMLElement
            const header = container.querySelector("section > header") as HTMLElement
            expect(header.className).toContain("cursor-grab")

            drag(header, [10, 10], [60, 40])
            expect(main.style.left).toBe("50px")
            expect(main.style.top).toBe("30px")

            drag(within(header).getByRole("button"), [10, 10], [200, 200])
            expect(main.style.left).toBe("50px")

            drag(header, [0, 0], [5000, 5000])
            expect(main.style.left).toBe(`${window.innerWidth - 800}px`)
            expect(main.style.top).toBe(`${window.innerHeight - 600}px`)

            fireEvent.doubleClick(header)
            expect(main.style.left).toBe("0px")
            expect(main.style.top).toBe("0px")
        })

        it("stays on screen without a render loop when dragged past the left edge mid-transition", () => {
            const visual = { x: 0, y: 0 }
            vi.spyOn(HTMLElement.prototype, "getBoundingClientRect").mockImplementation(function (this: HTMLElement) {
                if (this.tagName !== "MAIN") return rect(0, 0, 0, 0)
                return rect(600 + visual.x, 300 + visual.y, 400, 300)
            })
            const computed = window.getComputedStyle.bind(window)
            vi.spyOn(window, "getComputedStyle").mockImplementation((element: Element, pseudo?: string | null) => {
                const style = computed(element, pseudo)
                if ((element as HTMLElement).tagName !== "MAIN") return style
                return new Proxy(style, { get: (target, key) => {
                    if (key === "left") return `${visual.x}px`
                    if (key === "top") return `${visual.y}px`
                    const value = Reflect.get(target, key, target)
                    return typeof value === "function" ? value.bind(target) : value
                } })
            })
            const { container } = render(<AppShell />)
            openApp(baseApp({ title: "Home" }, { draggable: true }))
            const main = container.querySelector("main") as HTMLElement
            const header = container.querySelector("section > header") as HTMLElement
            const settle = () => { visual.x = parseFloat(main.style.left) || 0; visual.y = parseFloat(main.style.top) || 0 }

            pointer(header, "pointerdown", 1000, 10)
            pointer(header, "pointermove", 405, 10)
            pointer(header, "pointermove", 395, 10)
            settle()
            expect(() => pointer(header, "pointermove", 394, 10)).not.toThrow()
            pointer(header, "pointerup", 394, 10)
            settle()

            expect(main.style.left).toBe("-600px")
            expect(main.getBoundingClientRect().left).toBe(0)
            expect(container.querySelector("main")).toBe(main)
            expect(main.className).toContain("transition-none")
        })

        it("clamps a remembered off-screen position on open and re-clamps when the window shrinks", () => {
            window.localStorage.setItem("kora_lib:app-position:shop", JSON.stringify({ x: -5000, y: 9000 }))
            const { container } = render(<AppShell />)
            openApp(baseApp({ title: "Home" }, { draggable: true, rememberPosition: true, positionKey: "shop" }))
            const main = container.querySelector("main") as HTMLElement
            expect(main.style.left).toBe("-400px")
            expect(main.style.top).toBe(`${window.innerHeight - 600}px`)

            const width = window.innerWidth
            try {
                drag(container.querySelector("section > header") as HTMLElement, [0, 0], [5000, 0])
                expect(main.style.left).toBe(`${width - 800}px`)
                Object.defineProperty(window, "innerWidth", { configurable: true, value: width - 200 })
                act(() => { window.dispatchEvent(new Event("resize")) })
                expect(main.style.left).toBe(`${width - 1000}px`)
            } finally {
                Object.defineProperty(window, "innerWidth", { configurable: true, value: width })
            }
        })

        it("clamps and follows the pointer in root px when the NUI root is scaled (above 1080p)", () => {
            const scale = 2
            const rootWidth = window.innerWidth / scale
            const rootHeight = window.innerHeight / scale
            const box = { left: (rootWidth - 300) / 2, top: (rootHeight - 200) / 2 }
            const isHost = (element: HTMLElement) => element.firstElementChild?.tagName === "MAIN"
            vi.spyOn(HTMLElement.prototype, "offsetWidth", "get").mockImplementation(function (this: HTMLElement) {
                return this.tagName === "MAIN" ? 300 : isHost(this) ? rootWidth : 0
            })
            vi.spyOn(HTMLElement.prototype, "offsetHeight", "get").mockImplementation(function (this: HTMLElement) {
                return this.tagName === "MAIN" ? 200 : isHost(this) ? rootHeight : 0
            })
            vi.spyOn(HTMLElement.prototype, "getBoundingClientRect").mockImplementation(function (this: HTMLElement) {
                if (isHost(this)) return rect(0, 0, window.innerWidth, window.innerHeight)
                if (this.tagName !== "MAIN") return rect(0, 0, 0, 0)
                return rect(scale * (box.left + (parseFloat(this.style.left) || 0)), scale * (box.top + (parseFloat(this.style.top) || 0)), scale * 300, scale * 200)
            })
            const { container } = render(<AppShell />)
            openApp(baseApp({ title: "Home" }, { draggable: true }))
            const main = container.querySelector("main") as HTMLElement
            const header = container.querySelector("section > header") as HTMLElement

            drag(header, [100, 100], [140, 120])
            expect(main.style.left).toBe("20px")
            expect(main.style.top).toBe("10px")

            drag(header, [0, 0], [5000, 5000])
            expect(main.style.left).toBe(`${box.left}px`)
            expect(main.style.top).toBe(`${box.top}px`)

            drag(header, [5000, 5000], [-5000, -5000])
            expect(main.style.left).toBe(`${-box.left}px`)
            expect(main.style.top).toBe(`${-box.top}px`)
        })

        it("remembers the position under positionKey only when rememberPosition is set", () => {
            const { container, unmount } = render(<AppShell />)
            openApp(baseApp({ title: "Home" }, { draggable: true, rememberPosition: true, positionKey: "shop" }))
            drag(container.querySelector("section > header") as HTMLElement, [0, 0], [20, 10])
            expect(JSON.parse(window.localStorage.getItem("kora_lib:app-position:shop") ?? "null")).toEqual({ x: 20, y: 10 })
            unmount()

            const again = render(<AppShell />)
            openApp(baseApp({ title: "Home" }, { draggable: true, rememberPosition: true, positionKey: "shop" }))
            expect((again.container.querySelector("main") as HTMLElement).style.left).toBe("20px")
            again.unmount()

            window.localStorage.clear()
            const plain = render(<AppShell />)
            openApp(baseApp({ title: "Home" }, { draggable: true }))
            drag(plain.container.querySelector("section > header") as HTMLElement, [0, 0], [20, 10])
            expect(window.localStorage.length).toBe(0)
        })
    })

    describe("hold actions", () => {
        const holdApp = () => baseApp({ blocks: [{ type: "list", id: "rows", items: [{ id: "horn-row", label: "Horn", actions: [{ id: "horn:test", label: "Test horn", hold: true }] }] }] })
        const press = (target: HTMLElement, type: string) => {
            const event = new MouseEvent(type, { bubbles: true, cancelable: true, button: 0 })
            Object.defineProperty(event, "pointerId", { value: 1 })
            fireEvent(target, event)
        }
        const holdCalls = () => fetchNuiMock.mock.calls.filter(([name]) => name === "kora_lib:app:hold").map(([, data]) => data as Record<string, unknown>)

        it("sends start on press and one end on release, never a click", () => {
            render(<AppShell />)
            const token = openApp(holdApp())
            const button = screen.getByRole("button", { name: "Test horn" })

            press(button, "pointerdown")
            press(button, "pointerdown")
            expect(button).toHaveAttribute("aria-pressed", "true")
            press(button, "pointerup")
            press(button, "pointerup")
            fireEvent.click(button)

            expect(holdCalls().map((call) => call.state)).toEqual(["start", "end"])
            expect(holdCalls()[0]).toMatchObject({ appId: "test:app", token, actionId: "horn:test", itemId: "horn-row" })
            expect(fetchNuiMock.mock.calls.some(([name]) => name === "kora_lib:app:action")).toBe(false)
        })

        it("supports the keyboard and releases when focus is lost or the shell goes away", () => {
            const { unmount } = render(<AppShell />)
            openApp(holdApp())
            const button = screen.getByRole("button", { name: "Test horn" })

            fireEvent.keyDown(button, { key: " " })
            fireEvent.keyDown(button, { key: " ", repeat: true })
            fireEvent.keyUp(button, { key: " " })
            fireEvent.keyDown(button, { key: "Enter" })
            fireEvent.blur(button)
            press(button, "pointerdown")
            unmount()

            expect(holdCalls().map((call) => call.state)).toEqual(["start", "end", "start", "end", "start", "end"])
        })
    })

    it("answers the open request when the shell unmounts while open, so Lua releases focus", () => {
        const { unmount } = render(<AppShell />)
        const token = openApp(baseApp({ title: "Home" }))
        unmount()
        expect(respondToNuiMock).toHaveBeenCalledWith(requestId, token, true, expect.objectContaining({ closed: true, reason: "unmounted" }))
    })

    it("keeps the game visible around the app shell", () => {
        const { container } = render(<AppShell />)
        openApp(baseApp({ title: "Home" }))
        expect(container.querySelector("main")?.parentElement).not.toHaveClass("bg-modal-overlay")
    })

    it("right-aligns multi-action list rows beside the info block, leaving card layouts unchanged", () => {
        render(<AppShell />)
        openApp(baseApp({ blocks: [
            { type: "list", id: "jobs", items: [{ id: "police", label: "Police", actions: [{ id: "active", label: "Make active" }, { id: "leave", label: "Leave job" }] }] },
            { type: "list", id: "cards", layout: "cards", items: [{ id: "tool", label: "Tool", actions: [{ id: "use", label: "Use tool" }] }] },
        ] }))
        const row = screen.getByText("Police").closest("article")!
        expect(row).toHaveClass("flex-wrap", "gap-x-3", "gap-y-2")
        expect(row.firstElementChild).toHaveClass("basis-40")
        const actions = screen.getByRole("button", { name: "Leave job" }).parentElement!
        expect(actions).toHaveClass("justify-end")
        expect(actions.parentElement).toHaveClass("ml-auto", "shrink-0", "max-w-full")
        const card = screen.getByText("Tool").closest("article")!
        const cardActions = screen.getByRole("button", { name: "Use tool" }).parentElement!
        expect(cardActions).not.toHaveClass("justify-end")
        expect(cardActions.parentElement).not.toHaveClass("ml-auto")
        expect(card.firstElementChild).not.toHaveClass("basis-40")
    })

    it("supports searchable paged tables and nested card lists", async () => {
        const user = userEvent.setup()
        render(<AppShell />)
        openApp(baseApp({ blocks: [
            { type: "table", id: "people", title: "People", searchable: true, pageSize: 1, columns: [{ key: "name", label: "Name", sortable: true }], rows: [{ name: "Ada" }, { name: "Grace" }] },
            { type: "list", id: "tools", title: "Tools", layout: "cards", searchable: true, items: [{ id: "admin", label: "Admin", children: [{ id: "weather", label: "Weather" }] }] },
        ] }))
        const people = screen.getByText("People").closest("section")!
        expect(within(people).getByText("Ada")).toBeInTheDocument()
        await user.click(within(people).getByRole("button", { name: "Next" }))
        expect(within(people).getByText("Grace")).toBeInTheDocument()
        await user.type(within(people).getByRole("textbox"), "Ada")
        expect(within(people).getByText("Ada")).toBeInTheDocument()
        await user.click(screen.getByRole("button", { name: /Admin/ }))
        expect(screen.getByText("Weather")).toBeInTheDocument()
    })

    it.each(["cards", "grid"] as const)("renders media %s with working actions, forms, paging and search", async (layout) => {
        const user = userEvent.setup()
        const { container } = render(<AppShell />)
        openApp(baseApp({ blocks: [{ type: "list", id: "events", layout, cardStyle: "media", columns: 2, searchable: true, pageSize: 1, items: [
            { id: "halloween", label: "Halloween Giveaway", image: "halloween.png", badge: "Scheduled", description: "14 prizes", data: { event: 42 }, action: "open-event", actions: [
                { id: "manage", label: "Manage event" },
                { id: "edit", label: "Edit event", fields: [{ id: "name", label: "Event name", type: "text" }] },
                { id: "publish", label: "Publish", disabled: true },
            ] },
            { id: "community", label: "Community Giveaway", icon: "Gift" },
        ] }] }))
        const card = container.querySelector('article[data-card-style="media"]')!
        expect(card.querySelector("img")?.parentElement).toHaveClass("aspect-video", "w-full")
        expect(card.parentElement?.style.gridTemplateColumns).toContain("repeat(auto-fill")
        expect(within(card as HTMLElement).getByText("Scheduled")).toBeInTheDocument()
        expect(within(card as HTMLElement).getByRole("button", { name: "Publish" })).toBeDisabled()
        const open = within(card as HTMLElement).getByRole("button", { name: /Halloween Giveaway/ })
        open.focus()
        await user.keyboard("{Enter}")
        expect(fetchNuiMock).toHaveBeenLastCalledWith("kora_lib:app:action", expect.objectContaining({ actionId: "open-event", itemId: "halloween", value: { event: 42 } }))
        await user.click(screen.getByRole("button", { name: "Manage event" }))
        expect(fetchNuiMock).toHaveBeenLastCalledWith("kora_lib:app:action", expect.objectContaining({ actionId: "manage", itemId: "halloween", value: { event: 42 } }))
        await user.click(screen.getByRole("button", { name: "Edit event" }))
        await user.type(screen.getByLabelText("Event name"), "Updated")
        await user.click(screen.getByRole("button", { name: "Run action" }))
        expect(fetchNuiMock).toHaveBeenLastCalledWith("kora_lib:app:action", expect.objectContaining({ actionId: "edit", itemId: "halloween", value: { name: "Updated" } }))
        await user.click(screen.getByRole("button", { name: "Next" }))
        expect(screen.getByText("Community Giveaway")).toBeInTheDocument()
        expect(container.querySelector('article[data-card-style="media"] svg')).toBeInTheDocument()
        await user.type(screen.getByRole("textbox"), "Halloween")
        expect(screen.getByText("Halloween Giveaway")).toBeInTheDocument()
    })

    it("keeps thumbnail cards as the default and ignores card styling in list rows", () => {
        const { container } = render(<AppShell />)
        openApp(baseApp({ blocks: [
            { type: "list", layout: "cards", items: [{ id: "compact", label: "Compact", image: "compact.png" }] },
            { type: "list", layout: "list", cardStyle: "media", columns: 4, items: [{ id: "row", label: "Row", image: "row.png" }] },
        ] }))
        expect(container.querySelector('article[data-card-style="compact"] img')?.parentElement).toHaveClass("h-14", "w-14")
        expect(container.querySelector('img[src="row.png"]')?.parentElement).toHaveClass("h-9", "w-9")
        expect(container.querySelector('img[src="compact.png"]')).toHaveStyle({ objectFit: "cover" })
        expect(container.querySelector('img[src="row.png"]')).toHaveStyle({ objectFit: "cover" })
        expect(container.querySelector('article[data-card-style="media"]')).not.toBeInTheDocument()
    })

    it.each([
        { layout: "cards", cardStyle: "media" },
        { layout: "grid", cardStyle: "compact" },
        { layout: "list", cardStyle: "compact" },
    ] as const)("inherits and overrides image fit in $layout/$cardStyle", async ({ layout, cardStyle }) => {
        const user = userEvent.setup()
        const { container } = render(<AppShell />)
        const fits = ["cover", "contain", "fill", "none", "scale-down"] as const
        openApp(baseApp({ blocks: [{ type: "list", layout, cardStyle, imageFit: "contain", items: [
            { id: "inherited", label: "Inherited", image: "inherited.png" },
            ...fits.map((imageFit) => ({ id: imageFit, label: imageFit, image: `${imageFit}.png`, imageFit })),
            { id: "parent", label: "Nested images", children: [{ id: "child", label: "Nested child", image: "child.png" }] },
        ] }] }))
        expect(container.querySelector('img[src="inherited.png"]')).toHaveStyle({ objectFit: "contain" })
        for (const objectFit of fits) {
            expect(container.querySelector(`img[src="${objectFit}.png"]`)).toHaveStyle({ objectFit })
        }
        await user.click(screen.getByRole("button", { name: /Nested images/ }))
        expect(container.querySelector('img[src="child.png"]')).toHaveStyle({ objectFit: "contain" })
    })

    it("renders wide list thumbnails only when imageAspect is wide", () => {
        const { container } = render(<AppShell />)
        openApp(baseApp({ blocks: [{ type: "list", layout: "list", imageAspect: "wide", items: [
            { id: "wide", label: "Wide", image: "wide.png", imageFit: "contain" },
            { id: "square", label: "Square", image: "square.png", imageAspect: "square" },
        ] }] }))
        expect(container.querySelector('img[src="wide.png"]')?.parentElement).toHaveClass("w-20")
        expect(container.querySelector('img[src="square.png"]')?.parentElement).toHaveClass("w-9")
    })

    it("supports fixed table widths and hover details on rich values", () => {
        const { container } = render(<AppShell />)
        openApp(baseApp({ blocks: [{
            type: "table",
            columns: [
                { key: "name", label: "Setting", width: "20%" },
                { key: "description", label: "Description", width: "80%" },
            ],
            rows: [{
                name: { label: "Speed unit", description: "Key: hud.speedUnit" },
                description: "Controls the unit displayed by the vehicle speedometer.",
            }],
        }] }))

        const table = container.querySelector("table")
        expect(table).toHaveClass("table-fixed")
        expect(table?.querySelector("col")).toHaveStyle({ width: "20%" })
        expect(screen.getByText("Speed unit").closest("[title]"))
            .toHaveAttribute("title", "Key: hud.speedUnit")
    })

    it("lets a collection own scrolling while the surrounding content stays fixed", () => {
        render(<AppShell />)
        openApp(baseApp({ scrollable: false, blocks: [
            { type: "stats", items: [{ label: "Recipes", value: 2 }] },
            { type: "list", id: "craftables", title: "Craftables", scrollable: true, items: [
                { id: "board", label: "Board" }, { id: "nails", label: "Nails" },
            ] },
        ] }))

        const list = screen.getByText("Craftables").closest("section")!
        expect(list).toHaveClass("flex", "min-h-0")
        expect(list.parentElement).toHaveClass("flex", "min-h-0")
        expect(list.parentElement?.parentElement).toHaveClass("overflow-hidden")
        expect(screen.getByText("Board").closest("article")?.parentElement).toHaveClass("overflow-y-auto")
    })

    it("reconciles nested list navigation with live updates", async () => {
        const user = userEvent.setup()
        render(<AppShell />)
        const app = (child: string) => baseApp({ blocks: [{ type: "list", id: "commands", items: [{ id: "admin", label: "Admin", children: [{ id: "weather", label: child }] }] }] })
        const token = openApp(app("Old weather"))
        await user.click(screen.getByRole("button", { name: /Admin/ }))
        expect(screen.getByText("Old weather")).toBeInTheDocument()
        dispatch("updateApp", { appId: "test:app", token, app: app("Fresh weather") })
        expect(screen.getByText("Fresh weather")).toBeInTheDocument()
        expect(screen.queryByText("Old weather")).not.toBeInTheDocument()
    })

    it("clamps list pagination after a live update removes the current page", async () => {
        const user = userEvent.setup()
        render(<AppShell />)
        const app = (items: string[]) => baseApp({ blocks: [{
            type: "list", id: "people", pageSize: 1,
            items: items.map((label) => ({ id: label.toLowerCase(), label })),
        }] })
        const token = openApp(app(["Ada", "Grace"]))

        await user.click(screen.getByRole("button", { name: "Next" }))
        expect(screen.getByText("Grace")).toBeInTheDocument()
        dispatch("updateApp", { appId: "test:app", token, app: app(["Ada"]) })
        expect(screen.getByText("Ada")).toBeInTheDocument()
        expect(screen.queryByText("Nothing here")).not.toBeInTheDocument()
    })

    it("cancels a stopped resource request without posting a second response", () => {
        render(<AppShell />)
        const token = openApp(baseApp({ title: "Owned app" }))
        expect(screen.getByRole("heading", { name: "Owned app" })).toBeInTheDocument()

        dispatch("cancelNuiRequest", { requestId, token })
        expect(screen.queryByRole("heading", { name: "Owned app" })).not.toBeInTheDocument()
        expect(respondToNuiMock).not.toHaveBeenCalled()
    })

    it("lazily renders tile maps and selectable markers", async () => {
        render(<AppShell />)
        openApp(baseApp({ blocks: [{ type: "map", id: "dispatch-map", title: "Live map", minZoom: 0, maxZoom: 1, now: 100, fadeDuration: 100, tiles: { url: "https://cfx-nui-kora_dispatch/web/build/map/{z}/{x}/{y}.jpg", grid: { x: 2, y: 2 } }, markers: [{ id: "call-1", x: 128, y: 128, label: "Robbery", action: "select-call", expiresAt: 110, fadeDuration: 20 }] }] }))
        expect(await screen.findByRole("application", { name: "Live map" })).toBeInTheDocument()
        expect(screen.getByRole("button", { name: /Robbery/ })).toHaveStyle({ opacity: "0.5" })
    })
})
