import { act, render, screen, within } from "@testing-library/react"
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import { TextUi } from "@/components/textui/TextUi"
import { fetchNui } from "@/lib/fetchNui"
import { DispatchFeed } from "./DispatchFeed"
import type { DispatchFeedCall, DispatchFeedPayload } from "@/lib/types"
vi.mock("@/lib/fetchNui", () => ({ fetchNui: vi.fn().mockResolvedValue(true) }))
const keys = { previous: "PRIOR", next: "NEXT", respond: "HOME", toggle: "END", tablet: "F9" }
function call(id: number, extra: Partial<DispatchFeedCall> = {}): DispatchFeedCall {
    return { id, code: `10-${id}`, title: `Incident ${id}`, priority: 2, icon: "car", createdAt: 0, expiresAt: 300000, units: [], ...extra }
}
function payload(extra: Partial<DispatchFeedPayload> = {}): DispatchFeedPayload {
    return { now: 38000, calls: [call(1)], hidden: false, me: { src: 7 }, keybinds: keys,
        config: { feed: { position: "left-center", maxVisible: 4 }, priorities: { "2": { label: "High", color: "#F59E0B" } } }, ...extra }
}
function send(data: unknown, action = "kora_dispatch:feed") { act(() => window.dispatchEvent(new MessageEvent("message", { data: { action, data } }))) }
function card(title = "Incident 1") { return screen.getByRole("article", { name: title }) }
let elapsed = 0
beforeEach(() => { vi.useFakeTimers(); elapsed = 0; vi.spyOn(performance, "now").mockImplementation(() => elapsed); vi.mocked(fetchNui).mockClear().mockResolvedValue(true) })
afterEach(() => { vi.restoreAllMocks(); vi.useRealTimers(); document.documentElement.style.removeProperty("--primary"); document.documentElement.style.removeProperty("--background") })
function tick(ms: number) { act(() => { elapsed += ms; vi.advanceTimersByTime(ms) }) }

describe("shared dispatch feed", () => {
    it("stays headless until a payload and requests cached replay without focus", () => {
        const view = render(<DispatchFeed />)
        expect(view.container).toBeEmptyDOMElement()
        expect(fetchNui).toHaveBeenCalledTimes(1)
        expect(fetchNui).toHaveBeenCalledWith("kora_lib:dispatchfeed:ready")
        send(payload()); expect(card()).toBeVisible()
        expect(view.container.querySelectorAll("button,input,select,textarea,[tabindex]")).toHaveLength(0)
        expect(screen.getByRole("region", { name: "Dispatch calls" })).toHaveClass("pointer-events-none")
        send(false); expect(view.container).toBeEmptyDOMElement(); expect(vi.getTimerCount()).toBe(0)
    })
    it("renders complete compact fields, priority edge and assigned response", () => {
        render(<DispatchFeed />)
        send(payload({ selected: 1, calls: [call(1, { data: { street: "Vespucci Boulevard" }, units: [{ src: 7, state: "en_route" }, { src: 8, state: "on_scene" }] })] }))
        const current = card()
        for (const text of ["10-1", "Incident 1", "High", "38s", "Vespucci Boulevard", "2", "You are en route", "Selected"]) expect(within(current).getByText(text)).toBeVisible()
        expect(current.querySelector(".w-1")).toHaveStyle({ background: "#F59E0B" })
        expect(current).toHaveStyle({ background: "hsl(var(--card))", borderColor: "hsl(var(--brand-border))" }); expect(current).not.toHaveClass("bg-brand-soft")
        for (const text of ["PRIOR", "NEXT", "HOME", "F9", "Browse", "On scene", "Map"]) expect(screen.getByText(text)).toBeVisible()
        expect(current.querySelector("svg.lucide-car")).not.toBeNull()
    })
    it.each([
        ["en_route", "You are en route", "On scene"], ["on_scene", "You are on scene", "Clear"], ["clear", "You have cleared", "Accept"],
    ] as const)("preserves %s own-response hint", (state, line, hint) => {
        render(<DispatchFeed />); send(payload({ selected: 1, calls: [call(1, { units: [{ src: 7, state }] })] }))
        expect(screen.getByText(line)).toBeVisible(); expect(screen.getByText(hint, { exact: true })).toBeVisible()
    })
    it("normalizes Lua empty units/calls objects and clears nil or malformed envelopes", () => {
        const view = render(<DispatchFeed />)
        send(payload({ selected: 1, calls: [call(1, { units: {} as DispatchFeedCall["units"] })] }))
        expect(card()).toBeVisible(); expect(screen.getByText("Accept")).toBeVisible()
        expect(screen.queryByText("You are en route")).not.toBeInTheDocument()
        send(payload({ calls: {} as DispatchFeedCall[] })); expect(view.container).toBeEmptyDOMElement()
        send(payload()); send(null); expect(view.container).toBeEmptyDOMElement()
        send(payload()); send({ now: "38000" }); expect(view.container).toBeEmptyDOMElement()
    })
    it("preserves dense priority arrays and unknown priority fallback", () => {
        render(<DispatchFeed />)
        send(payload({ config: { priorities: [{ label: "Critical", color: "#F04444" }, { label: "High array", color: "#F59E0B" }] } }))
        expect(screen.getByText("High array")).toBeVisible()
        send(payload({ calls: [call(1, { priority: 9 })] })); expect(screen.getByText("P9")).toBeVisible()
    })
    it("keeps configured live window, prepends selected ended history and avoids duplication", () => {
        render(<DispatchFeed />)
        const calls = [call(5), call(4), call(3), call(2, { closedAt: 1 }), call(1, { expiresAt: 10 })]
        send(payload({ calls, selected: 1, config: { feed: { maxVisible: 2 } } }))
        expect(screen.getAllByRole("article").map((node) => node.getAttribute("aria-label"))).toEqual(["Incident 1", "Incident 5", "Incident 4"])
        expect(card()).toHaveClass("opacity-60"); expect(screen.queryByRole("article", { name: "Incident 2" })).not.toBeInTheDocument()
        send(payload({ calls, selected: 5, config: { feed: { maxVisible: 2 } } })); expect(screen.getAllByRole("article")).toHaveLength(2)
    })
    it("preserves default, zero and negative slice cap semantics", () => {
        render(<DispatchFeed />); const calls = [call(5), call(4), call(3), call(2), call(1)]
        send(payload({ calls, config: {} })); expect(screen.getAllByRole("article")).toHaveLength(4)
        send(payload({ calls, config: { feed: { maxVisible: 0 } } })); expect(screen.queryAllByRole("article")).toHaveLength(0)
        send(payload({ calls, selected: 1, config: { feed: { maxVisible: 0 } } })); expect(screen.getAllByRole("article")).toHaveLength(1)
        send(payload({ calls, config: { feed: { maxVisible: -1 } } })); expect(screen.getAllByRole("article")).toHaveLength(4)
    })
    it.each([
        ["left-center", ["left-4", "top-1/2", "-translate-y-1/2"]], ["top-left", ["left-4", "top-4"]],
        ["top-center", ["left-1/2", "top-4", "-translate-x-1/2"]], ["unknown", ["left-4", "top-1/2"]], ["constructor", ["left-4", "top-1/2"]],
    ])("preserves %s placement/fallback", (position, classes) => {
        render(<DispatchFeed />); send(payload({ config: { feed: { position: position as string } } }))
        expect(screen.getByRole("region", { name: "Dispatch calls" })).toHaveClass(...classes)
    })
    it("shows mute restore key even with no calls and stops visible clock work", () => {
        render(<DispatchFeed />); send(payload()); expect(vi.getTimerCount()).toBe(1)
        send(payload({ hidden: true, calls: [] })); expect(screen.getByLabelText("Dispatch muted")).toBeVisible(); expect(screen.getByText("END")).toBeVisible()
        expect(screen.queryAllByRole("article")).toHaveLength(0); expect(vi.getTimerCount()).toBe(0)
        send(payload()); expect(card()).toBeVisible(); expect(vi.getTimerCount()).toBe(1)
    })
    it("scopes only service brand tokens, leaving global palette and prompts untouched", () => {
        document.documentElement.style.setProperty("--primary", "global-brand"); document.documentElement.style.setProperty("--background", "configured-neutral")
        render(<><TextUi /><DispatchFeed /></>)
        send({ id: 99, text: "Fuel vehicle", position: "right-center", key: "E" }, "textui:set")
        send(payload({ theme: { primary: "local-brand", "brand-soft": "local-soft", "brand-border": "local-border", background: "wrong-palette" } }))
        const feed = screen.getByRole("region", { name: "Dispatch calls" })
        expect(feed.style.getPropertyValue("--primary")).toBe("local-brand"); expect(feed.style.getPropertyValue("--brand-soft")).toBe("local-soft")
        expect(feed.style.getPropertyValue("--brand-border")).toBe("local-border"); expect(feed.style.getPropertyValue("--background")).toBe("")
        expect(document.documentElement.style.getPropertyValue("--primary")).toBe("global-brand"); expect(document.documentElement.style.getPropertyValue("--background")).toBe("configured-neutral")
        expect(screen.getByText("Fuel vehicle")).toBeVisible(); send(false); expect(screen.getByText("Fuel vehicle")).toBeVisible()
    })
    it("preserves all original icons and uses safe fallback for unknown/prototype property names", () => {
        render(<DispatchFeed />)
        for (const icon of ["car", "crosshair", "home", "package", "radio", "truck", "wrench", "banknote", "fire", "heart-pulse", "person", "siren", "stethoscope"]) {
            send(payload({ calls: [call(1, { icon })] })); expect(card().querySelectorAll("svg")).toHaveLength(1)
        }
        for (const icon of ["unknown", "constructor", "toString", "__proto__"]) { send(payload({ calls: [call(1, { icon })] })); expect(card().querySelector("svg.lucide-triangle-alert")).not.toBeNull() }
    })
    it("advances elapsed/expiry from pushed server time without new Lua events, rolls capped window, and stops when empty", () => {
        render(<DispatchFeed />)
        send(payload({ now: 59500, calls: [call(2, { expiresAt: 60000 }), call(1, { expiresAt: 61000 })], config: { feed: { maxVisible: 1 } } }))
        expect(screen.getByText("59s")).toBeVisible(); expect(card("Incident 2")).toBeVisible()
        tick(500); expect(screen.queryByRole("article", { name: "Incident 2" })).not.toBeInTheDocument(); expect(card()).toBeVisible(); expect(screen.getByText("1m 00s")).toBeVisible()
        tick(1000); expect(screen.queryAllByRole("article")).toHaveLength(0); expect(vi.getTimerCount()).toBe(0)
        send(payload({ now: 0, calls: [call(1)] })); expect(screen.getByText("0s")).toBeVisible()
    })
    it("keeps selected expired history readable while clock advances, but unmount disposes timer", () => {
        const view = render(<DispatchFeed />); send(payload({ now: 300000, selected: 1, calls: [call(1)] }))
        expect(card()).toHaveClass("opacity-60"); expect(screen.getByText("5m 00s")).toBeVisible()
        tick(1000); expect(screen.getByText("5m 01s")).toBeVisible(); expect(vi.getTimerCount()).toBe(1)
        view.unmount(); expect(vi.getTimerCount()).toBe(0)
    })
})
