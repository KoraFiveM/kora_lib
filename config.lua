Config = {}

Config.third_party_notify = false

Config.nui = {
    clipboardFocus = true,
    clipboardUnfocusedFirst = true,
}

Config.ui = {
    interact = true,
    apps = {
        draggableDefault = false,
    },
}

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

Config.interact = {
    previousControls = { 27, 15 },
    nextControls = { 173, 14 },
    selectControls = { 38, 24 },
    cancelControls = { 322, 177, 200 },
}

Config.callback = {
    timeout = 30000,
}

Config.cache = {
    tickInterval = 200,
}

Config.notify = {
    defaultDuration = 5000,
    maxDuration = 120000,
    defaultType = "info",
    defaultPosition = "top-right",
}

Config.sound = {
    defaultReleaseAfter = 10000,
    defaultRange = 30.0,
}

Config.blips = {
    defaultSprite = 1,
    defaultColor = 0,
    defaultScale = 1.0,
    defaultShortRange = true,
    defaultDisplay = 4,

    listedCategory = 2,
    groupedCategory = 2,

    namedCategoryStart = 12,
    namedCategoryEnd = 133,

    info = {
        showOnLegendSelect = false,
        hoverStableMs = 120,
        requirePauseReady = true,
        blockWhileNavigatingContent = true,
        legendSuppressMs = 400,
        legendMinX = 0.66,
        forceShowColumn = true,
    },
}

Config.progressbar = {
    maxDuration = 600000,
    maxProps = 2,
    cancelControls = { 73, 322 },
    defaultMoveMode = 'controls',
    bottomOffset = 10,
}

Config.radialmenuCompat = {
    enableVehicleExtras = true,
    flipVehicleTime = 15000,

    jobInteractions = {
        ambulance = {
            { id = 'statuscheck', title = 'Check Health Status', type = 'client', event = 'hospital:client:CheckStatus', shouldClose = true },
            { id = 'revivep', title = 'Revive', type = 'client', event = 'hospital:client:RevivePlayer', shouldClose = true },
            { id = 'treatwounds', title = 'Heal Wounds', type = 'client', event = 'hospital:client:TreatWounds', shouldClose = true },
            { id = 'emergencybutton2', title = 'Request Backup', type = 'command', event = 'backup', shouldClose = true },
        },
        police = {
            { id = 'emergencybutton', title = 'Request Backup', type = 'command', event = 'backup', shouldClose = true },
        },
    },
}

Config.world = {
    defaultRadius = 50.0,
    groundHeight = 1000.0,
    groundAttempts = 20,
    groundRetryDelay = 50,
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
        maxDistance = 10.0,
        outline = true,
    },
}

Config.editor = {
    enabled = true,
    permission = 'editor',
    permissionPrefix = 'kora_lib',
    zoneCommand = 'qb_zonecreator',
    placementCommand = 'qb_place',
}

Config.placement = {
    enabled = true,
    raycastDistance = 50.0,
    moveSpeed = 1.0,
    rotationSpeed = 45.0,
    shiftMultiplier = 2.5,
    cameraMoveSpeed = 6.0,
    cameraLookSensitivity = 5.0,
    cameraTransitionMs = 800,
    previewAlpha = 180,
    confirmTimeout = 120000,
    hudUpdateInterval = 100,
    hideRadar = true,
    hideHud = true,
}

Config.freecam = {
    freezePlayer = true,
    cameraMoveSpeed = 6.0,
    cameraLookSensitivity = 5.0,
    shiftMultiplier = 2.5,
    cameraTransitionMs = 800,
}

Config.zones = {
    gridSize = 50,
    nearProximity = 25,
    speedSafetyFactor = 1.5,
    tickFar = 1000,
    tickNear = 200,
    tickInside = 0,
    defaultPointRadius = 1.0,
    defaultPolyThickness = 4.0,
    debugAlpha = 200,
    debugWallAlpha = 40,
    debug = false,

    creator = {
        raycastDistance = 50.0,
        cameraMoveSpeed = 6.0,
        cameraLookSensitivity = 5.0,
        cameraTransitionMs = 800,
        defaultBoxSize = 4.0,
        defaultBoxHeight = 3.0,
        defaultRadius = 3.0,
        defaultThickness = 4.0,
        sizeStep = 0.25,
        rotationStep = 5.0,
        shiftMultiplier = 2.5,
        maxPolyPoints = 64,
        confirmTimeout = 120000,
        hideRadar = true,
        hideHud = true,
        enabled = true,
    },
}

Config.minigames = {
    sessionTTL = 60000,
    authorizationTTL = 60000,
    proofTTL = 15000,
    maxConcurrentPerPlayer = 1,
    maxAttemptsCap = 10,
    roundTimeoutBuffer = 5000,

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

    callbackRateLimits = {
        start = { max = 5, window = 10000 },
        submit = { max = 20, window = 10000 },
        cancel = { max = 10, window = 10000 },
    },

    lockpick = {
        attempts = 3,
        pinCount = 4,
        tolerance = 0.08,
        speed = 1.4,
        timeLimit = 8000,
        minTimePerPin = 150,
    },
    skillbar = {
        attempts = 3,
        zoneSize = 0.14,
        speed = 1.0,
        timeLimit = 5000,
        minReactionTime = 80,
    },
    circuit = {
        attempts = 3,
        nodeCount = 4,
        timeLimit = 15000,
        minTimePerConnection = 300,
    },
    mash = {
        attempts = 3,
        requiredPresses = 20,
        timeLimit = 4000,
        minPressInterval = 60,
    },
    fishing = {
        attempts = 2,
        games = 3,
        zoneSize = 0.18,
        speed = 0.85,
        timeLimit = 9000,
        minReelInterval = 250,
    },

    pinpad = {
        attempts = 1,
        digits = 4,
        timeLimit = 15000,
        minTimePerDigit = 200,
    },
    quiz = {
        attempts = 1,
        correctRequired = 1,
        timePerQuestion = 15000,
        minTimePerAnswer = 300,
    },
    wordguess = {
        attempts = 1,
        guesses = 5,
        timeLimit = 60000,
        minTimePerGuess = 200,
    },
    wordscramble = {
        attempts = 1,
        timeLimit = 30000,
        minSubmitTime = 300,
    },
    keys = {
        attempts = 1,
        amount = 10,
        perKeyWindow = 1500,
        minTimePerPress = 100,
    },
    hacking = {
        attempts = 1,
        solutionsize = 5,
        timeout = 30,
        minTimePerFind = 400,
    },
}
