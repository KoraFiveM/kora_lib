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
function Kora.status.assertName(name)
    assert(type(name) == 'string' and #name > 0 and #name <= 128, KoraLang('Modules.Status.status_effect_name'))
end

---Registers a named status-effect definition. Call from a `shared_script` so client and server see the same one;
---Kora.status ships no bundled effects.
---@param name string
---@param def KoraStatusEffectDef
---@return boolean registered
---@return string? error
function Kora.status.registerEffect(name, def)
    Kora.status.assertName(name)
    assert(type(def) == "table", KoraLang('Modules.Status.status_registereffect_de'))
    assert(
        def.stacking == nil or STACKING_MODES[def.stacking],
        KoraLang('Modules.Status.invalid_stacking_mode', tostring(def.stacking))
    )
    assert(
        def.duration == nil or (Kora.util.isInteger(def.duration) and def.duration >= 0),
        KoraLang('Modules.Status.duration_non_negative')
    )
    assert(
        def.severityLevels == nil
                    or (Kora.util.isInteger(def.severityLevels)
                    and def.severityLevels >= 1),
        KoraLang('Modules.Status.severitylevels_positive')
    )
    if def.movement ~= nil then
        assert(type(def.movement) == 'table', KoraLang('Modules.Status.movement'))
        assert(Kora.util.isFiniteNumber(def.movement.speedMultiplier), KoraLang('Modules.Status.movement_speedmultiplier'))
    end
    if def.fx ~= nil then
        assert(type(def.fx) == 'table', KoraLang('Modules.Status.fx'))
        assert(
            def.fx.screen == nil or (type(def.fx.screen) == 'string' and #def.fx.screen > 0),
            KoraLang('Modules.Status.fx_screen_non')
        )
        if def.fx.ptfx ~= nil then
            assert(type(def.fx.ptfx) == 'table', KoraLang('Modules.Status.fx_ptfx'))
            assert(
                type(def.fx.ptfx.dict) == 'string' and #def.fx.ptfx.dict > 0
                and type(def.fx.ptfx.name) == 'string' and #def.fx.ptfx.name > 0,
                KoraLang('Modules.Status.fx_ptfx_non')
            )
        end
    end
    if def.anim ~= nil then
        assert(
            type(def.anim) == 'table' and type(def.anim.dict) == 'string' and #def.anim.dict > 0
            and type(def.anim.clip) == 'string' and #def.anim.clip > 0,
            KoraLang('Modules.Status.anim_non_empty')
        )
    end

    local owner = GetInvokingResource() or GetCurrentResourceName()
    local existingOwner = definitionOwners[name]
    if existingOwner and existingOwner ~= owner then
        return false, ("Status effect '%s' is owned by resource '%s'."):format(name, existingOwner)
    end

    registry[name] = Kora.util.deepClone(def)
    definitionOwners[name] = owner
    return true
end

---@param name string
---@return KoraStatusEffectDef?
function Kora.status.getEffectDef(name)
    Kora.status.assertName(name)
    local def = registry[name]
    return def and Kora.util.deepClone(def) or nil
end
