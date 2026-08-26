local H = dofile('test/harness.lua')
H.test('pinned legacy UI exports are present', function()
    local contract = dofile('test/contracts/legacy_ui.lua')
    local function read(path) local f = assert(io.open(path, 'r')); local value = f:read('*a'); f:close(); return value end
    local menu, input = read('compat/client/qb-menu.lua'), read('compat/client/qb-input.lua')
    for _, name in ipairs(contract.qbMenu.exports) do H.assertTrue(menu:find('"' .. name .. '"', 1, true) or menu:find("'" .. name .. "'", 1, true), 'qb-menu export ' .. name) end
    for _, name in ipairs(contract.qbInput.exports) do H.assertTrue(input:find('"' .. name .. '"', 1, true), 'qb-input export ' .. name) end
end)
H.test('pinned legacy qb-minigames exports are present', function()
    local contract = dofile('test/contracts/legacy_ui.lua')
    local function read(path) local f = assert(io.open(path, 'r')); local value = f:read('*a'); f:close(); return value end
    local minigames = read('compat/client/qb-minigames.lua')
    for _, name in ipairs(contract.qbMinigames.exports) do
        H.assertTrue(minigames:find('"' .. name .. '"', 1, true) or minigames:find("'" .. name .. "'", 1, true), 'qb-minigames export ' .. name)
    end
end)
H.report('compat_contract')
