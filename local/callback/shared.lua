-- Not on Kora.callback (finalise.lua would export it): shared by the client and
-- server callback files of this resource only.
---Expands a handler's `{ n, ..., __kora_lib_callback_envelope = true }` result
---(see the register wrapper in init.lua) back into a table.pack(pcall(...))
---shape, so every return value, nils included, is sent to the requester.
---@param results table table.pack(pcall(handler, ...))
---@return table results
function KoraLibUnwrapCallbackResults(results)
    if not results[1] or results.n ~= 2 then return results end
    local envelope = results[2]
    if type(envelope) ~= 'table' or envelope.__kora_lib_callback_envelope ~= true then return results end
    local count = math.tointeger(tonumber(envelope.n)) or 0
    local out = { n = count + 1, true }
    for index = 1, count do out[index + 1] = envelope[index] end
    return out
end

---Validates a callback name used with Kora.callback.register / Kora.callback.trigger.
---Raises on a non-string, empty, or oversized name. (Exported like every Kora.* function, so
---consumer resources can pre-validate names before registering.)
---@param name string
function Kora.callback.assertName(name)
    assert(type(name) == "string", "Callback name must be a string.")
    assert(#name > 0, "Callback name must not be empty.")
    assert(#name <= 128, "Callback name must be at most 128 bytes.")
end
