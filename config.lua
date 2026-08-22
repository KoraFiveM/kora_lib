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
    selectControls = { 38, 18 }, -- E, Enter
    cancelControls = { 322, 177, 200 }, -- Escape, Backspace, Pause
}

Config.callback = {
    timeout = 10000, -- ms a QB.callback.trigger() request (either direction) waits before rejecting
}

Config.cache = {
    tickInterval = 100, -- ms Wait() between QB.cache ped/vehicle/seat/weapon refreshes; 0 = every frame
}

Config.notify = {
    defaultDuration = 5000,       -- ms a notification stays visible when `duration` isn't given
    maxDuration = 120000,         -- ms; the hard ceiling QB.notify.assert() enforces
    defaultType = "info",         -- "info" | "success" | "warning" | "error"
    defaultPosition = "top-right",-- "top-left" | "top-center" | "top-right" | "bottom-left" | "bottom-center" | "bottom-right"
}

Config.blips = {
    defaultSprite = 1,       -- default SetBlipSprite when options.sprite is omitted
    defaultColor = 0,        -- default SetBlipColour when options.color is omitted
    defaultScale = 1.0,      -- default SetBlipScale when options.scale is omitted
    defaultShortRange = true,-- default SetBlipAsShortRange when options.shortRange is omitted
}

Config.progressbar = {
    maxDuration = 600000, -- ms; the hard ceiling QB.progressbar.start() enforces (10 minutes)
    cancelControl = 73,   -- control id checked when payload.canCancel is true -- 73 = INPUT_VEH_EXIT, the "X" key
}

Config.world = {
    defaultRadius = 50.0, -- meters; QB.world.getClosestEntity's search radius when options.radius is omitted
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

Config.zones = {
    gridSize = 50,               -- meters per grid cell (horizontal XY)
    nearProximity = 25,          -- meters; base "near" threshold before speed correction
    speedSafetyFactor = 1.5,     -- widens "near" for fast-moving entities so tickFar can't skip a small zone
    tickFar = 1000,              -- ms Wait() when nothing is near
    tickNear = 200,              -- ms Wait() when near/inside without an active `inside` callback
    tickInside = 0,              -- ms Wait() while inside a zone with an `inside` callback
    defaultPointRadius = 1.0,    -- meters; QB.zones.point() default
    defaultPolyThickness = 4.0,  -- meters; QB.zones.poly() default height band
    debugColor = { r = 255, g = 0, b = 0, a = 200 }, -- alpha bumped from 100: was easy to lose against terrain at the old value
    debugWallAlpha = 40,         -- 0-255; translucent fill for box/poly walls, deliberately lower than debugColor.a so it doesn't bury the wireframe it complements

    creator = {
        raycastDistance = 50.0,  -- meters; max distance a placement raycast will reach
        defaultBoxSize = 4.0,    -- meters; starting X/Y size for a new box, before scroll-adjustment
        defaultBoxHeight = 3.0,  -- meters; starting Z size for a new box
        defaultRadius = 3.0,     -- meters; starting radius for a new sphere
        defaultThickness = 4.0,  -- meters; starting height band for a new poly
        sizeStep = 0.25,         -- meters per scroll tick when adjusting size/height/radius/thickness
        rotationStep = 5.0,      -- degrees per scroll tick when adjusting box rotation
        shiftMultiplier = 2.5,   -- multiplies sizeStep/rotationStep while Shift is held, for faster adjustment
        maxPolyPoints = 64,      -- hard cap so placement can't run away
        confirmTimeout = 120000, -- ms the confirm dialog waits for a response before the promise rejects
        hideRadar = true,        -- hide the minimap while placing, so it can't cover the shape you're drawing
        enabled = true,          -- set false to disable QB.zones.startCreator()/`/qb_zonecreator` server-wide
    },
}

Config.minigames = {
    sessionTTL = 60000,          -- ms; server-side session expiry, checked on every submit and swept every 30s
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
}
