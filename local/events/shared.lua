---Validates an event name used with QB.events.register / QB.events.trigger.
---Raises on a non-string or empty name. (Exported like every QB.* function, so
---consumer resources can pre-validate names before registering.)
---@param name string
function QB.events.assertName(name)
    assert(type(name) == "string", "Event name must be a string.")
    assert(#name > 0, "Event name must not be empty.")
end
