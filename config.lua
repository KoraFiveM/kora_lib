Config = {}

Config.third_party_notify = false

-- Shared NUI branding. This must be a six-digit hex colour; the browser
-- derives hover, pressed, soft, border, and focus tokens from this one value.
Config.ui = {
    accentColor = "#DC143C", -- QBCore crimson; e.g. "#7C3AED" for a server-specific brand
    interact = true, -- set false to disable the qblib interact-zone module entirely
}

-- Controls are consumed only while a qblib interact selector is visible.
-- Keeping them here makes the gameplay-side interaction rebindable without
-- changing the NUI, which remains a pointer-transparent display layer.
Config.interact = {
    previousControls = { 27 }, -- INPUT_PHONE / Up
    nextControls = { 173 }, -- INPUT_CELLPHONE_DOWN / Down
    selectControls = { 38 }, -- INPUT_PICKUP / E
    cancelControls = { 322, 177, 200 }, -- Escape, Backspace, Pause
}

Config.callback = {
    timeout = 10000, -- ms a QB.callback.trigger() request (either direction) waits before rejecting
}

Config.discord = {
    roleSyncInterval = 300000, -- ms; refresh the guild role catalog and every online player's roles (5 minutes)
    cacheMaxAge = 600000,      -- ms; hasRole/hasRoles fail closed once a member snapshot is older than this
    databaseTimeout = 60000,   -- ms to wait for optional qbsql before continuing with memory-only caching
}

Config.cache = {
    -- 5Hz keeps HUD health/armour/stamina and local distance helpers feeling
    -- immediate, while halving the shared native/cache work previously done
    -- at 10Hz. Never set this to 0: the cache is deliberately telemetry, not
    -- a per-frame game-control loop.
    tickInterval = 200,
}

Config.notify = {
    defaultDuration = 5000,       -- ms a notification stays visible when `duration` isn't given
    maxDuration = 120000,         -- ms; the hard ceiling QB.notify.assert() enforces
    defaultType = "info",         -- "info" | "success" | "warning" | "error"
    defaultPosition = "top-right",-- "top-left" | "top-center" | "top-right" | "bottom-left" | "bottom-center" | "bottom-right"
}

Config.sound = {
    -- ms before a sound id allocated by QB.sound is automatically released.
    -- GTA's sound-id pool is small and finite, so an id that is never released
    -- permanently reduces how many sounds the client can play at once. Ten
    -- seconds comfortably outlives every alert tone and UI blip; a longer
    -- looping sound should pass an explicit `releaseAfter` (or 0 to opt out
    -- and call QB.sound.stop itself).
    defaultReleaseAfter = 10000,
    defaultRange = 30.0, -- metres; audible range for QB.sound.playFromCoords when `range` is omitted
}

Config.blips = {
    defaultSprite = 1,       -- default SetBlipSprite when options.sprite is omitted
    defaultColor = 0,        -- default SetBlipColour when options.color is omitted
    defaultScale = 1.0,      -- default SetBlipScale when options.scale is omitted
    defaultShortRange = true,-- default SetBlipAsShortRange when options.shortRange is omitted
}

Config.progressbar = {
    maxDuration = 600000, -- ms; the hard ceiling QB.progressbar.start() enforces (10 minutes)
    maxProps = 2,         -- maximum number of networked props one progress bar may attach
    cancelControl = 73,   -- control id checked when payload.canCancel is true -- 73 = INPUT_VEH_EXIT, the "X" key
}

-- compat/client/qb-radialmenu.lua's built-in wheel content -- the same
-- categories real qbcore-framework/qb-radialmenu injects into every player's
-- wheel by default (SetupJobMenu/SetupVehicleMenu in its main.lua), ported
-- here so a server pairing qblib's compat with no qb-radialmenu installed
-- still sees the same default content, not an empty wheel.
Config.radialmenuCompat = {
    enableVehicleExtras = true, -- mirrors real qb-radialmenu's Config.EnableExtraMenu
    flipVehicleTime = 15000,    -- ms; mirrors real qb-radialmenu's Config.Fliptime

    -- Per-job "Work" submenu entries, keyed by job name (or job `type` for
    -- 'leo' jobs, matching real qb-radialmenu's own JobInteractionCheck
    -- override -- see compat/client/qb-radialmenu.lua's setupJobMenu). Only
    -- shown while the player is on duty in that job, exactly like upstream.
    --
    -- Real qb-radialmenu's own default Config.JobInteractions ships entries
    -- for ambulance/police/tow/taxi/mechanic/hotdog, but every one of those
    -- (besides the ambulance actions below) fires an event owned by a
    -- COMPANION job resource (qb-ambulancejob, qb-policejob, qb-tow,
    -- qb-taxi, qb-tunerchip, qb-houses, qb-hotdogjob) or requires the wheel
    -- to know an aimed-at/nearby TARGET player (search/escort/jail/seize
    -- license) that the wheel's own event payload never carries -- copying
    -- those in verbatim would just be dead buttons against resources this
    -- server doesn't run, or against ones (qbambulance/qbpolice) that
    -- implement the equivalent action under a different, non-parameterless
    -- shape. Only entries verified to have a real, self-contained handler in
    -- THIS server's own resources are wired up below; add your own the same
    -- way for any other job.
    jobInteractions = {
        ambulance = {
            { id = 'statuscheck', title = 'Check Health Status', type = 'client', event = 'hospital:client:CheckStatus', shouldClose = true },
            { id = 'revivep', title = 'Revive', type = 'client', event = 'hospital:client:RevivePlayer', shouldClose = true },
            { id = 'treatwounds', title = 'Heal Wounds', type = 'client', event = 'hospital:client:TreatWounds', shouldClose = true },
            -- Real upstream's ambulance/police "Emergency button" entries both
            -- fire 'police:client:SendPoliceEmergencyAlert', which this
            -- server's qbpolice doesn't implement -- qbpolice's own real
            -- equivalent is the self-contained, on-duty-gated `/backup`
            -- command (client/dispatch.lua), fired here via `type =
            -- 'command'` (a real qb-radialmenu dispatch type -- see
            -- ExecuteCommand(data.event) in its own selectItem callback).
            { id = 'emergencybutton2', title = 'Request Backup', type = 'command', event = 'backup', shouldClose = true },
        },
        police = {
            { id = 'emergencybutton', title = 'Request Backup', type = 'command', event = 'backup', shouldClose = true },
        },
    },
}

Config.world = {
    defaultRadius = 50.0, -- meters; QB.world.getClosestEntity's search radius when options.radius is omitted
    groundHeight = 1000.0, -- starting Z used by QB.world.getGroundCoords when no explicit options.height is supplied
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
        maxDistance = 10.0, -- meters from PlayerPedId(); beyond this QB.drawing.text3d skips every native call
        outline = true,
    },
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
}

Config.zones = {
    gridSize = 50,               -- meters per grid cell (horizontal XY)
    nearProximity = 25,          -- meters; base "near" threshold before speed correction
    speedSafetyFactor = 1.5,     -- widens "near" for fast-moving entities so tickFar can't skip a small zone
    tickFar = 1000,              -- ms Wait() when nothing is near
    tickNear = 200,              -- ms Wait() when near/inside without an active `inside` callback
    tickInside = 0,              -- ms Wait() while inside a zone with an `inside` callback
    defaultPointRadius = 1.0,    -- meters; QB.zones.point() default
    defaultPolyThickness = 4.0,  -- meters; QB.zones.poly() default height band
    debugAlpha = 200, -- 0-255; wireframe/marker alpha for debug zones and the creator's live preview (colour itself follows QB.theme.accentColor(), not a fixed value)
    debugWallAlpha = 40,         -- 0-255; translucent fill for box/poly walls, deliberately lower than debugAlpha so it doesn't bury the wireframe it complements
    debug = false, -- global default OR'd into every zone's own opts.debug at creation (QB.zones.setDebug can still flip debug on/off for already-created zones at runtime)

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
        enabled = true,          -- set false to disable QB.zones.startCreator()/`/qb_zonecreator` server-wide
    },
}

Config.minigames = {
    sessionTTL = 60000,          -- ms; server-side session expiry, checked on every submit and swept every 30s
    proofTTL = 15000,            -- ms a successful single-use proof remains consumable by a server gameplay resource
    maxConcurrentPerPlayer = 1,  -- max simultaneous QB.minigames.play() sessions per player, server-enforced
    maxAttemptsCap = 10,         -- hard ceiling on opts.attempts, regardless of per-type default or client override
    roundTimeoutBuffer = 5000,   -- ms added to a round's timeLimit for the client-side NUI request timeout (safety net -- the NUI is expected to auto-submit on its own clock well before this)

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

    -- The six types below back the qb-minigames compat shim
    -- (compat/client/qb-minigames.lua) -- unlike lockpick/skillbar/circuit/mash,
    -- their puzzle CONTENT (the PIN, the word, the quiz questions) is supplied
    -- by the calling script via opts rather than randomized purely from
    -- config, since that's how the real qb-minigames exports work. These
    -- config blocks only cover attempts/timing/anti-cheat defaults.
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
