-- Client-only additions to Kora.util. The rest of the module is realm-agnostic
-- and lives in shared.lua; anything needing a rendering native has to be here.
--
-- Both files populate the same Kora.util table. That is the established pattern
-- (Kora.notify, Kora.state, Kora.callback all do it), but note the smoke-test
-- consequence documented in AGENTS.md: a test that dofiles both realms into
-- one process must capture a direct reference to each realm's functions right
-- after its own dofile.

---Projects a world position onto normalised screen space.
---
---Returns `x, y` in the 0..1 range FiveM's own draw natives use (SetTextEntry,
---DrawRect, ...), NOT pixels -- multiply by the resolution yourself if a NUI
---overlay needs pixel coordinates. The third return says whether the point is
---actually on screen; `x`/`y` are still returned when it isn't, but they are
---meaningless (World3dToScreen2d leaves them at whatever the last successful
---projection produced), so always gate on it.
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
