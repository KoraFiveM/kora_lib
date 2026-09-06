import { isBrowserEnv } from "@/lib/fetchNui"
import type {
    AppDefinition,
    MenuItem,
    NotifyPayload,
    NotifyPosition,
    NuiWireMessage,
    OpenContextMenuPayload,
    OpenAlertPayload,
    OpenInputDialogPayload,
    OpenMenuPayload,
    OpenRadialMenuPayload,
    PlacementConfirmPayload,
    PlacementHudSnapshot,
    PlacementStartPayload,
    ProgressStartPayload,
    ZoneCreatorConfirmPayload,
    ZoneCreatorHudSnapshot,
    ZoneCreatorStartPayload,
    InteractOpenPayload,
} from "@/lib/types"
import { Button } from "@/components/ui/button"

// Dev-only: fires the exact `window` message shape Lua's SendNUIMessage
// produces (NuiWireMessage, see lib/types.ts), so every component can be
// exercised by running `pnpm dev` in a plain browser instead of needing a
// running game. The import.meta.env.DEV gate below means Vite dead-code-
// eliminates this whole component (and its sample payloads) from the
// production bundle; isBrowserEnv additionally keeps it hidden if a dev
// build ever ends up inside the real CEF frame.
//
// Every payload here is TYPED against lib/types.ts -- if the contract
// changes, these samples fail the type-check instead of silently testing a
// stale shape.
function post<T>(action: string, data: T) {
    const message: NuiWireMessage<T> = { action, data }
    window.postMessage(message, "*")
}

function postRequest<T>(action: string, payload: T) {
    post(action, { requestId: Math.floor(Math.random() * 1_000_000_000), token: "dev-token", payload })
}

const SAMPLE_ITEMS: MenuItem[] = [
    { id: "give", label: "Give item", description: "Hand over an item", icon: "gift" },
    { id: "inspect", label: "Inspect", description: "Look closer" },
    { id: "cancel", label: "Locked action", disabled: true },
    { id: "dispatch", label: "Dispatch vehicle", description: "Send an available vehicle to the marked location." },
    { id: "evidence", label: "Review evidence locker", description: "A deliberately longer description verifies wrapping without changing row rhythm." },
    { id: "invoice", label: "Create invoice" },
    { id: "garage", label: "Request garage access", description: "Access is checked against the currently selected character." },
    { id: "radio", label: "Set radio channel" },
    { id: "profile", label: "Open personnel profile", description: "Long labels, descriptions, filtering and scrolling all stay readable." },
    { id: "report", label: "File incident report" },
    { id: "storage", label: "Manage shared storage", disabled: true },
    { id: "service", label: "Request service" },
]

const SAMPLE_APP: AppDefinition = {
    id: "qbmdt:police",
    title: "Mobile Data Terminal",
    description: "Los Santos Police Department",
    icon: "Shield",
    defaultView: "dashboard",
    footer: "LSPD secure network · Unit 312",
    navigation: [
        {
            id: "dashboard",
            label: "Dashboard",
            description: "Current operational picture",
            icon: "Home",
            group: "Workspace",
            content: {
                title: "Shift overview",
                description: "Live workload and the records requiring attention.",
                actions: [{ id: "new-report", label: "New report", icon: "Plus", variant: "primary" }],
                blocks: [
                    {
                        type: "stats",
                        items: [
                            { label: "Active units", value: 12, description: "3 supervisors", icon: "Users", tone: "success" },
                            { label: "Open reports", value: 4, description: "1 high priority", icon: "FileText", tone: "warning" },
                            { label: "Active calls", value: 7, description: "Updated just now", icon: "Radio", tone: "primary" },
                        ],
                    },
                    {
                        type: "table",
                        title: "Recent incidents",
                        action: "open-incident",
                        idKey: "id",
                        columns: [
                            { key: "id", label: "Report" },
                            { key: "title", label: "Incident" },
                            { key: "officer", label: "Officer" },
                            { key: "status", label: "Status", align: "right" },
                        ],
                        rows: [
                            { id: "R-1042", title: "Vehicle theft", officer: "J. Morgan", status: "Open" },
                            { id: "R-1041", title: "Traffic collision", officer: "A. Silva", status: "Review" },
                            { id: "R-1038", title: "Property damage", officer: "D. Price", status: "Filed" },
                        ],
                    },
                ],
            },
        },
        {
            id: "records",
            label: "Records",
            description: "People, vehicles, and reports",
            icon: "Database",
            group: "Information",
            badge: 3,
            tabs: [
                { id: "people", label: "People", content: { blocks: [{ type: "empty", title: "Find a person", description: "Search and recent records will live here.", icon: "Users" }] } },
                { id: "vehicles", label: "Vehicles", content: { blocks: [{ type: "empty", title: "Find a vehicle", description: "Search registrations, flags, and ownership.", icon: "Car" }] } },
                { id: "reports", label: "Reports", badge: 3, content: { blocks: [{ type: "empty", title: "No report selected", description: "Choose a report from the index to review it.", icon: "FileText" }] } },
            ],
        },
        {
            id: "dispatch",
            label: "Dispatch",
            description: "Calls and unit status",
            icon: "Radio",
            group: "Operations",
            content: {
                blocks: [{
                    type: "list",
                    title: "Active calls",
                    items: [
                        { id: "C-219", label: "10-31 · Robbery in progress", description: "Strawberry Avenue · 48 seconds ago", badge: "High", tone: "destructive", action: "open-call" },
                        { id: "C-218", label: "Traffic obstruction", description: "Olympic Freeway · 3 minutes ago", badge: "Normal", action: "open-call" },
                    ],
                }],
            },
        },
    ],
}

const SAMPLE_HUD_SNAPSHOT: ZoneCreatorHudSnapshot = {
    type: "box",
    pointCount: 0,
    hasCenter: true,
    activeParam: "zOffset",
    size: 4,
    height: 3,
    rotation: 45,
    radius: 3,
    thickness: 4,
    zOffset: -1.5,
    editIndex: 0,
    canConfirm: true,
    aiming: true,
    isShiftHeld: false,
    stepSize: 0.25,
}

const SAMPLE_PLACEMENT_START: PlacementStartPayload = {
    model: "prop_tool_bench02",
    bindings: {
        forward: "UP",
        backward: "DOWN",
        left: "LEFT",
        right: "RIGHT",
        up: "PAGEUP",
        down: "PAGEDOWN",
        rotateLeft: "LBRACKET",
        rotateRight: "RBRACKET",
        cycle: "TAB",
        confirm: "RETURN",
        cancel: "X",
    },
}

const SAMPLE_PLACEMENT_HUD: PlacementHudSnapshot = {
    coords: { x: 100.125, y: 200.5, z: 30.075 },
    rotation: { pitch: 5, roll: -2.5, yaw: -90 },
    activeAxis: "yaw",
    isShiftHeld: false,
}

const actions: { label: string; run: () => void }[] = [
    {
        label: "App shell",
        run: () => postRequest("openApp", { app: SAMPLE_APP, viewId: "dashboard", data: { unit: "312" } }),
    },
    {
        label: "Notify (every variant)",
        run: () => {
            const variants: NotifyPayload[] = [
                { title: "Info", message: "Something happened.", type: "info" },
                { title: "Success", message: "That worked.", type: "success" },
                { title: "Warning", message: "Careful with that.", type: "warning" },
                { title: "Error", message: "That did not work.", type: "error" },
            ]
            for (const variant of variants) post<NotifyPayload>("notify", { ...variant, duration: 6000 })
        },
    },
    {
        label: "Notify (positions)",
        run: () => {
            const positions: NotifyPosition[] = ["top-left", "top-center", "top-right", "bottom-left", "bottom-center", "bottom-right"]
            for (const position of positions) {
                post<NotifyPayload>("notify", { title: position, position, type: "info", duration: 6000 })
            }
        },
    },
    {
        label: "Notify (long copy)",
        run: () => post<NotifyPayload>("notify", {
            title: "Long notification title for wrapping",
            message: "This verifies that a longer gameplay notice wraps cleanly inside the fixed neutral toast without stealing input.",
            type: "warning",
            duration: 6000,
        }),
    },
    {
        label: "Menu",
        run: () => postRequest<OpenMenuPayload>("openMenu", { title: "Sample Menu", items: SAMPLE_ITEMS }),
    },
    {
        label: "Interact selector",
        run: () => post<InteractOpenPayload>("openInteract", [
            { label: "Inspect vehicle" },
            { label: "Open storage" },
            { label: "Cancel interaction" },
        ]),
    },
    {
        label: "Interact next row",
        run: () => post<number>("scroll", 1),
    },
    {
        label: "Interact select",
        run: () => post<undefined>("select", undefined),
    },
    {
        label: "Menu (nested)",
        run: () =>
            postRequest<OpenMenuPayload>("openMenu", {
                title: "Nested menu",
                items: [
                    {
                        id: "vehicle",
                        label: "Vehicle",
                        description: "Nested one level",
                        submenu: {
                            title: "Vehicle",
                            items: [
                                { id: "repair", label: "Repair" },
                                { id: "remove", label: "Remove" },
                                {
                                    id: "doors",
                                    label: "Doors",
                                    description: "Nested two levels",
                                    submenu: {
                                        title: "Doors",
                                        items: [
                                            { id: "lock", label: "Lock" },
                                            { id: "unlock", label: "Unlock" },
                                        ],
                                    },
                                },
                            ],
                        },
                    },
                    {
                        id: "player",
                        label: "Player",
                        description: "Reuses the 'remove' id",
                        submenu: {
                            title: "Player",
                            items: [
                                { id: "heal", label: "Heal" },
                                { id: "remove", label: "Remove" },
                            ],
                        },
                    },
                    { id: "top", label: "Top-level action", description: "No submenu — resolves immediately" },
                ],
            }),
    },
    {
        label: "Radial menu",
        run: () => postRequest<OpenRadialMenuPayload>("openRadialMenu", {
            items: [
                { id: "engine", label: "Engine", icon: "Wrench", description: "Check the engine bay" },
                { id: "doors", label: "Doors", icon: "Car", submenu: { items: [{ id: "lock", label: "Lock", icon: "Lock" }, { id: "unlock", label: "Unlock", icon: "Unlock" }] } },
                { id: "disabled", label: "Unavailable", icon: "Ban", disabled: true },
            ],
        }),
    },
    {
        label: "Radial menu (paged)",
        run: () => postRequest<OpenRadialMenuPayload>("openRadialMenu", {
            radius: 170,
            items: Array.from({ length: 12 }, (_, index) => ({ id: `option-${index + 1}`, label: `Option ${index + 1}`, icon: "Star" })),
        }),
    },
    {
        label: "Context menu",
        run: () => postRequest<OpenContextMenuPayload>("openContextMenu", { items: SAMPLE_ITEMS, x: 300, y: 300 }),
    },
    {
        label: "Context menu (edge)",
        run: () => postRequest<OpenContextMenuPayload>("openContextMenu", {
            items: SAMPLE_ITEMS,
            x: window.innerWidth - 4,
            y: window.innerHeight - 4,
        }),
    },
    {
        label: "Input dialog (validation)",
        run: () =>
            postRequest<OpenInputDialogPayload>("openInputDialog", {
                title: "Sample Form",
                description: "A field of every type.",
                fields: [
                    { id: "name", label: "Name", type: "text", required: true, placeholder: "Jane Doe" },
                    { id: "pin", label: "PIN", type: "password", pattern: "^\\d{4}$", placeholder: "4 digits" },
                    { id: "notes", label: "Notes", type: "textarea", rows: 4, placeholder: "Anything else?" },
                    { id: "amount", label: "Amount", type: "number", default: 1, min: 0, max: 10 },
                    { id: "volume", label: "Volume", type: "range", default: 50, min: 0, max: 100, step: 5 },
                    { id: "fine", label: "Fine", type: "range", default: 0.5, min: 0, max: 1, step: 0.05 },
                    { id: "confirm", label: "I understand", type: "checkbox" },
                    {
                        id: "color",
                        label: "Color",
                        type: "select",
                        options: [
                            { value: "red", label: "Red" },
                            { value: "blue", label: "Blue" },
                        ],
                    },
                ],
            }),
    },
    {
        label: "Alert (confirm + cancel)",
        run: () =>
            postRequest<OpenAlertPayload>("openAlert", {
                title: "Delete everything?",
                message: "A destructive confirmation with both buttons.",
                image: "https://placehold.co/640x320/171717/F5F5F5?text=Alert+artwork",
                confirmLabel: "Delete",
                cancelLabel: "Keep it",
                destructive: true,
            }),
    },
    {
        label: "Alert (acknowledge only)",
        run: () =>
            postRequest<OpenAlertPayload>("openAlert", {
                title: "Acknowledge",
                message: "No cancel button; Escape and the backdrop are both inert.",
                confirmLabel: "Understood",
                cancellable: false,
            }),
    },
    {
        label: "Progress bar",
        run: () => post<ProgressStartPayload>("progressStart", { label: "Hotwiring...", duration: 8000 }),
    },
    {
        label: "Progress bar (cancelled)",
        run: () => {
            post<ProgressStartPayload>("progressStart", { label: "Interrupted shortly...", duration: 8000 })
            setTimeout(() => post<undefined>("progressCancel", undefined), 1500)
        },
    },
    {
        label: "Zone HUD (starting)",
        run: () => post<ZoneCreatorStartPayload>("zoneCreator:start", { type: "box" }),
    },
    {
        label: "Zone HUD (live)",
        run: () => {
            post<ZoneCreatorStartPayload>("zoneCreator:start", { type: "box" })
            post<ZoneCreatorHudSnapshot>("zoneCreator:hud", SAMPLE_HUD_SNAPSHOT)
        },
    },
    {
        label: "Zone HUD (shift fast-adjust)",
        run: () => {
            post<ZoneCreatorStartPayload>("zoneCreator:start", { type: "box" })
            post<ZoneCreatorHudSnapshot>("zoneCreator:hud", {
                ...SAMPLE_HUD_SNAPSHOT,
                isShiftHeld: true,
                stepSize: 0.625, // sizeStep (0.25) * shiftMultiplier (2.5), per config.lua
            })
        },
    },
    {
        label: "Zone HUD (poly edit)",
        run: () => {
            post<ZoneCreatorStartPayload>("zoneCreator:start", { type: "poly" })
            post<ZoneCreatorHudSnapshot>("zoneCreator:hud", {
                ...SAMPLE_HUD_SNAPSHOT,
                type: "poly",
                pointCount: 4,
                activeParam: "editPoint",
                editIndex: 2,
                canConfirm: false,
                aiming: false,
            })
        },
    },
    {
        // Mirrors the real teardown wire shape: Lua sends data = nil, which
        // arrives as an ABSENT field (undefined), never a literal null.
        label: "Zone HUD teardown",
        run: () => post<undefined>("zoneCreator:hud", undefined),
    },
    {
        label: "Zone confirm",
        run: () =>
            postRequest<ZoneCreatorConfirmPayload>("zoneCreator:confirm", {
                type: "box",
                snippet: "QB.zones.box({\n    coords = vector3(100.00, 200.00, 30.00),\n    size = vector3(4.00, 4.00, 3.00),\n    rotation = 45.00,\n})",
            }),
    },
    {
        label: "Zone confirm (overflow)",
        run: () => postRequest<ZoneCreatorConfirmPayload>("zoneCreator:confirm", {
            type: "poly",
            snippet: `QB.zones.poly({
    points = {
        vector3(100.00, 200.00, 30.00),
        vector3(140.00, 200.00, 30.00),
        vector3(140.00, 240.00, 30.00),
        vector3(100.00, 240.00, 30.00),
    },
    minZ = 28.00,
    maxZ = 35.00,
    metadata = "A deliberately long code value verifies horizontal overflow and the thumb-only scrollbar behavior in the generated preview.",
})`,
        }),
    },
    {
        label: "Placement HUD (live)",
        run: () => {
            post<PlacementStartPayload>("placement:start", SAMPLE_PLACEMENT_START)
            post<PlacementHudSnapshot>("placement:hud", SAMPLE_PLACEMENT_HUD)
        },
    },
    {
        label: "Placement HUD (fast pitch)",
        run: () => {
            post<PlacementStartPayload>("placement:start", SAMPLE_PLACEMENT_START)
            post<PlacementHudSnapshot>("placement:hud", {
                ...SAMPLE_PLACEMENT_HUD,
                activeAxis: "pitch",
                isShiftHeld: true,
            })
        },
    },
    {
        label: "Placement HUD teardown",
        run: () => post<undefined>("placement:hud", undefined),
    },
    {
        label: "Placement confirm",
        run: () => postRequest<PlacementConfirmPayload>("placement:confirm", {
            model: "prop_tool_bench02",
            snippet: "{\n    model = 'prop_tool_bench02',\n    coords = vector3(100.1250, 200.5000, 30.0750),\n    heading = 270.0000,\n    rotation = {\n        pitch = 5.0000,\n        roll = -2.5000,\n        yaw = -90.0000,\n    },\n}",
        }),
    },
]

/**
 * Floating panel of buttons that fire typed sample NUI messages, so every
 * component can be visually developed/reviewed outside the game. Stripped
 * from production builds entirely (import.meta.env.DEV); renders nothing in
 * a dev build that somehow runs inside the real NUI frame (isBrowserEnv).
 */
export function DevHarness() {
    if (!import.meta.env.DEV || !isBrowserEnv) return null

    return (
        <div className="pointer-events-auto fixed bottom-4 right-4 z-dev flex max-h-[calc(100vh-2rem)] w-56 flex-col gap-1 overflow-y-auto rounded-xl border bg-card p-3 text-card-foreground shadow-floating">
            <p className="title-rail mb-1 text-xs font-semibold text-muted-foreground">Dev harness</p>
            {actions.map((action) => (
                <Button key={action.label} size="sm" variant="secondary" onClick={action.run}>
                    {action.label}
                </Button>
            ))}
        </div>
    )
}
