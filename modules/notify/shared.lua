local NOTIFY_TYPES = {
    info = true,
    success = true,
    warning = true,
    error = true,
}

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
---@param payload KoraNotifyPayload
---@return KoraNotifyPayload
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
---@param payload KoraNotifyPayload
function Kora.notify.assert(payload)
    assert(type(payload) == "table", KoraLang('Modules.Notify.payload_invalid'))

    local title = payload.title
    local message = payload.message
    local duration = payload.duration
    if duration == nil then duration = Config.notify.defaultDuration end

    assert(title == nil or type(title) == "string", KoraLang('Modules.Notify.title_invalid'))
    assert(message == nil or type(message) == "string", KoraLang('Modules.Notify.message_invalid'))
    assert(title or message, KoraLang('Modules.Notify.content_required'))
    assert(Kora.util.isInteger(duration), KoraLang('Modules.Notify.duration_invalid'))
    assert(duration > 0, KoraLang('Modules.Notify.duration_positive'))
    assert(duration <= Config.notify.maxDuration,
        KoraLang('Modules.Notify.duration_max', Config.notify.maxDuration))

    assert(payload.type == nil or NOTIFY_TYPES[Kora.notify.normalizeType(payload.type)],
        KoraLang('Modules.Notify.type_invalid', tostring(payload.type)))
    assert(payload.position == nil or NOTIFY_POSITIONS[payload.position],
        KoraLang('Modules.Notify.position_invalid', tostring(payload.position)))
    assert(payload.icon == nil or type(payload.icon) == "string", KoraLang('Modules.Notify.icon_invalid'))
    assert(payload.id == nil or Kora.util.isFiniteNumber(payload.id) or (type(payload.id) == "string" and payload.id ~= ""),
        KoraLang('Modules.Notify.id_invalid'))
    assert(payload.iconColor == nil or type(payload.iconColor) == "string", KoraLang('Modules.Notify.icon_color_invalid'))
    assert(payload.iconAnimation == nil or ICON_ANIMATIONS[payload.iconAnimation], KoraLang('Modules.Notify.icon_animation_invalid'))
    assert(payload.alignIcon == nil or payload.alignIcon == "top" or payload.alignIcon == "center",
        KoraLang('Modules.Notify.align_invalid'))
    assert(payload.style == nil or type(payload.style) == "table", KoraLang('Modules.Notify.style_invalid'))
    assert(payload.showDuration == nil or type(payload.showDuration) == "boolean", KoraLang('Modules.Notify.show_duration_invalid'))
end

---Fills in configured defaults so the NUI always receives a resolved `type`/`position`.
---@param payload KoraNotifyPayload
---@return KoraNotifyPayload resolved A copy; the caller's table is never mutated.
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
