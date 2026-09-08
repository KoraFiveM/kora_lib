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

-- Validation sets, kept in sync with QBNotifyType/QBNotifyPosition above and
-- with NotifyPayload in web/src/lib/types.ts.
local NOTIFY_TYPES = {
    info = true,
    success = true,
    warning = true,
    error = true,
}

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
function QB.notify.assert(payload)
    assert(type(payload) == "table", "Notify payload must be a table.")

    local title = payload.title
    local message = payload.message
    local duration = payload.duration or Config.notify.defaultDuration

    -- Type-checked, not just truthy-checked: these render as text in the NUI,
    -- and a table/number sneaking through as a React child would crash the
    -- whole NUI root, not just this one toast.
    assert(title == nil or type(title) == "string", "Notification title must be a string.")
    assert(message == nil or type(message) == "string", "Notification message must be a string.")
    assert(title or message, "Notifications require a title or message.")
    assert(type(duration) == "number", "Duration must be a number.")
    assert(duration > 0, "Duration must be greater than 0.")
    assert(duration <= Config.notify.maxDuration,
        ("Duration must be at most %d ms (Config.notify.maxDuration)."):format(Config.notify.maxDuration))

    assert(payload.type == nil or NOTIFY_TYPES[payload.type],
        ("Notification type must be one of info/success/warning/error, got: %s"):format(tostring(payload.type)))
    assert(payload.position == nil or NOTIFY_POSITIONS[payload.position],
        ("Notification position must be one of top/bottom + left/center/right, got: %s"):format(tostring(payload.position)))
    assert(payload.icon == nil or type(payload.icon) == "string", "Notification icon must be a string.")
    assert(payload.id == nil or type(payload.id) == "number" or (type(payload.id) == "string" and payload.id ~= ""),
        "Notification id must be a number or non-empty string.")
    assert(payload.iconColor == nil or type(payload.iconColor) == "string", "Notification iconColor must be a string.")
    assert(payload.iconAnimation == nil or ICON_ANIMATIONS[payload.iconAnimation], "Notification iconAnimation is unsupported.")
    assert(payload.alignIcon == nil or payload.alignIcon == "top" or payload.alignIcon == "center",
        "Notification alignIcon must be top or center.")
    assert(payload.style == nil or type(payload.style) == "table", "Notification style must be a table.")
    assert(payload.showDuration == nil or type(payload.showDuration) == "boolean", "Notification showDuration must be a boolean.")
end

---Fills in the configured defaults a payload didn't specify, so the NUI always
---receives a fully-resolved `type`/`position` rather than having to know
---Lua-side config values that are never transmitted.
---@param payload QBNotifyPayload
---@return QBNotifyPayload resolved A copy; the caller's table is never mutated.
function QB.notify.withDefaults(payload)
    return {
        title = payload.title,
        message = payload.message,
        duration = payload.duration or Config.notify.defaultDuration,
        type = payload.type or Config.notify.defaultType,
        position = payload.position or Config.notify.defaultPosition,
        icon = payload.icon,
        id = payload.id,
        iconColor = payload.iconColor,
        iconAnimation = payload.iconAnimation,
        alignIcon = payload.alignIcon,
        style = payload.style,
        showDuration = payload.showDuration,
    }
end
