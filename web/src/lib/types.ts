export interface NuiWireMessage<T = unknown> {
    action: string
    data: T
}

export interface NuiRequestEnvelope<T = unknown> {
    requestId: number
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

export interface InteractOption {
    label: string
    icon?: string
}

export type InteractOpenPayload = InteractOption[]

export interface TargetHudPayload {
    active: boolean
    label?: string
    optionCount?: number
}

export interface CameraHudPayload {
    active: boolean
    mode: "cctv" | "recording" | "helicam" | "operator"
    title: string
    subtitle: string
    cameraLabel: string
    cameraIndex: number
    totalCameras: number
    location?: string
    recording: boolean
    timestamp: boolean
    elapsed: number
}

export interface TextUiPayload {
    id: number
    text: string
    key?: string
    icon?: string
    iconColor?: string
    iconAnimation?: IconAnimation
    alignIcon?: "top" | "center"
    /** Scoped inline CSS declarations or a flat React-style property table. */
    style?: string | Record<string, string | number>
    position: "left-center" | "right-center" | "top-center" | "bottom-center"
}

export type IconAnimation =
    | "spin"
    | "spinPulse"
    | "spinReverse"
    | "pulse"
    | "beat"
    | "fade"
    | "beatFade"
    | "bounce"
    | "shake"

export type DialogSize = "xs" | "sm" | "md" | "lg" | "xl"

export type MenuMetadataItem = string | {
    label: string
    value?: unknown
    progress?: number
    colorScheme?: string
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
    /** Optional side-scroll values; defaultIndex is one-based. */
    values?: Array<string | { label: string; description?: string }>
    defaultIndex?: number
    /** A checkable row toggles in place rather than resolving the menu. */
    checked?: boolean
    progress?: number
    colorScheme?: string
    iconColor?: string
    /** Radial/image icon dimensions in CSS pixels, clamped to ox_lib's 0..100 range. */
    iconWidth?: number
    iconHeight?: number
    /** Font Awesome-compatible motion requested by ox_lib callers. */
    iconAnimation?: IconAnimation
    /** Informational row: remains readable/focusable but never selects. */
    readOnly?: boolean
    /** Show or suppress the trailing navigation affordance. */
    arrow?: boolean
    /** Structured detail rows used by ox_lib context menus. */
    metadata?: MenuMetadataItem[]
    /** Keep the menu mounted after confirmation; reported as a live confirmed event. */
    close?: boolean
    /** Opens a nested level instead of resolving. `title` defaults to this item's label. */
    submenu?: { title?: string; items: MenuItem[] }
}

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
    /** Prevent Escape/backdrop dismissal. */
    canClose?: boolean
    /** Initially selected one-based item index. */
    startIndex?: number
    /** Compact non-modal panel used by ox_lib list/context compatibility. */
    presentation?: "dialog" | "panel"
    /**
     * Render an external parent-navigation control in a panel header. Clicking
     * it emits a token-authenticated `back` request event with `{}` data and
     * does not settle the open request.
     */
    back?: boolean
}

/**
 * action: "updateMenu" (fire-and-forget, request-scoped). The envelope must
 * match the active request id/token and payload must be complete. Accepted
 * only by a mounted panel; it replaces the root view without settling it.
 */
export type UpdateMenuPayload = NuiRequestEnvelope<OpenMenuPayload>

export type CloseMenuPayload = Record<string, never>

export interface OpenContextMenuPayload {
    title?: string
    items: MenuItem[]
    x?: number
    y?: number
    canClose?: boolean
}

export interface OpenRadialMenuPayload {
    items: MenuItem[]
    radius?: number
    /** Max lines a tile label wraps onto before ellipsizing (1-4, default 3). */
    labelLines?: number
    /** Internal live-update hint: preserve the deepest still-valid submenu path. */
    path?: string[]
}

export type MenuResult = { selectedId: string; path: string[]; valueIndex?: number; checked?: boolean } | { cancelled: true; keyPressed?: "Escape" | "Backspace" }

export interface NuiRequestEventEnvelope<T = unknown> {
    requestId: number
    token: string
    event: string
    data: T
}

export interface KeyValueEntry {
    key: string
    value: string
}

export interface VectorFieldValue {
    x: number | string
    y: number | string
    z?: number | string
    w?: number | string
}

export type FieldValue = string | number | boolean | Array<string | number> | KeyValueEntry[] | VectorFieldValue

export type InputFieldType = "text" | "password" | "textarea" | "number" | "checkbox" | "select" | "multiselect" | "range" | "combobox" | "date" | "date-range" | "time" | "color" | "key-value" | "vector"

export interface InputOption {
    value: string | number
    label: string
    disabled?: boolean
}

export interface InputField {
    id: string
    label: string
    type: InputFieldType
    options?: InputOption[]
    /** Select options keyed by another select field's current value. */
    optionsByValue?: Record<string, InputOption[]>
    /** Field id that selects this field's `optionsByValue` entry. */
    dependsOn?: string
    default?: FieldValue
    description?: string
    placeholder?: string
    /** Key handling and labels for editable table rows. */
    keyMode?: "string" | "integer" | "integer-map" | "mixed"
    keyLabel?: string
    requiredKeys?: Array<string | number>
    valueLabel?: string
    /** Typed scalar table values; transport remains JSON strings per row. */
    valueField?: InputField & { type: "text" | "number" | "checkbox" | "select" }
    addRowLabel?: string
    removeRowLabel?: string
    /** Require a number field to contain an integer. */
    wholeNumber?: boolean
    /** Number of editable vector components. */
    dimensions?: 2 | 3 | 4
    /**
     * vector only: an inline button that fills the field with the local player's position
     * (x/y/z, heading as w). `vehicle` uses the vehicle's position and heading while seated.
     */
    pickPosition?: boolean | { label?: string; vehicle?: boolean }
    rows?: number
    required?: boolean
    /** Prevent interaction while retaining the field and its submitted value. */
    disabled?: boolean
    min?: number
    max?: number
    minLength?: number
    maxLength?: number
    pattern?: string
    /** ISO date limits used by date and date-range controls. */
    dateMin?: string | number
    dateMax?: string | number
    /** Convert submitted date values to local epoch milliseconds. */
    returnString?: boolean
    /** ox-compatible date output pattern when returnString is true. */
    dateFormat?: string
    precision?: number
    colorFormat?: "hex" | "hexa" | "rgb" | "rgba" | "hsl" | "hsla"
    timeFormat?: "12" | "24"
    clearable?: boolean
    searchable?: boolean
    maxSelectedValues?: number
    autosize?: boolean
    minRows?: number
    maxRows?: number
    icon?: string
    iconColor?: string
    /** text only: show a "Copy Text" button right of the input that copies its current value. */
    copyButton?: boolean | { label?: string }
    /** Optional compact numeric keypad, primarily for short PIN entry. */
    keypad?: boolean
    /** Strip non-digits from textual input and request a numeric keyboard. */
    numericOnly?: boolean
    /** Quick values rendered below number fields. */
    presets?: { label?: string; value: number }[]
    /** Render this field only when another field has the given scalar value. */
    visibleWhen?: { fieldId: string; equals: string | number | boolean }
    /**
     * Slider granularity, `range` only (default 1). `min`/`max` are not
     * optional for a range in practice -- a slider with no bounds has nothing
     * to slide between -- so they fall back to 0/100.
     */
    step?: number
}

export interface OpenInputDialogPayload {
    title?: string
    description?: string
    fields: InputField[]
    labels?: Partial<AppShellLabels>
    /** Default true. When false, Escape/backdrop and the cancel button are disabled. */
    allowCancel?: boolean
    /** ox_lib-compatible responsive dialog width. */
    size?: DialogSize
    /** Whether a backdrop click cancels the dialog. Defaults to true. */
    dismissOnBackdrop?: boolean
}

export type InputDialogResult = { values: Record<string, FieldValue> } | { cancelled: true }

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
    /** Cancel button visibility, independently of Escape dismissal. Defaults to `cancellable`. */
    showCancel?: boolean
    /** Corner close-button visibility. Defaults to `cancellable`. */
    showClose?: boolean
    /** Whether a backdrop click dismisses the alert. Defaults to true. */
    dismissOnBackdrop?: boolean
    /** Styles Confirm as a destructive action. Purely cosmetic. */
    destructive?: boolean
    /** Keep the default centred overlay unless explicitly disabled. */
    centered?: boolean
    /** ox_lib-compatible responsive dialog width. */
    size?: DialogSize
    /** Keep long content inside a dedicated scrolling region. */
    overflow?: boolean
}

export type AlertResult = { confirmed: boolean }

export interface CopyToClipboardPayload {
    text: string
}

export type AppTone = "neutral" | "primary" | "success" | "warning" | "destructive"

export interface AppAction {
    id: string
    label: string
    icon?: string
    variant?: "primary" | "secondary" | "outline" | "ghost" | "destructive"
    /** Current boolean state for a toggle action. Shown as an On/Off indicator. */
    state?: boolean
    disabled?: boolean
    data?: unknown
    /** Optional fields collected in the app shell before this action is sent. */
    fields?: InputField[]
    /** A short acknowledgement shown above destructive in-shell actions. */
    confirm?: string
    /** Submit button text for this action's in-shell form. Defaults to Confirm/Run action. */
    submitLabel?: string
    /** Release the shell before invoking actions which open another UI or world editor. */
    closeBeforeAction?: boolean
    /** Press-and-hold button: onAction gets context.hold "start" on press and "end" on release, never a click. */
    hold?: boolean
}

export interface AppStat {
    label: string
    value: string | number
    description?: string
    icon?: string
    tone?: AppTone
}

/** A compact, accessible value graph for progression and other bounded values. */
export interface AppProgressItem {
    label: string
    value: number
    max: number
    description?: string
    detail?: string
    icon?: string
    tone?: AppTone
}

export interface AppTableColumn {
    key: string
    label: string
    align?: "left" | "center" | "right"
    sortable?: boolean
    /** Optional CSS width. Supplying any column width enables fixed table layout. */
    width?: string | number
}

export interface AppRichValue {
    value?: string | number | boolean | null
    label?: string
    description?: string
    icon?: string
    tone?: AppTone
    badge?: boolean
    copyText?: string
    href?: string
}

export type AppTableValue = string | number | boolean | null | AppRichValue
export type AppTableRow = Record<string, AppTableValue>

export interface AppMetadataItem {
    label: string
    value: string | number | boolean
    tone?: AppTone
}

export type AppImageFit = "cover" | "contain" | "fill" | "none" | "scale-down"
export type AppImageAspect = "square" | "wide"

export interface AppListItem {
    id: string
    label: string
    description?: string
    icon?: string
    badge?: string | number
    tone?: AppTone
    action?: string | AppAction
    data?: unknown
    image?: string
    imageFit?: AppImageFit
    imageAspect?: AppImageAspect
    metadata?: AppMetadataItem[]
    actions?: AppAction[]
    children?: AppListItem[]
}

export interface AppDetailItem {
    label: string
    value?: string | number | boolean | null
    description?: string
    icon?: string
    tone?: AppTone
}

export interface AppTimelineItem {
    id: string
    title: string
    description?: string
    timestamp?: string
    icon?: string
    tone?: AppTone
    metadata?: AppMetadataItem[]
    actions?: AppAction[]
}

export interface AppMapMarker {
    id: string
    x: number
    y: number
    label: string
    description?: string
    heading?: number
    tone?: AppTone
    icon?: string
    action?: string
    data?: unknown
    expiresAt?: number
    /** Optional marker-specific fade window before expiry; overrides the map block default. */
    fadeDuration?: number
}

export interface AppMapTiles {
    /** URL template using {z}, {x}, and {y}; cross-resource cfx-nui URLs are supported. */
    url: string
    tileSize?: number
    grid?: { x: number; y: number }
    /** Optional two-point affine calibration from world coordinates to image pixels. */
    calibration?: {
        a: { world: { x: number; y: number }; image: { x: number; y: number } }
        b: { world: { x: number; y: number }; image: { x: number; y: number } }
    }
}

export interface AppShellLabels {
    cancel: string
    confirm: string
    working: string
    runAction: string
    search: string
    previous: string
    next: string
    noRecords: string
    nothingHere: string
    emptyTitle: string
    emptyDescription: string
    close: string
    select: string
    required: string
    invalidFormat: string
    minValue: string
    maxValue: string
    minLength: string
    maxLength: string
    page: string
    recenter: string
    clear: string
    backspace: string
    back: string
    open: string
    yes: string
    no: string
    map: string
    zoomIn: string
    zoomOut: string
    value: string
    decrease: string
    increase: string
    send?: string
    newMessages?: string
    newDivider?: string
    message?: string
    statusSent?: string
    statusDelivered?: string
    statusSeen?: string
}

export type AppBlock =
    | { type: "text"; title?: string; text: string }
    | { type: "stats"; title?: string; items: AppStat[] }
    | { type: "progress"; id?: string; title?: string; items: AppProgressItem[] }
    | { type: "table"; id?: string; title?: string; columns: AppTableColumn[]; rows: AppTableRow[]; empty?: string; action?: string; idKey?: string; searchable?: boolean; searchPlaceholder?: string; pageSize?: number; headerToggle?: { label: string; checked: boolean; action: string }; refreshAction?: string }
    | { type: "list"; id?: string; title?: string; items: AppListItem[]; empty?: string; layout?: "list" | "grid" | "cards"; cardStyle?: "compact" | "media"; imageFit?: AppImageFit; imageAspect?: AppImageAspect; columns?: 1 | 2 | 3 | 4; searchable?: boolean; searchPlaceholder?: string; pageSize?: number; scrollable?: boolean }
    | { type: "actions"; id?: string; title?: string; actions: AppAction[] }
    | { type: "form"; id: string; title?: string; description?: string; fields: InputField[]; action: AppAction; submitLabel?: string }
    | { type: "details"; id?: string; title?: string; columns?: number; items: AppDetailItem[] }
    | { type: "timeline"; id?: string; title?: string; items: AppTimelineItem[]; empty?: string }
    | { type: "map"; id?: string; title?: string; tiles: AppMapTiles; markers: AppMapMarker[]; selectedId?: string; action?: string; minZoom?: number; maxZoom?: number; initialZoom?: number; follow?: boolean; captureWheel?: boolean; recenter?: { x: number; y: number }; now?: number; fadeDuration?: number; empty?: string }
    | { type: "empty"; title: string; description?: string; icon?: string }
    | { type: "chat"; id: string; title?: string; messages: AppChatMessage[]; composer?: AppChatComposer; empty?: string; scrollable?: boolean; follow?: boolean }

export interface AppChatMessage {
    id: string
    author: string
    /** Plain text. Rendered as a React text node, never as HTML. */
    text: string
    timestamp?: string
    /** The viewer's own message: drawn as a right-aligned bubble. */
    mine?: boolean
    /** A "New" divider is drawn before the first unread message. */
    unread?: boolean
    /** Delivery ticks on the viewer's own (`mine`) messages: one tick sent, two delivered, two in the brand colour seen. */
    status?: "sent" | "delivered" | "seen"
    badge?: string
    tone?: AppTone
}

export interface AppChatComposer {
    /** Plain action: onAction receives context.value = { message }. */
    action: AppAction
    placeholder?: string
    maxLength?: number
    disabled?: boolean
    /** Shown in place of the input while disabled. */
    note?: string
}

export interface AppContent {
    title?: string
    description?: string
    actions?: AppAction[]
    blocks?: AppBlock[]
    /** Set false to keep the shell fixed while a scrollable collection block owns overflow. */
    scrollable?: boolean
}

export interface AppTab {
    id: string
    label: string
    badge?: string | number
    content?: AppContent
    /** Action the header "<" runs while this tab is shown, instead of the shell's own history step. */
    back?: string
}

export interface AppNavigationItem {
    id: string
    label: string
    description?: string
    icon?: string
    badge?: string | number
    group?: string
    disabled?: boolean
    /** Action invoked when the user opens this view, useful for lazy data loading. */
    onOpen?: string
    defaultTab?: string
    tabs?: AppTab[]
    content?: AppContent
}

export interface AppDefinition {
    id: string
    /** Lua has registered an onChange handler for form edits. */
    onChange?: boolean
    title: string
    description?: string
    icon?: string
    navigation: AppNavigationItem[]
    layout?: "standard" | "compact"
    /** Screen placement for compact, task-focused applications. */
    placement?: "center" | "left" | "right"
    defaultView?: string
    width?: number
    height?: number
    footer?: string
    /** The app header acts as a drag handle (kora_lib fills this from Config.ui.apps.draggableDefault when omitted). */
    draggable?: boolean
    /** Remember the dragged position in localStorage (only meaningful when draggable). */
    rememberPosition?: boolean
    /** localStorage key suffix for the remembered position; defaults to the app id. */
    positionKey?: string
    /** #RRGGBB primary colour applied for this app's lifetime; omitted apps retain the player's /theme colour. */
    accent?: string
    /** Supplied by kora_lib from its active locale; consumers normally omit it. */
    labels?: Partial<AppShellLabels>
}

export interface OpenAppPayload {
    app: AppDefinition
    data?: unknown
    viewId?: string
    tabId?: string
}

export interface UpdateAppPayload {
    appId: string
    token: string
    app: AppDefinition
}

export interface CloseAppPayload {
    appId: string
    token: string
    reason?: string
}

export interface AppResult {
    closed: true
    reason: string
    viewId?: string
    tabId?: string
}

export interface AppActionRequest {
    appId: string
    token: string
    actionId: string
    viewId: string
    tabId?: string
    itemId?: string
    value?: unknown
}

export interface AppActionResult {
    close?: boolean
    app?: AppDefinition
    navigate?: { viewId: string; tabId?: string; replace?: boolean }
    notice?: { tone: AppTone; message: string }
}

export interface AppActionResponse {
    ok: boolean
    error?: string
    result?: AppActionResult
}

export type PlacementRotationAxis = "yaw" | "pitch" | "roll"

export interface PlacementStartPayload {
    model: string
}

export interface PlacementHudSnapshot {
    coords: { x: number; y: number; z: number }
    rotation: { pitch: number; roll: number; yaw: number }
    activeAxis: PlacementRotationAxis
    isShiftHeld: boolean
}

export interface PlacementConfirmPayload {
    model: string
    snippet: string
}

export type PlacementConfirmResult = { confirmed: boolean }

export type ZoneType = "box" | "sphere" | "poly"

export interface ZoneCreatorStartPayload {
    type: ZoneType
}

export type ZoneCreatorParam = "size" | "height" | "rotation" | "radius" | "thickness" | "zOffset" | "editPoint"

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

export interface ZoneCreatorConfirmPayload {
    type: ZoneType
    snippet: string
}

export type ZoneCreatorConfirmResult = { confirmed: boolean }

export interface NoclipHudPayload {
    active: boolean
    /** What A/D do: "strafe" (default) slides sideways, "turn" turns the view. Only changes the hint. */
    adMode?: "strafe" | "turn"
}

export interface ProgressStartPayload {
    label: string
    duration: number
    presentation?: "bar" | "circle"
    position?: "middle" | "bottom"
    /** rem from the screen bottom (Config.progressbar.bottomOffset); clears kora_hud's vitals. */
    bottomOffset?: number
}

export type NotifyType = "info" | "success" | "warning" | "error"

export type NotifyPosition =
    | "top-left"
    | "top-center"
    | "top-right"
    | "bottom-left"
    | "bottom-center"
    | "bottom-right"
    | "center-left"
    | "center-right"
    | "top"
    | "bottom"

export interface NotifyPayload {
    title?: string
    message?: string
    duration?: number
    type?: NotifyType
    position?: NotifyPosition
    icon?: string
    id?: string | number
    iconColor?: string
    iconAnimation?: IconAnimation
    alignIcon?: "top" | "center"
    style?: Record<string, string | number | Record<string, string | number>>
    showDuration?: boolean
}

export type MinigameType =
    | "lockpick"
    | "skillbar"
    | "circuit"
    | "mash"
    | "fishing"
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
    /** Optional KeyboardEvent.key accepted for this round; defaults to Space/Enter. */
    input?: string
}

export interface SkillbarAttempt {
    /** Milliseconds since the round started when the player pressed -- never a position. */
    elapsed: number
}

export type OxSkillCheckDifficulty = "easy" | "medium" | "hard" | { areaSize: number; speedMultiplier: number }

export interface OxSkillCheckPayload {
    difficulty: OxSkillCheckDifficulty | OxSkillCheckDifficulty[]
    inputs?: string[]
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

export interface FishingPuzzle {
    gameCount: number
    zoneSize: number
    speed: number
    /** Visible center of each bite window, in bottom-to-top gauge coordinates. */
    targets: number[]
}

export interface FishingReel {
    index: number
    /** Milliseconds since the round started; the server recomputes the marker position. */
    elapsed: number
}

export interface FishingAttempt {
    reels: FishingReel[]
}

export interface CancelledAttempt {
    cancelled: true
}

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
    | FishingPuzzle
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
    | FishingAttempt
    | PinpadAttempt
    | QuizAttempt
    | WordGuessAttempt
    | WordScrambleAttempt
    | KeysAttempt
    | HackingAttempt
    | CancelledAttempt

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

export interface MinigamesClosePayload {
    result?: "success" | "exhausted" | "cancelled"
}

export interface DispatchFeedCall {
    id: number
    code?: string
    title: string
    priority: number
    icon?: string
    createdAt: number
    expiresAt: number
    closedAt?: number
    data?: { street?: unknown }
    units: { src: number; state: "en_route" | "on_scene" | "clear" }[]
}
export interface DispatchFeedPayload {
    now: number
    calls: DispatchFeedCall[]
    selected?: number
    hidden: boolean
    me?: { src: number }
    config?: {
        feed?: { maxVisible?: number; position?: string }
        priorities?: Record<string, { label: string; color: string }> | { label: string; color: string }[]
    }
    keybinds: { previous: string; next: string; respond: string; toggle: string; tablet: string }
    theme?: Record<string, string>
}

export interface InstructionalRow {
    label: string
    keys: string[]
}
export interface InstructionalPayload {
    buttons: InstructionalRow[]
}
