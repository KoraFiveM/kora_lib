local entries = {}
local order = {}
local nextId = 0

local POSITIONS = {
    ['left-center'] = true,
    ['right-center'] = true,
    ['top-center'] = true,
    ['bottom-center'] = true,
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

local function normalize(text, options)
    assert(type(text) == 'string' and #text > 0, 'Text UI text must be a non-empty string.')
    assert(options == nil or type(options) == 'table', 'Text UI options must be a table.')
    options = options or {}

    local position = options.position
    if position == nil then position = 'right-center' end
    assert(POSITIONS[position], 'Text UI position must be left-center, right-center, top-center, or bottom-center.')
    assert(options.key == nil or (type(options.key) == 'string' and #options.key > 0),
        'Text UI key must be a non-empty string.')
    assert(options.icon == nil or (type(options.icon) == 'string' and #options.icon > 0),
        'Text UI icon must be a non-empty string.')
    assert(options.iconColor == nil or type(options.iconColor) == 'string', 'Text UI iconColor must be a string.')
    assert(options.iconAnimation == nil or ICON_ANIMATIONS[options.iconAnimation], 'Text UI iconAnimation is unsupported.')
    assert(options.alignIcon == nil or options.alignIcon == 'top' or options.alignIcon == 'center',
        'Text UI alignIcon must be top or center.')
    assert(options.style == nil or type(options.style) == 'table' or type(options.style) == 'string',
        'Text UI style must be a table or CSS declaration string.')

    return {
        text = text,
        key = options.key,
        icon = options.icon,
        iconColor = options.iconColor,
        iconAnimation = options.iconAnimation,
        alignIcon = options.alignIcon,
        style = options.style,
        position = position,
    }
end

local function visibleId()
    return order[#order]
end

local function render()
    local id = visibleId()
    local entry = id and entries[id]
    if entry then
        Kora.nui.send('textui:set', {
            id = id,
            text = entry.text,
            key = entry.key,
            icon = entry.icon,
            iconColor = entry.iconColor,
            iconAnimation = entry.iconAnimation,
            alignIcon = entry.alignIcon,
            style = entry.style,
            position = entry.position,
        })
    else
        Kora.nui.send('textui:set', false)
    end
end

local registry

local function remove(id, untrack)
    if not entries[id] then return false end
    local wasVisible = visibleId() == id
    entries[id] = nil

    for index = #order, 1, -1 do
        if order[index] == id then
            table.remove(order, index)
            break
        end
    end

    if untrack then registry.untrack(id) end
    if wasVisible then render() end
    return true
end

registry = Kora.resources.registry(function(id)
    remove(id, false)
end)

---Adds a text prompt to the display stack and returns its owned handle.
---@param text string
---@param opts? QBTextUIOptions
---@param owner? string Internal owner override for compatibility providers.
---@return integer id
function Kora.textui.show(text, opts, owner)
    local entry = normalize(text, opts)
    assert(owner == nil or (type(owner) == 'string' and owner ~= ''), 'Text UI owner must be a non-empty string.')
    nextId = nextId + 1
    local id = nextId

    entries[id] = entry
    order[#order + 1] = id
    registry.track(owner or GetInvokingResource() or GetCurrentResourceName(), id)
    render()
    return id
end

---Updates a live handle without changing its place in the display stack.
---@param id integer
---@param text string
---@param opts? QBTextUIOptions
---@return boolean updated
function Kora.textui.update(id, text, opts)
    assert(type(id) == 'number' and id % 1 == 0, 'Text UI id must be an integer.')
    if not entries[id] then return false end
    local caller = GetInvokingResource()
    if caller and registry.owner(id) ~= caller then return false end

    entries[id] = normalize(text, opts)
    if visibleId() == id then render() end
    return true
end

---Removes a handle; removing the visible handle restores the previous one.
---@param id integer
---@return boolean removed
function Kora.textui.hide(id)
    assert(type(id) == 'number' and id % 1 == 0, 'Text UI id must be an integer.')
    local caller = GetInvokingResource()
    if caller and registry.owner(id) ~= caller then return false end
    return remove(id, true)
end

---Reports whether any handle, or a particular handle, is live.
---@param id? integer
---@return boolean open
function Kora.textui.isOpen(id)
    if id == nil then return #order > 0 end
    return entries[id] ~= nil
end

---Reports whether a handle is the newest live entry currently rendered.
---@param id integer
---@return boolean visible
function Kora.textui.isVisible(id)
    return entries[id] ~= nil and visibleId() == id
end
