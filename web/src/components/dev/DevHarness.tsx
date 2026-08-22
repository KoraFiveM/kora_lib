import { isBrowserEnv } from "@/lib/fetchNui"
import type {
    MenuItem,
    NotifyPayload,
    NotifyPosition,
    NuiWireMessage,
    OpenContextMenuPayload,
    OpenAlertPayload,
    OpenInputDialogPayload,
    OpenMenuPayload,
    ProgressStartPayload,
    ZoneCreatorConfirmPayload,
    ZoneCreatorHudSnapshot,
    ZoneCreatorStartPayload,
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
}

const actions: { label: string; run: () => void }[] = [
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
