---Validates a callback name used with QB.callback.register / QB.callback.trigger.
---Raises on a non-string, empty, or oversized name. (Exported like every QB.* function, so
---consumer resources can pre-validate names before registering.)
---@param name string
function QB.callback.assertName(name)
    assert(type(name) == "string", "Callback name must be a string.")
    assert(#name > 0, "Callback name must not be empty.")
    assert(#name <= 128, "Callback name must be at most 128 bytes.")
end
