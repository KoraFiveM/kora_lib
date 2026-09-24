---@class QBStatusEffectDef
---@field duration? integer Default ms an application lasts when the caller's `opts.duration` doesn't override it. `nil` means "until explicitly removed."
---@field stacking? "replace"|"extend"|"stack" How a second `QB.status.apply` for the same name, while one is already active, combines with it. `"replace"` restarts the timer/severity from the new call; `"extend"` adds the new duration onto whatever's left; `"stack"` adds the new severity onto the existing one (capped at `severityLevels`). Defaults to `"replace"`.
---@field severityLevels? integer Number of discrete severity tiers `opts.severity` may select between (1..severityLevels). `nil` means this effect doesn't use severity.
---@field fx? {screen?: string, ptfx?: QBFxPtfxDef} Played via `QB.fx` on the client while the effect is active. A `ptfx` entry needs `dict`/`name` at minimum -- `entity` defaults to the local ped if neither `entity` nor `coords` is set, and `looped` is always forced true regardless of what's given (a status effect's visual runs for the effect's own lifetime, not the ptfx's independent one).
---@field anim? {dict: string, clip: string} Played on the local ped via `QB.anim.play` while the effect is active.
---@field movement? {speedMultiplier: number} Applied every frame via `SetPedMoveRateOverride` while active. Simultaneous effects compose multiplicatively; the frame loop exists only while a movement effect is active.

local registry = {}
local definitionOwners = {}

local STACKING_MODES = { replace = true, extend = true, stack = true }

local stopEvent = type(IsDuplicityVersion) == "function" and IsDuplicityVersion()
    and "onResourceStop" or "onClientResourceStop"

AddEventHandler(stopEvent, function(resource)
    for name, owner in pairs(definitionOwners) do
        if owner == resource then
            registry[name] = nil
            definitionOwners[name] = nil
        end
    end
end)

---@param name string
function QB.status.assertName(name)
    assert(type(name) == 'string' and #name > 0 and #name <= 128,
        'Status effect name must be a non-empty string of at most 128 bytes.')
end

---Registers a named status-effect definition. Call from a `shared_script` so
---both the client and server VM see the same definition -- QB.status ships
---no bundled effects of its own, every consumer defines its own (e.g.
---`"bleeding"`, `"limping"`, `"high_weed"`).
---@param name string
---@param def QBStatusEffectDef
---@return boolean registered
---@return string? error
function QB.status.registerEffect(name, def)
    QB.status.assertName(name)
    assert(type(def) == "table", "QB.status.registerEffect requires a def table.")
    assert(def.stacking == nil or STACKING_MODES[def.stacking], ("Invalid stacking mode: %s"):format(tostring(def.stacking)))
    assert(def.duration == nil or (QB.util.isInteger(def.duration) and def.duration >= 0),
        "duration must be a non-negative integer.")
    assert(def.severityLevels == nil or (QB.util.isInteger(def.severityLevels) and def.severityLevels >= 1),
        "severityLevels must be a positive integer.")
    if def.movement ~= nil then
        assert(type(def.movement) == 'table', 'movement must be a table.')
        assert(QB.util.isFiniteNumber(def.movement.speedMultiplier),
            'movement.speedMultiplier must be a finite number.')
    end
    if def.fx ~= nil then
        assert(type(def.fx) == 'table', 'fx must be a table.')
        assert(def.fx.screen == nil or (type(def.fx.screen) == 'string' and #def.fx.screen > 0),
            'fx.screen must be a non-empty string.')
        if def.fx.ptfx ~= nil then
            assert(type(def.fx.ptfx) == 'table', 'fx.ptfx must be a table.')
            assert(type(def.fx.ptfx.dict) == 'string' and #def.fx.ptfx.dict > 0
                and type(def.fx.ptfx.name) == 'string' and #def.fx.ptfx.name > 0,
                'fx.ptfx requires non-empty dict and name strings.')
        end
    end
    if def.anim ~= nil then
        assert(type(def.anim) == 'table' and type(def.anim.dict) == 'string' and #def.anim.dict > 0
            and type(def.anim.clip) == 'string' and #def.anim.clip > 0,
            'anim requires non-empty dict and clip strings.')
    end

    local owner = GetInvokingResource() or GetCurrentResourceName()
    local existingOwner = definitionOwners[name]
    if existingOwner and existingOwner ~= owner then
        return false, ("Status effect '%s' is owned by resource '%s'."):format(name, existingOwner)
    end

    registry[name] = QB.util.deepClone(def)
    definitionOwners[name] = owner
    return true
end

---@param name string
---@return QBStatusEffectDef?
function QB.status.getEffectDef(name)
    QB.status.assertName(name)
    local def = registry[name]
    return def and QB.util.deepClone(def) or nil
end
