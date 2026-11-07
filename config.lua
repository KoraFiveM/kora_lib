Config = {}

Config.third_party_notify = false

Config.nui = {
    -- Kora.nui.copyToClipboard may take a brief cursor-less NUI focus lease while the browser copies.
    -- CEF execCommand copy can return false without document focus. Set false to never take focus.
    clipboardFocus = true,
    -- true: copy without focus first (like ox_lib) and take the lease above only for one retry
    -- when the browser refuses. false: take the lease for every copy (the old behaviour).
    clipboardUnfocusedFirst = true,
}

Config.ui = {
    interact = true, -- set false to disable the kora_lib interact-zone module entirely
    apps = {
        -- Apps opt in with draggable = true in Kora.nui.registerApp (plus rememberPosition / positionKey).
        -- true: every app that does not set draggable itself becomes draggable by its header. Default false.
        draggableDefault = false,
    },
}

-- Output ceiling for screenshot capture, so ultrawide/4K clients don't allocate a second full-res
-- frame buffer. Set either limit to false to leave that dimension unbounded.
Config.screenshot = {
    debugConvar = 'kora_lib_screenshot_debug',
    defaultEncoding = 'jpg',
    defaultQuality = 0.92,
    maxWidth = 1920,
    maxHeight = 1080,
    requestTimeout = 30000,
    uploadBytesPerSecond = 2 * 1024 * 1024,
    maxBytes = 12 * 1024 * 1024,
}

-- Controls are consumed only while a kora_lib interact selector is visible.
-- Keeping them here makes the gameplay-side interaction rebindable without
-- changing the NUI, which remains a pointer-transparent display layer.
Config.interact = {
    previousControls = { 27, 15 }, -- INPUT_PHONE / Up, INPUT_WEAPON_WHEEL_PREV / Mouse wheel up
    nextControls = { 173, 14 }, -- INPUT_CELLPHONE_DOWN / Down, INPUT_WEAPON_WHEEL_NEXT / Mouse wheel down
    selectControls = { 38, 24 }, -- INPUT_PICKUP / E, INPUT_ATTACK / Left mouse button
    cancelControls = { 322, 177, 200 }, -- Escape, Backspace, Pause
}

Config.callback = {
    -- ms a Kora.callback.trigger() request waits before rejecting. Must cover the WORST client
    -- (a cold, still-joining machine answers slowly) since a timeout looks like a refusal at the call site.
    timeout = 30000,
}

Config.cache = {
    -- 5Hz is enough for HUD/distance helpers. Never set to 0: this is telemetry, not a per-frame loop.
    tickInterval = 200,
}

Config.notify = {
    defaultDuration = 5000,       -- ms a notification stays visible when `duration` isn't given
    maxDuration = 120000,         -- ms; the hard ceiling Kora.notify.assert() enforces
    defaultType = "info",         -- "info" | "success" | "warning" | "error"
    defaultPosition = "top-right",-- "top-left" | "top-center" | "top-right" | "bottom-left" | "bottom-center" | "bottom-right"
}

Config.sound = {
    -- ms before a Kora.sound-allocated sound id is auto-released. The id pool is small and finite;
    -- long looping sounds should pass `releaseAfter` (0 opts out; call Kora.sound.stop yourself).
    defaultReleaseAfter = 10000,
    defaultRange = 30.0, -- metres; audible range for Kora.sound.playFromCoords when `range` is omitted
}

Config.blips = {
    defaultSprite = 1,       -- default SetBlipSprite when options.sprite is omitted
    defaultColor = 0,        -- default SetBlipColour when options.color is omitted
    defaultScale = 1.0,      -- default SetBlipScale when options.scale is omitted
    defaultShortRange = true,-- default SetBlipAsShortRange when options.shortRange is omitted
    defaultDisplay = 4,      -- restored after a player shows a hidden blip/category

    -- Category 2 lists every blip as its own row in the pause-map legend (no grouping).
    -- Kept as a numeric compat value; new code should pass a catalogue name (omission uses Other, 12).
    listedCategory = 2,
    -- Compat alias; category 2 is a list, not a collapsible group.
    groupedCategory = 2,

    -- GTA's range for named custom legend categories. kora_lib's fixed catalogue
    -- in modules/blips/shared.lua uses ids from this range.
    namedCategoryStart = 12,
    namedCategoryEnd = 133,

    -- Custom pause-map detail card (Kora.blips create/setInfo `info`).
    -- Selecting an entry in the pause-map legend reports the same highlighted blip as hovering
    -- it on the map, for a few frames, while the map pans. The card shares frontend column 1
    -- with the legend, so drawing then shows an unpositioned panel in the top-left corner.
    info = {
        -- false: draw the card only for a genuine map hover (see the options below).
        -- true: draw it for any highlighted blip, legend selections included. The stable-hover
        -- delay and frontend-ready checks still apply.
        showOnLegendSelect = false,
        -- ms the cursor must stay on the same blip (unbroken) before its card is first drawn.
        -- Filters out the few-frame blip report of a legend click. 0 draws immediately.
        hoverStableMs = 120,
        -- Require GetPauseMenuState() == PM_READY (15) besides IsPauseMenuActive,
        -- IsFrontendReadyForControl and not IsPauseMenuRestarting.
        requirePauseReady = true,
        -- Treat IsNavigatingMenuContent() as legend focus (keyboard/gamepad/mouse navigation of
        -- the legend). Set false if it also reports true during plain map hover on your build.
        blockWhileNavigatingContent = true,
        -- ms to hold the card back after each pause-menu layout-changed event (list navigation,
        -- which is what a legend selection raises). 0 disables the event check.
        legendSuppressMs = 400,
        -- Fallback only: with the mouse as active input, a cursor X (0-1) at or right of this
        -- counts as over the legend. false/0 disables it.
        legendMinX = 0.66,
        -- Call SHOW_COLUMN(1, true) while the card renders. The game script, not the engine, makes
        -- this column visible for creator blips, so the default is true. Set false to rely on
        -- the game having shown the column itself. kora_lib never calls SHOW_COLUMN(1, false).
        forceShowColumn = true,
    },
}

Config.progressbar = {
    maxDuration = 600000, -- ms; the hard ceiling Kora.progressbar.start() enforces (10 minutes)
    maxProps = 2,         -- maximum number of local cosmetic props one progress bar may attach
    cancelControls = { 73, 322 }, -- checked when payload.canCancel is true -- X and Escape by default
    -- How disable.move is enforced when the payload sets no disable.moveMode.
    --   'controls' (default): only the movement controls are disabled; the ped is never
    --     FreezeEntityPosition'd, so a player who triggers a bar from a third-eye/target option
    --     while walking glides to a stop instead of locking solid like an admin freeze.
    --   'freeze': legacy behaviour, FreezeEntityPosition for the duration (still skipped while
    --     the ped is falling, jumping, ragdolling or otherwise airborne, where it falls back to 'controls').
    -- A payload's own disable.moveMode always wins over this.
    defaultMoveMode = 'controls',
    -- rem from the bottom of the screen for the bar (and the circle's 'bottom' position). 10 keeps it
    -- above kora_hud's vitals row, whose NUI frame draws over kora_lib's. The old spot was 6.
    bottomOffset = 10,
}

-- Built-in wheel content for compat/client/qb-radialmenu.lua, ported from upstream qb-radialmenu's
-- default job/vehicle menus so the wheel isn't empty without it.
Config.radialmenuCompat = {
    enableVehicleExtras = true, -- mirrors real qb-radialmenu's Config.EnableExtraMenu
    flipVehicleTime = 15000,    -- ms; mirrors real qb-radialmenu's Config.Fliptime

    -- Per-job "Work" submenu entries keyed by job name (or job `type` for 'leo'), shown only while on duty.
    -- Upstream entries that fire companion-resource events or need a target player are omitted
    -- (dead buttons here); only entries with a self-contained handler on this server are wired.
    jobInteractions = {
        ambulance = {
            { id = 'statuscheck', title = 'Check Health Status', type = 'client', event = 'hospital:client:CheckStatus', shouldClose = true },
            { id = 'revivep', title = 'Revive', type = 'client', event = 'hospital:client:RevivePlayer', shouldClose = true },
            { id = 'treatwounds', title = 'Heal Wounds', type = 'client', event = 'hospital:client:TreatWounds', shouldClose = true },
            -- Upstream's emergency button fires 'police:client:SendPoliceEmergencyAlert', which kora_police
            -- doesn't implement; use its on-duty-gated `/backup` command via `type = 'command'` instead.
            { id = 'emergencybutton2', title = 'Request Backup', type = 'command', event = 'backup', shouldClose = true },
        },
        police = {
            { id = 'emergencybutton', title = 'Request Backup', type = 'command', event = 'backup', shouldClose = true },
        },
    },
}

Config.world = {
    defaultRadius = 50.0, -- meters; Kora.world.getClosestEntity's search radius when options.radius is omitted
    groundHeight = 1000.0, -- starting Z used by Kora.world.getGroundCoords when no explicit options.height is supplied
    groundAttempts = 20, -- bounded collision/ground probes before getGroundCoords reports failure
    groundRetryDelay = 50, -- milliseconds between ground probes
}

Config.teleport = {
    fadeTime = 500,
    waypointLaunchHeight = 1000.0,
    waypointCollisionTimeout = 2000,
    waypointGroundAttempts = 20,
    waypointGroundRetryDelay = 50,
}

Config.drawing = {
    text3d = {
        font = 4,
        scale = 0.35,
        color = { r = 255, g = 255, b = 255, a = 215 },
        maxDistance = 10.0, -- meters from PlayerPedId(); beyond this Kora.drawing.text3d skips every native call
        outline = true,
    },
}

-- Permission-gated convenience commands for the built-in developer editors.
-- This keeps the normal server UX admin-only; a modified client can still
-- call client-side library functions, so gameplay resources must never treat
-- this gate as an authorization boundary for persistent changes.
Config.editor = {
    enabled = true,
    permission = 'editor',
    permissionPrefix = 'kora_lib',
    zoneCommand = 'qb_zonecreator',
    placementCommand = 'qb_place',
}

-- Temporary client-side entity placement/capture tool. The preview is always
-- deleted when the session finishes; these values only control the editor UX.
Config.placement = {
    enabled = true,
    raycastDistance = 50.0,
    moveSpeed = 1.0,             -- metres/second while an arrow/Page key is held
    rotationSpeed = 45.0,        -- degrees/second while [ or ] is held
    shiftMultiplier = 2.5,       -- fast movement/rotation/freecam multiplier
    cameraMoveSpeed = 6.0,       -- metres/second for the scripted freecam
    cameraLookSensitivity = 5.0, -- degrees per raw mouse-look unit
    cameraTransitionMs = 800,
    previewAlpha = 180,          -- 0-255; translucent enough to read against the world
    confirmTimeout = 120000,
    hudUpdateInterval = 100,     -- ms; caps live coordinate/rotation NUI updates at 10Hz
    hideRadar = true,
    hideHud = true,              -- hide the kora_hud vitals/job/bank/voice HUD while a placement session is active, restoring it afterwards
}

Config.freecam = {
    freezePlayer = true,   -- default for Kora.freecam.start({ freezePlayer }); never freezes a falling/jumping/ragdolling/airborne ped
    cameraMoveSpeed = 6.0,
    cameraLookSensitivity = 5.0,
    shiftMultiplier = 2.5,
    cameraTransitionMs = 800,
}

Config.zones = {
    gridSize = 50,               -- meters per grid cell (horizontal XY)
    nearProximity = 25,          -- meters; base "near" threshold before speed correction
    speedSafetyFactor = 1.5,     -- widens "near" for fast-moving entities so tickFar can't skip a small zone
    tickFar = 1000,              -- ms Wait() when nothing is near
    tickNear = 200,              -- ms Wait() when near/inside without an active `inside` callback
    tickInside = 0,              -- ms Wait() while inside a zone with an `inside` callback
    defaultPointRadius = 1.0,    -- meters; Kora.zones.point() default
    defaultPolyThickness = 4.0,  -- meters; Kora.zones.poly() default height band
    debugAlpha = 200, -- 0-255; colour follows kora_theme's configured primary through Kora.theme.accentColor()
    debugWallAlpha = 40,         -- 0-255; translucent fill for box/poly walls, deliberately lower than debugAlpha so it doesn't bury the wireframe it complements
    debug = false, -- global default OR'd into every zone's own opts.debug at creation (Kora.zones.setDebug can still flip debug on/off for already-created zones at runtime)

    creator = {
        raycastDistance = 50.0,  -- meters; max distance a placement raycast will reach
        cameraMoveSpeed = 6.0,        -- meters/second the creator's scripted camera flies at (before the Shift boost)
        cameraLookSensitivity = 5.0,  -- degrees per raw mouse-look unit while flying the creator's camera
        cameraTransitionMs = 800,     -- ms to smoothly blend the gameplay camera into the creator's scripted camera, and back on exit
        defaultBoxSize = 4.0,    -- meters; starting X/Y size for a new box, before scroll-adjustment
        defaultBoxHeight = 3.0,  -- meters; starting Z size for a new box
        defaultRadius = 3.0,     -- meters; starting radius for a new sphere
        defaultThickness = 4.0,  -- meters; starting height band for a new poly
        sizeStep = 0.25,         -- meters per scroll tick when adjusting size/height/radius/thickness
        rotationStep = 5.0,      -- degrees per scroll tick when adjusting box rotation
        shiftMultiplier = 2.5,   -- multiplies sizeStep/rotationStep/cameraMoveSpeed while Shift is held, for faster adjustment/flying
        maxPolyPoints = 64,      -- hard cap so placement can't run away
        confirmTimeout = 120000, -- ms the confirm dialog waits for a response before the promise rejects
        hideRadar = true,        -- hide the minimap while placing, so it can't cover the shape you're drawing
        hideHud = true,          -- hide kora_hud (vitals, job/bank, voice) while the creator is open, so it can't overlap the control prompts
        enabled = true,          -- set false to disable Kora.zones.startCreator()/`/qb_zonecreator` server-wide
    },
}

Config.minigames = {
    sessionTTL = 60000,          -- ms; minimum abandoned-round lifetime and bounded overall-session cleanup grace
    authorizationTTL = 60000,    -- ms a server-issued, resource-owned proof authorization remains usable to start a session
    proofTTL = 15000,            -- ms a successful single-use proof remains consumable by a server gameplay resource
    maxConcurrentPerPlayer = 1,  -- max simultaneous Kora.minigames.play() sessions per player, server-enforced
    maxAttemptsCap = 10,         -- hard ceiling on opts.attempts, regardless of per-type default or client override
    roundTimeoutBuffer = 5000,   -- ms added to a round's timeLimit for the client-side NUI request timeout (safety net -- the NUI is expected to auto-submit on its own clock well before this)

    -- Hard byte/count bounds for caller/client-provided puzzle content and
    -- attempt arrays. These cap server work and NUI payload size; they are
    -- intentionally not overridable per play call.
    inputLimits = {
        pinSourceBytes = 32,
        pinDigits = 8,
        quizQuestions = 20,
        quizOptionsPerQuestion = 8,
        quizQuestionBytes = 512,
        quizOptionBytes = 128,
        wordGuessBytes = 32,
        wordScrambleBytes = 64,
        hintBytes = 256,
    },

    -- Per-player callback quotas. The shared callback layer enforces these
    -- before a minigame handler allocates, validates, or regenerates state.
    callbackRateLimits = {
        start = { max = 5, window = 10000 },
        submit = { max = 20, window = 10000 },
        cancel = { max = 10, window = 10000 },
    },

    lockpick = {
        attempts = 3,
        pinCount = 4,
        tolerance = 0.08,    -- +/- around each pin's target, 0..1 scale
        speed = 1.4,         -- triangle-wave cycles per second
        timeLimit = 8000,    -- ms for the whole round
        minTimePerPin = 150, -- ms; anti-cheat floor between two pin presses, not client-adjustable
    },
    skillbar = {
        attempts = 3,
        zoneSize = 0.14,        -- width of the target zone, 0..1 scale
        speed = 1.0,            -- triangle-wave cycles per second
        timeLimit = 5000,       -- ms for the whole round
        minReactionTime = 80,   -- ms; anti-cheat floor on the reported press elapsed time, not client-adjustable
    },
    circuit = {
        attempts = 3,
        nodeCount = 4,               -- input/output pairs; capped by the color palette in modules/minigames/server.lua
        timeLimit = 15000,           -- ms for the whole round
        minTimePerConnection = 300,  -- ms; anti-cheat floor between two connections, not client-adjustable
    },
    mash = {
        attempts = 3,
        requiredPresses = 20,
        timeLimit = 4000,       -- ms for the whole round
        minPressInterval = 60,  -- ms; anti-cheat floor between two presses, not client-adjustable
    },
    fishing = {
        attempts = 2,
        games = 3,              -- number of bite games in one round, 1..3
        zoneSize = 0.18,        -- height of each catch window, 0..1 scale
        speed = 0.85,            -- triangle-wave cycles per second
        timeLimit = 9000,        -- ms for the whole round
        minReelInterval = 250,   -- ms; anti-cheat floor between reel inputs
    },

    -- The six types below back the qb-minigames compat shim (compat/client/qb-minigames.lua).
    -- Their puzzle CONTENT (PIN, word, quiz questions) comes from the caller via opts;
    -- these blocks only cover attempts/timing/anti-cheat defaults.
    pinpad = {
        attempts = 1,
        digits = 4,             -- PIN length when opts.numbers isn't provided
        timeLimit = 15000,      -- ms for the whole round
        minTimePerDigit = 200,  -- ms; anti-cheat floor between two digit entries, not client-adjustable
    },
    quiz = {
        attempts = 1,
        correctRequired = 1,
        timePerQuestion = 15000,  -- ms per question, used as the default per-question/whole-quiz time budget
        minTimePerAnswer = 300,   -- ms; anti-cheat floor between two answers, not client-adjustable
    },
    wordguess = {
        attempts = 1,
        guesses = 5,
        timeLimit = 60000,       -- ms for the whole round
        minTimePerGuess = 200,   -- ms; anti-cheat floor between two letter guesses, not client-adjustable
    },
    wordscramble = {
        attempts = 1,
        timeLimit = 30000,      -- ms for the whole round
        minSubmitTime = 300,    -- ms; anti-cheat floor on the reported submit elapsed time, not client-adjustable
    },
    keys = {
        attempts = 1,           -- upstream's KeyMinigame always runs to completion once, never retries
        amount = 10,
        perKeyWindow = 1500,    -- ms allotted per prompt (mirrors upstream's 1500ms cadence); timeLimit = amount * this
        minTimePerPress = 100,  -- ms; anti-cheat floor between two presses, not client-adjustable
    },
    hacking = {
        attempts = 1,           -- upstream's Hacking is a single pass/fail against a countdown, not a multi-attempt puzzle
        solutionsize = 5,       -- hex characters in the code to find
        timeout = 30,           -- seconds
        minTimePerFind = 400,   -- ms; anti-cheat floor on the reported submit elapsed time, not client-adjustable
    },
}
