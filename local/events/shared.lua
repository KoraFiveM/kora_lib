---Validates an event name used with Kora.events.register / Kora.events.trigger.
---Raises on a non-string, empty, or oversized name. (Exported like every Kora.* function, so
---consumer resources can pre-validate names before registering.)
---@param name string
function Kora.events.assertName(name)
    assert(type(name) == "string", KoraLang('Local.Events.name_must_be_string'))
    assert(#name > 0, KoraLang('Local.Events.name_must_not_be_empty'))
    assert(#name <= 128, KoraLang('Local.Events.name_too_long', 128))
end
