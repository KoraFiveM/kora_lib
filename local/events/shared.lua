---Validates an event name used with Kora.events.register / Kora.events.trigger.
---Raises on a non-string, empty, or oversized name. (Exported like every Kora.* function, so
---consumer resources can pre-validate names before registering.)
---@param name string
function Kora.events.assertName(name)
    assert(type(name) == "string", "Event name must be a string.")
    assert(#name > 0, "Event name must not be empty.")
    assert(#name <= 128, "Event name must be at most 128 bytes.")
end
