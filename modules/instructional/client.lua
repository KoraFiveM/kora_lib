local displays, nextId = {}, 0
local ownership
local activeIds = {}

local function token(button)
    if button.control ~= nil then
        assert(type(button.control) == 'number', 'Instructional button control must be a number.')
        return GetControlInstructionalButton(0, button.control, true)
    end
    local name = button.command or (button.keybind and button.keybind.name)
    assert(type(name) == 'string' and name ~= '', 'Instructional button requires control, command, or keybind.')
    if name:sub(1, 1) ~= '+' then name = '+' .. name end
    return GetControlInstructionalButton(0, joaat(name) | 0x80000000, true)
end

local function validate(buttons)
    assert(type(buttons) == 'table' and #buttons > 0, 'Instructional buttons must be a non-empty array.')
    for index = 1, #buttons do
        local button = buttons[index]
        assert(type(button) == 'table' and type(button.label) == 'string' and button.label ~= '', ('Instructional button %d requires a non-empty label.'):format(index))
        local count = (button.control ~= nil and 1 or 0) + (button.command ~= nil and 1 or 0) + (button.keybind ~= nil and 1 or 0)
        assert(count == 1, ('Instructional button %d requires exactly one input source.'):format(index))
        token(button)
    end
end

-- Native icon codes (b_*) have no readable name, so the NUI gets a short key label instead.
-- Text keys come back as t_<NAME> and need no entry. Unmapped codes fall through as the raw token.
local ICONS = {
    b_1004 = 'LMB', b_1005 = 'RMB', b_1006 = 'MMB',
}

local function keyLabel(button)
    local value = token(button)
    if type(value) ~= 'string' or value == '' then return '?' end
    local name = value:gsub('^t_', '', 1)
    return ICONS[name] or ICONS[value] or (name:gsub('^b_', '', 1))
end

local lastPayload

-- Merges every active display into rows; buttons sharing a label collapse into one row with several keys.
local function publish()
    local rows, byLabel = {}, {}
    for index = 1, #activeIds do
        local display = displays[activeIds[index]]
        if display then
            for _, button in ipairs(display.buttons) do
                local row = byLabel[button.label]
                if not row then
                    row = { label = button.label, keys = {} }
                    byLabel[button.label] = row
                    rows[#rows + 1] = row
                end
                local key = keyLabel(button)
                local seen = false
                for _, existing in ipairs(row.keys) do if existing == key then seen = true break end end
                if not seen then row.keys[#row.keys + 1] = key end
            end
        end
    end
    local parts = {}
    for _, row in ipairs(rows) do parts[#parts + 1] = row.label .. '=' .. table.concat(row.keys, '+') end
    local encoded = table.concat(parts, '\n')
    if encoded == lastPayload then return end
    lastPayload = encoded
    Kora.nui.send('instructional:set', { buttons = rows })
end

local function hide(id)
    if not displays[id] then return false end
    displays[id] = nil
    for index = 1, #activeIds do
        if activeIds[index] == id then table.remove(activeIds, index) break end
    end
    ownership.untrack(id)
    publish()
    return true
end

ownership = Kora.resources.registry(hide)

---@param buttons QBInstructionalButton[]
---@return QBInstructionalHandle
function Kora.instructional.show(buttons)
    validate(buttons)
    nextId = nextId + 1
    local id, display = nextId, { buttons = buttons }
    displays[id] = display
    activeIds[#activeIds + 1] = id
    ownership.track(GetInvokingResource() or GetCurrentResourceName(), id)
    publish()
    return {
        setButtons = function(updated) validate(updated) if displays[id] ~= display then return false end display.buttons = updated publish() return true end,
        hide = function() return hide(id) end,
        isVisible = function() return displays[id] == display end,
    }
end
