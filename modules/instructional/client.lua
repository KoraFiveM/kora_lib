local displays, nextId, movie, running = {}, 0, nil, false
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

local function drawText(value)
    BeginTextCommandScaleformString('STRING') AddTextComponentSubstringPlayerName(value) EndTextCommandScaleformString()
end

local function draw()
    if not movie then movie = RequestScaleformMovie('INSTRUCTIONAL_BUTTONS') end
    if not movie or not HasScaleformMovieLoaded(movie) then return end
    BeginScaleformMovieMethod(movie, 'CLEAR_ALL') EndScaleformMovieMethod()
    local slot = 0
    for index = 1, #activeIds do
        local display = displays[activeIds[index]]
        if display then
            for index = 1, #display.buttons do
                local button = display.buttons[index]
                BeginScaleformMovieMethod(movie, 'SET_DATA_SLOT')
                ScaleformMovieMethodAddParamInt(slot)
                drawText(token(button)) drawText(button.label)
                EndScaleformMovieMethod()
                slot = slot + 1
            end
        end
    end
    BeginScaleformMovieMethod(movie, 'DRAW_INSTRUCTIONAL_BUTTONS') EndScaleformMovieMethod()
    DrawScaleformMovieFullscreen(movie, 255, 255, 255, 255, 0)
end

local function ensureThread()
    if running then return end
    running = true
    CreateThread(function()
        while #activeIds > 0 do draw() Wait(0) end
        if movie then SetScaleformMovieAsNoLongerNeeded(movie) movie = nil end
        running = false
    end)
end

local function hide(id)
    if not displays[id] then return false end
    displays[id] = nil
    for index = 1, #activeIds do
        if activeIds[index] == id then table.remove(activeIds, index) break end
    end
    ownership.untrack(id)
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
    ensureThread()
    return {
        setButtons = function(updated) validate(updated) if displays[id] ~= display then return false end display.buttons = updated return true end,
        hide = function() return hide(id) end,
        isVisible = function() return displays[id] == display end,
    }
end
