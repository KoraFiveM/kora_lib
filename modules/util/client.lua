---Projects a world position onto normalised 0..1 screen space (as FiveM's draw natives use), NOT pixels.
---The third return says whether the point is on screen; `x`/`y` are meaningless when it isn't, so gate on it.
---@param coords vector3 | {x: number, y: number, z: number}
---@return number x Normalised 0..1, left to right.
---@return number y Normalised 0..1, top to bottom.
---@return boolean onScreen
function Kora.util.worldToScreen(coords)
    assert(coords and Kora.util.isFiniteNumber(coords.x) and Kora.util.isFiniteNumber(coords.y)
        and Kora.util.isFiniteNumber(coords.z), "Kora.util.worldToScreen expects finite vector3 or {x, y, z} values.")

    local onScreen, x, y = World3dToScreen2d(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)

    return x or 0.0, y or 0.0, onScreen == true
end

---Same projection in pixels, using the client's current resolution.
---@param coords vector3 | {x: number, y: number, z: number}
---@return number x Pixels.
---@return number y Pixels.
---@return boolean onScreen
function Kora.util.worldToScreenPixels(coords)
    local x, y, onScreen = Kora.util.worldToScreen(coords)
    local width, height = GetActiveScreenResolution()

    return x * width, y * height, onScreen
end
