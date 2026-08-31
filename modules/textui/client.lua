---@alias QBTextUIPosition 'left-center'|'right-center'|'top-center'|'bottom-center'

---@class QBTextUIOptions
---@field key? string Short key/control label displayed beside the text.
---@field icon? string Lucide icon name.
---@field position? QBTextUIPosition Defaults to `right-center`.

local entries = {}
local order = {}
local nextId = 0

local POSITIONS = {
    ['left-center'] = true,
    ['right-center'] = true,
    ['top-center'] = true,
    ['bottom-center'] = true,
}

local function normalize(text, options)
    assert(type(text) == 'string' and #text > 0, 'Text UI text must be a non-empty string.')
    assert(options == nil or type(options) == 'table', 'Text UI options must be a table.')
    options = options or {}

    local position = options.position or 'right-center'
    assert(POSITIONS[position], 'Text UI position must be left-center, right-center, top-center, or bottom-center.')
    assert(options.key == nil or (type(options.key) == 'string' and #options.key > 0),
        'Text UI key must be a non-empty string.')
    assert(options.icon == nil or (type(options.icon) == 'string' and #options.icon > 0),
        'Text UI icon must be a non-empty string.')

    return {
        text = text,
        key = options.key,
        icon = options.icon,
        position = position,
    }
end

local function visibleId()
    return order[#order]
end

local function render()
    local id = visibleId()
    local entry = id and entries[id] or nil
    if entry then
        QB.nui.send('textui:set', {
            id = id,
            text = entry.text,
            key = entry.key,
            icon = entry.icon,
            position = entry.position,
        })
    else
        QB.nui.send('textui:set', false)
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

registry = QB.resources.registry(function(id)
    remove(id, false)
end)

---Adds a text prompt to the display stack and returns its owned handle.
---@param text string
---@param opts? QBTextUIOptions
---@return integer id
function QB.textui.show(text, opts)
    local entry = normalize(text, opts)
    nextId = nextId + 1
    local id = nextId

    entries[id] = entry
    order[#order + 1] = id
    registry.track(GetInvokingResource() or GetCurrentResourceName(), id)
    render()
    return id
end

---Updates a live handle without changing its place in the display stack.
---@param id integer
---@param text string
---@param opts? QBTextUIOptions
---@return boolean updated
function QB.textui.update(id, text, opts)
    assert(type(id) == 'number' and id % 1 == 0, 'Text UI id must be an integer.')
    if not entries[id] then return false end

    entries[id] = normalize(text, opts)
    if visibleId() == id then render() end
    return true
end

---Removes a handle; removing the visible handle restores the previous one.
---@param id integer
---@return boolean removed
function QB.textui.hide(id)
    assert(type(id) == 'number' and id % 1 == 0, 'Text UI id must be an integer.')
    return remove(id, true)
end

---Reports whether any handle, or a particular handle, is live.
---@param id? integer
---@return boolean open
function QB.textui.isOpen(id)
    if id == nil then return #order > 0 end
    return entries[id] ~= nil
end

---Reports whether a handle is the newest live entry currently rendered.
---@param id integer
---@return boolean visible
function QB.textui.isVisible(id)
    return entries[id] ~= nil and visibleId() == id
end
