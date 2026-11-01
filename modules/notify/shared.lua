---@alias QBNotifyType "info" | "success" | "warning" | "error"
---@alias QBNotifyPosition "top-left" | "top-center" | "top-right" | "bottom-left" | "bottom-center" | "bottom-right" | "center-left" | "center-right" | "top" | "bottom"

---@class QBNotifyPayload
---@field title? string Notification title.
---@field message? string Notification body. At least one of `title` or `message` is required.
---@field duration? integer Milliseconds to display for. Defaults to Config.notify.defaultDuration, must be > 0 and <= Config.notify.maxDuration.
---@field type? QBNotifyType Visual variant (accent colour + icon). Defaults to Config.notify.defaultType.
---@field position? QBNotifyPosition Screen corner/edge to show in. Defaults to Config.notify.defaultPosition.
---@field icon? string Overrides the variant's default icon. A lucide icon name from web/src/lib/icon.ts's curated set; an unknown name renders no icon.
---@field id? string|number Replaces an existing toast with the same id.
---@field iconColor? string CSS colour for the icon.
---@field iconAnimation? 'spin'|'spinPulse'|'spinReverse'|'pulse'|'beat'|'fade'|'beatFade'|'bounce'|'shake'
---@field alignIcon? 'top'|'center' Defaults to center.
---@field style? table<string, any> Trusted scalar root styles and vetted title/description child styles.
---@field showDuration? boolean Set false to hide the lifetime indicator.

-- Validation sets; keep in sync with the aliases above and NotifyPayload in web/src/lib/types.ts.
local NOTIFY_TYPES = {
    info = true,
    success = true,
    warning = true,
    error = true,
}

-- Aliases from other notify APIs (ox_lib's `inform`), resolved by Kora.notify.normalizeType; anything else must be a NOTIFY_TYPES key.
local NOTIFY_TYPE_ALIASES = {
    inform = "info",
    warn = "warning",
}

---Maps a notify type alias (`inform`, `warn`) onto its canonical type; unknown values are returned unchanged for Kora.notify.assert to reject.
---@param notifyType any
---@return any
function Kora.notify.normalizeType(notifyType)
    if type(notifyType) ~= "string" then return notifyType end
    return NOTIFY_TYPE_ALIASES[notifyType] or notifyType
end

---Returns a shallow copy of the payload with its `type` alias resolved; non-table payloads are returned as-is for Kora.notify.assert.
---@param payload QBNotifyPayload
---@return QBNotifyPayload
function Kora.notify.normalize(payload)
    if type(payload) ~= "table" then return payload end
    local canonical = Kora.notify.normalizeType(payload.type)
    if canonical == payload.type then return payload end
    local copy = {}
    for k, v in pairs(payload) do copy[k] = v end
    copy.type = canonical
    return copy
end

local NOTIFY_POSITIONS = {
    ["top-left"] = true,
    ["top-center"] = true,
    ["top-right"] = true,
    ["bottom-left"] = true,
    ["bottom-center"] = true,
    ["bottom-right"] = true,
    ["center-left"] = true,
    ["center-right"] = true,
    top = true,
    bottom = true,
}

local ICON_ANIMATIONS = {
    spin = true,
    spinPulse = true,
    spinReverse = true,
    pulse = true,
    beat = true,
    fade = true,
    beatFade = true,
    bounce = true,
    shake = true,
}

---Validates a notify payload, raising an assertion error if it's malformed.
---@param payload QBNotifyPayload
function Kora.notify.assert(payload)
    assert(type(payload) == "table", "Notify payload must be a table.")

    local title = payload.title
    local message = payload.message
    local duration = payload.duration
    if duration == nil then duration = Config.notify.defaultDuration end

    -- Type-checked: a non-string rendered as a React child would crash the whole NUI root.
    assert(title == nil or type(title) == "string", "Notification title must be a string.")
    assert(message == nil or type(message) == "string", "Notification message must be a string.")
    assert(title or message, "Notifications require a title or message.")
    assert(Kora.util.isInteger(duration), "Duration must be a finite integer.")
    assert(duration > 0, "Duration must be greater than 0.")
    assert(duration <= Config.notify.maxDuration,
        ("Duration must be at most %d ms (Config.notify.maxDuration)."):format(Config.notify.maxDuration))

    assert(payload.type == nil or NOTIFY_TYPES[Kora.notify.normalizeType(payload.type)],
        ("Notification type must be one of info/success/warning/error, got: %s"):format(tostring(payload.type)))
    assert(payload.position == nil or NOTIFY_POSITIONS[payload.position],
        ("Notification position must be one of top/bottom + left/center/right, got: %s"):format(tostring(payload.position)))
    assert(payload.icon == nil or type(payload.icon) == "string", "Notification icon must be a string.")
    assert(payload.id == nil or Kora.util.isFiniteNumber(payload.id) or (type(payload.id) == "string" and payload.id ~= ""),
        "Notification id must be a finite number or non-empty string.")
    assert(payload.iconColor == nil or type(payload.iconColor) == "string", "Notification iconColor must be a string.")
    assert(payload.iconAnimation == nil or ICON_ANIMATIONS[payload.iconAnimation], "Notification iconAnimation is unsupported.")
    assert(payload.alignIcon == nil or payload.alignIcon == "top" or payload.alignIcon == "center",
        "Notification alignIcon must be top or center.")
    assert(payload.style == nil or type(payload.style) == "table", "Notification style must be a table.")
    assert(payload.showDuration == nil or type(payload.showDuration) == "boolean", "Notification showDuration must be a boolean.")
end

---Fills in configured defaults so the NUI always receives a resolved `type`/`position`.
---@param payload QBNotifyPayload
---@return QBNotifyPayload resolved A copy; the caller's table is never mutated.
function Kora.notify.withDefaults(payload)
    local duration = payload.duration
    if duration == nil then duration = Config.notify.defaultDuration end
    local notifyType = Kora.notify.normalizeType(payload.type)
    if notifyType == nil then notifyType = Config.notify.defaultType end
    local position = payload.position
    if position == nil then position = Config.notify.defaultPosition end

    return {
        title = payload.title,
        message = payload.message,
        duration = duration,
        type = notifyType,
        position = position,
        icon = payload.icon,
        id = payload.id,
        iconColor = payload.iconColor,
        iconAnimation = payload.iconAnimation,
        alignIcon = payload.alignIcon,
        style = payload.style,
        showDuration = payload.showDuration,
    }
end
