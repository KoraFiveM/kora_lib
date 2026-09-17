import { act, render, screen, within } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { beforeEach, describe, expect, it, vi } from "vitest"

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
    it("omits an optional blank number from an action payload", async () => {
        const user = userEvent.setup()
        render(<AppShell />)
        openApp(baseApp({ actions: [{ id: "create", label: "Create", fields: [
            { id: "report_id", label: "Initial report # (optional)", type: "number", min: 1 },
        ] }] }))

        await user.click(screen.getByRole("button", { name: "Create" }))
        await user.click(screen.getByRole("button", { name: "Run action" }))
        expect(fetchNuiMock).toHaveBeenCalledWith("qblib:app:action", expect.objectContaining({ value: {} }))
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

    it("runs a view's lazy-load action when sidebar navigation opens it", async () => {
        const user = userEvent.setup()
        render(<AppShell />)
        openApp({ id: "test:app", title: "Test App", navigation: [
            { id: "home", label: "Home" },
            { id: "resource:sample", label: "Sample", onOpen: "load-resource", content: { title: "Loading" } },
        ] })

        await user.click(screen.getAllByRole("button", { name: "Sample" })[0])
        expect(fetchNuiMock).toHaveBeenCalledWith("qblib:app:action", expect.objectContaining({
            actionId: "load-resource",
            itemId: "resource:sample",
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

    it("keeps the game visible around the app shell", () => {
        const { container } = render(<AppShell />)
        openApp(baseApp({ title: "Home" }))
        expect(container.querySelector("main")?.parentElement).not.toHaveClass("bg-modal-overlay")
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
        openApp(baseApp({ blocks: [{ type: "map", id: "dispatch-map", title: "Live map", minZoom: 0, maxZoom: 1, now: 100, fadeDuration: 100, tiles: { url: "https://cfx-nui-qbdispatch/web/build/map/{z}/{x}/{y}.jpg", grid: { x: 2, y: 2 } }, markers: [{ id: "call-1", x: 128, y: 128, label: "Robbery", action: "select-call", expiresAt: 110, fadeDuration: 20 }] }] }))
        expect(await screen.findByRole("application", { name: "Live map" })).toBeInTheDocument()
        expect(screen.getByRole("button", { name: /Robbery/ })).toHaveStyle({ opacity: "0.5" })
    })
})
