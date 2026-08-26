---@class QBStatusEffectDef
---@field duration? integer Default ms an application lasts when the caller's `opts.duration` doesn't override it. `nil` means "until explicitly removed."
---@field stacking? "replace"|"extend"|"stack" How a second `QB.status.apply` for the same name, while one is already active, combines with it. `"replace"` restarts the timer/severity from the new call; `"extend"` adds the new duration onto whatever's left; `"stack"` adds the new severity onto the existing one (capped at `severityLevels`). Defaults to `"replace"`.
---@field severityLevels? integer Number of discrete severity tiers `opts.severity` may select between (1..severityLevels). `nil` means this effect doesn't use severity.
---@field fx? {screen?: string, ptfx?: QBFxPtfxDef} Played via `QB.fx` on the client while the effect is active. A `ptfx` entry needs `dict`/`name` at minimum -- `entity` defaults to the local ped if neither `entity` nor `coords` is set, and `looped` is always forced true regardless of what's given (a status effect's visual runs for the effect's own lifetime, not the ptfx's independent one).
---@field anim? {dict: string, clip: string} Played on the local ped via `QB.anim.play` while the effect is active.
---@field movement? {speedMultiplier: number} Applied via `SetPedMoveRateOverride` while active. Simultaneous effects compose multiplicatively and are recomputed whenever one is applied or removed.

local registry = {}

local STACKING_MODES = { replace = true, extend = true, stack = true }

---Registers a named status-effect definition. Call from a `shared_script` so
---both the client and server VM see the same definition -- QB.status ships
---no bundled effects of its own, every consumer defines its own (e.g.
---`"bleeding"`, `"limping"`, `"high_weed"`).
---@param name string
---@param def QBStatusEffectDef
function QB.status.registerEffect(name, def)
    assert(type(name) == "string" and #name > 0, "QB.status.registerEffect requires a string name.")
    assert(type(def) == "table", "QB.status.registerEffect requires a def table.")
    assert(def.stacking == nil or STACKING_MODES[def.stacking], ("Invalid stacking mode: %s"):format(tostring(def.stacking)))
    assert(def.severityLevels == nil or (type(def.severityLevels) == "number" and def.severityLevels >= 1),
        "severityLevels must be a positive number.")

    registry[name] = def
end

---@param name string
---@return QBStatusEffectDef?
function QB.status.getEffectDef(name)
    return registry[name]
end
