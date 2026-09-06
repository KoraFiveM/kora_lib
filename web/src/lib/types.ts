// The full Lua <-> NUI message contract. Every message from Lua arrives as a
// `window` `message` event shaped like NuiWireMessage below (see
// useNuiEvent.ts). Fire-and-forget messages (QB.nui.send) put the raw payload
// directly in `data`; request/response messages (QB.nui.request) wrap it as
// NuiRequestEnvelope, and expect the reply POSTed to the "qblib:nui:response"
// NUI callback (see respondToNui in fetchNui.ts) as a NuiResponseEnvelope.
//
// Keep this file in sync with every Lua-side QB.nui.send/request call site:
// modules/nui/client.lua (the bridge itself and the openMenu/openContextMenu/
// openRadialMenu/openInputDialog/copyToClipboard wrappers), modules/zones/client.lua (the
// zoneCreator:* actions), modules/placement/client.lua (the placement:* actions),
// modules/notify/client.lua (the "notify" action),
// and modules/minigames/client.lua (the minigames:* actions), plus
// qbtarget/client/loop.lua (the qbtarget:target display action and the
// qbtarget:select candidate-picker action) -- this file is the one place the
// whole contract is written down on the NUI side.

// The outer wire envelope every Lua->NUI message travels in.
export interface NuiWireMessage<T = unknown> {
    action: string
    data: T
}

export interface NuiRequestEnvelope<T = unknown> {
    requestId: number
    // Random per-request secret that must be echoed back in the response --
    // FiveM's NUI callback routing isn't scoped to the frame that issued a
    // given request, so this is what stops another resource's NUI page from
    // spoofing a response for a guessable sequential requestId. See
    // modules/nui/AGENTS.md.
    token: string
    payload: T
}

export interface NuiResponseEnvelope<T = unknown> {
    requestId: number
    token: string
    ok: boolean
    result?: T
    error?: string
}

// qblib interact contract. The browser renders the selector but never owns
// game controls, focus, or selection state outside the visible row.
export interface InteractOption {
    label: string
}

// action: "openInteract". `scroll` carries -1 or 1; `select` confirms the
// highlighted row; `hideInteract` closes it. The selection POSTs its one-based
// index straight to the `selectOption` NUI callback.
export type InteractOpenPayload = InteractOption[]

// action: "qbtarget:target" (fire-and-forget) -- a transparent, game-input
// driven target reticle/prompt. qbtarget owns raycasts, eligibility, controls,
// and selection; this payload is display-only and never requests NUI focus.
export interface TargetHudPayload {
    active: boolean
    label?: string
    optionCount?: number
}

// action: "qbtarget:select" (fire-and-forget) -- the compact candidate picker
// shown when more than one option is available under the reticle. Mirrors
// InteractOpenPayload's display-only, pointer-transparent contract, but is
// qbtarget's own action name/payload shape: qbtarget cycles/confirms/cancels
// entirely via its own control polling in client/loop.lua (no NUI focus, no
// selectOption callback round trip -- Lua already knows the active index).
export interface TargetSelectOption {
    label: string
    icon?: string
}

export interface TargetSelectPayload {
    active: boolean
    items?: TargetSelectOption[]
    activeIndex?: number
}

// action: "textui:set" (fire-and-forget). `false` hides the display.
export interface TextUiPayload {
    id: number
    text: string
    key?: string
    icon?: string
    position: "left-center" | "right-center" | "top-center" | "bottom-center"
}

/**
 * A nested level, opened when its parent item is selected instead of
 * resolving the request. Navigation happens entirely inside the NUI -- Lua
 * sends the whole tree in one openMenu call and gets one answer back, so
 * there's no per-level round trip (which would flicker focus on every step).
 *
 * openContextMenu ignores `submenu`: it's an anchored one-shot list with
 * nowhere sensible to put a back row.
 */
export interface MenuItem {
    id: string
    label: string
    description?: string
    icon?: string
    /** Trusted legacy/resource supplied item artwork URL (e.g. nui://). */
    image?: string
    disabled?: boolean
    /** Opens a nested level instead of resolving. `title` defaults to this item's label. */
    submenu?: { title?: string; items: MenuItem[] }
}

// action: "openMenu" (request)
export interface OpenMenuPayload {
    title?: string
    items: MenuItem[]
    /** Optional placement; omitted values retain the existing centred menu. */
    position?: {
        horizontal?: "left" | "center" | "right"
        vertical?: "top" | "center" | "bottom"
        /** Distance from the chosen horizontal edge, in pixels. */
        offsetX?: number
        /** Distance from the chosen vertical edge, in pixels. */
        offsetY?: number
    }
    /** Optional menu limits in pixels. */
    maxWidth?: number
    maxHeight?: number
}

// action: "closeMenu" (fire-and-forget)
export type CloseMenuPayload = Record<string, never>

// action: "openContextMenu" (request)
export interface OpenContextMenuPayload {
    items: MenuItem[]
    x?: number
    y?: number
}

// action: "openRadialMenu" (request). Items and results deliberately reuse
// openMenu's schema so callers can share their item trees between both views.
export interface OpenRadialMenuPayload {
    items: MenuItem[]
    radius?: number
}

// `path` is every id walked through to reach the selection, root-first, so a
// leaf inside a submenu is unambiguous even when two branches reuse an id
// (a "remove" under both "vehicle" and "player", say). For a top-level pick
// it's just { selectedId }. Flat callers can keep reading selectedId alone.
export type MenuResult = { selectedId: string; path: string[] } | { cancelled: true }

export type FieldValue = string | number | boolean

export type InputFieldType = "text" | "password" | "textarea" | "number" | "checkbox" | "select" | "range" | "combobox"

export interface InputField {
    id: string
    label: string
    type: InputFieldType
    // `select` (fixed choice) and `combobox` (free text + filtered
    // suggestions from this same list) both use this.
    options?: { value: string; label: string }[]
    default?: FieldValue
    placeholder?: string
    // textarea only; ignored by every other field type.
    rows?: number
    // Validation, all optional and opt-in -- a field with none of these set
    // behaves exactly as before. Checked client-side before Confirm is
    // allowed to respond; Lua-side validation is still the caller's job for
    // anything that actually matters (this only saves a round trip).
    required?: boolean
    min?: number
    max?: number
    pattern?: string
    /**
     * Slider granularity, `range` only (default 1). `min`/`max` are not
     * optional for a range in practice -- a slider with no bounds has nothing
     * to slide between -- so they fall back to 0/100.
     */
    step?: number
}

// action: "openInputDialog" (request)
export interface OpenInputDialogPayload {
    title?: string
    description?: string
    fields: InputField[]
}

export type InputDialogResult = { values: Record<string, FieldValue> } | { cancelled: true }

// action: "openAlert" (request) -- mount AlertDialog.
export interface OpenAlertPayload {
    title?: string
    message: string
    /** Trusted alert artwork URL (for example, an `nui://` path). Hidden if it fails to load. */
    image?: string
    /** Confirm button label. Defaults to "Confirm". */
    confirmLabel?: string
    /**
     * Cancel button label. Defaults to "Cancel". Pass `cancellable: false` to
     * drop the cancel button entirely, for an acknowledge-only alert.
     */
    cancelLabel?: string
    /** Default true. When false there is no cancel button, and Escape/backdrop can't dismiss. */
    cancellable?: boolean
    /** Styles Confirm as a destructive action. Purely cosmetic. */
    destructive?: boolean
}

// `confirmed: false` covers every "no" -- cancel button, Escape, backdrop --
// deliberately NOT a separate `cancelled` shape like the menu/input results:
// a confirmation only ever has two outcomes for the caller, and collapsing
// them means no call site can forget to handle one of them.
export type AlertResult = { confirmed: boolean }

// action: "copyToClipboard" (request) -- resolves `result: true` on success.
export interface CopyToClipboardPayload {
    text: string
}

export type PlacementRotationAxis = "yaw" | "pitch" | "roll"

export interface PlacementBindings {
    forward: string
    backward: string
    left: string
    right: string
    up: string
    down: string
    rotateLeft: string
    rotateRight: string
    cycle: string
    confirm: string
    cancel: string
}

// action: "placement:start" (fire-and-forget) -- mount PlacementHud.
export interface PlacementStartPayload {
    model: string
    bindings: PlacementBindings
}

// action: "placement:hud" (fire-and-forget) -- update PlacementHud, or
// unmount it when the payload is nullish. Lua's nil payload arrives undefined.
export interface PlacementHudSnapshot {
    coords: { x: number; y: number; z: number }
    rotation: { pitch: number; roll: number; yaw: number }
    activeAxis: PlacementRotationAxis
    isShiftHeld: boolean
}

// action: "placement:confirm" (request) -- mount PlacementConfirmDialog.
export interface PlacementConfirmPayload {
    model: string
    snippet: string
}

export type PlacementConfirmResult = { confirmed: boolean }
// action: "placement:closeConfirm" (fire-and-forget, no payload) -- answer
// any open confirmation as Keep Editing so Lua's request releases NUI focus.

export type ZoneType = "box" | "sphere" | "poly"

// action: "zoneCreator:start" (fire-and-forget) -- mount ZoneCreatorHud.
export interface ZoneCreatorStartPayload {
    type: ZoneType
}

// Which numeric parameter the scroll wheel currently adjusts -- mirrors
// creatorParamCycles in modules/zones/client.lua.
// "editPoint" is the odd one out: a MODE, not a numeric value (the placement
// key moves the grabbed poly point instead of appending one), so there's no
// matching number on the snapshot -- ZoneCreatorHud special-cases it.
export type ZoneCreatorParam = "size" | "height" | "rotation" | "radius" | "thickness" | "zOffset" | "editPoint"

// action: "zoneCreator:hud" (fire-and-forget) -- update ZoneCreatorHud, or
// unmount it when the payload is nullish (the creator session ended). NOTE:
// Lua sends the teardown as `data = nil`, and a nil-valued Lua table key is
// simply absent when serialized -- so the teardown arrives as `undefined`,
// never a literal `null`. Always check with `== null`/`!snapshot`, not `=== null`.
export interface ZoneCreatorHudSnapshot {
    type: ZoneType
    pointCount: number
    hasCenter: boolean
    activeParam: ZoneCreatorParam
    size: number
    height: number
    rotation: number
    radius: number
    thickness: number
    /** Vertical offset from the placement raycast hit. Signed -- negative sinks the zone. */
    zOffset: number
    /** 1-based poly point the "editPoint" mode would move; 0 when nothing is grabbed. */
    editIndex: number
    canConfirm: boolean
    aiming: boolean
    /** Whether Shift is currently held (speeds up scroll-adjustment; see shiftHeld() in client.lua). */
    isShiftHeld: boolean
    /** What one scroll tick currently moves the active param by, already shiftMultiplier-scaled. 0 for "editPoint" (no step). */
    stepSize: number
}

// action: "zoneCreator:confirm" (request) -- mount ZoneConfirmDialog.
export interface ZoneCreatorConfirmPayload {
    type: ZoneType
    snippet: string
}

export type ZoneCreatorConfirmResult = { confirmed: boolean }

// action: "progressStart" (fire-and-forget) -- mount ProgressBar. See
// modules/progressbar/. Lua owns the actual timing/completion decision (a
// per-frame poll, not this component) -- this payload only drives the
// visual fill, which is why there is no response to send back.
export interface ProgressStartPayload {
    label: string
    duration: number
}

// action: "progressCancel" (fire-and-forget, no payload) -- hides the bar
// immediately instead of waiting for its own fill animation to finish.
// Lua sends this on every early-exit path (death, the cancel key,
// QB.progressbar.cancel(), or QB.progressbar.start itself erroring), so the
// visual can never keep filling past the point the real bar it represents
// already ended.

export type NotifyType = "info" | "success" | "warning" | "error"

export type NotifyPosition =
    | "top-left"
    | "top-center"
    | "top-right"
    | "bottom-left"
    | "bottom-center"
    | "bottom-right"

// action: "notify" (fire-and-forget) -- see modules/notify/. QB.notify.send
// resolves duration/type/position from Config.notify before sending (see
// QB.notify.withDefaults), so they arrive populated in practice; they stay
// optional here because the Toast component must not trust that -- any
// resource can post a bare payload straight to this action.
export interface NotifyPayload {
    title?: string
    message?: string
    duration?: number
    type?: NotifyType
    position?: NotifyPosition
    // Overrides the variant's default icon; resolved against the curated set
    // in lib/icon.ts, so an unknown name simply renders no icon.
    icon?: string
}

export type MinigameType =
    | "lockpick"
    | "skillbar"
    | "circuit"
    | "mash"
    | "pinpad"
    | "quiz"
    | "wordguess"
    | "wordscramble"
    | "keys"
    | "hacking"

export interface LockpickPin {
    index: number
    /** 0..1 position on the shared triangle-wave track this pin's indicator must be over when pressed. */
    target: number
}

export interface LockpickPuzzle {
    pinCount: number
    /** +/- window around each pin's target, 0..1 scale -- also the rendered width of its target zone. */
    tolerance: number
    /** Triangle-wave cycles per second every pin's indicator moves at. */
    speed: number
    pins: LockpickPin[]
}

export interface LockpickPress {
    index: number
    /** Milliseconds since the round started -- never a position; the server recomputes that itself. */
    elapsed: number
}

export interface LockpickAttempt {
    presses: LockpickPress[]
}

export interface SkillbarPuzzle {
    zoneStart: number
    zoneEnd: number
    speed: number
}

export interface SkillbarAttempt {
    /** Milliseconds since the round started when the player pressed -- never a position. */
    elapsed: number
}

export interface CircuitNode {
    id: string
    color: string
    side: "input" | "output"
}

export interface CircuitPuzzle {
    /** Correctness is inherent in the colors -- connect every input to the output sharing its color. */
    nodes: CircuitNode[]
}

export interface CircuitConnection {
    from: string
    to: string
    elapsed: number
}

export interface CircuitAttempt {
    connections: CircuitConnection[]
}

export interface MashPuzzle {
    requiredPresses: number
    timeLimit: number
}

export interface MashAttempt {
    pressTimestamps: number[]
}

export interface CancelledAttempt {
    cancelled: true
}

// The six types below back the qb-minigames compat shim
// (compat/client/qb-minigames.lua). Their puzzle CONTENT (the PIN, the word,
// the quiz questions) comes from the calling script via opts, so -- unlike
// lockpick/skillbar/circuit/mash's purely config-randomized puzzles -- the
// Puzzle types below carry that content straight through from the server.

export interface PinpadPuzzle {
    digitCount: number
}

export interface PinpadDigit {
    value: number
    /** Milliseconds since the round started -- never which digit is "correct". */
    elapsed: number
}

export interface PinpadAttempt {
    digits: PinpadDigit[]
}

export interface QuizQuestion {
    numb: number
    question: string
    /** The correct answer is never sent -- see server.lua's generate.quiz. */
    options: string[]
}

export interface QuizPuzzle {
    questions: QuizQuestion[]
    correctRequired: number
    /** ms budget per question, informational only -- the round's own `timeLimit` covers the whole quiz. */
    timePerQuestion: number
}

export interface QuizAnswer {
    choice: string
    /** Milliseconds since the round started when this question was answered. */
    elapsed: number
}

export interface QuizAttempt {
    answers: QuizAnswer[]
}

export interface WordGuessPuzzle {
    hint: string
    length: number
    guesses: number
}

export interface WordGuessLetter {
    letter: string
    elapsed: number
}

export interface WordGuessAttempt {
    guesses: WordGuessLetter[]
}

export interface WordScramblePuzzle {
    scrambled: string
    hint: string
}

export interface WordScrambleAttempt {
    guess: string
    elapsed: number
}

export interface KeysPuzzle {
    /** Revealed in full up front -- the player has to see which key is being asked for next. */
    pattern: string[]
}

export interface KeysPress {
    key: string
    elapsed: number
}

export interface KeysAttempt {
    presses: KeysPress[]
}

export interface HackingPuzzle {
    /** Revealed directly, same reasoning as lockpick's target zone or keys' pattern. */
    code: string
    solutionsize: number
}

export interface HackingAttempt {
    submitted: string
    elapsed: number
}

export type MinigamePuzzle =
    | LockpickPuzzle
    | SkillbarPuzzle
    | CircuitPuzzle
    | MashPuzzle
    | PinpadPuzzle
    | QuizPuzzle
    | WordGuessPuzzle
    | WordScramblePuzzle
    | KeysPuzzle
    | HackingPuzzle

export type MinigameAttempt =
    | LockpickAttempt
    | SkillbarAttempt
    | CircuitAttempt
    | MashAttempt
    | PinpadAttempt
    | QuizAttempt
    | WordGuessAttempt
    | WordScrambleAttempt
    | KeysAttempt
    | HackingAttempt
    | CancelledAttempt

// action: "minigames:round" (request) -- mount/update MinigameContainer. Sent
// once per round: the FIRST round after QB.minigames.play() starts, and again
// after every failed-but-not-exhausted attempt, in the SAME mounted overlay
// (Lua never closes and reopens it between rounds -- see
// modules/minigames/AGENTS.md). `puzzle` is the server-generated round to
// render; it is NEVER the pass/fail answer itself -- see the per-type Puzzle
// comments above for what's actually visible vs. hidden.
export interface MinigamesRoundPayload {
    type: MinigameType
    sessionId: number
    /** 1-based current attempt number. */
    attempt: number
    /** Max attempts allowed for this play() call, constant across every round. */
    attempts: number
    /** ms budget for this round -- the component is expected to auto-submit once this elapses. */
    timeLimit: number
    /** Set from the second round on, when the previous attempt failed; absent on the first round. */
    lastResult?: "fail"
    puzzle: MinigamePuzzle
}

// action: "minigames:close" (fire-and-forget) -- unmount MinigameContainer.
export interface MinigamesClosePayload {
    result?: "success" | "exhausted" | "cancelled"
}
