---Releases server-side compatibility state owned by a stopped ox_lib consumer.
---The current provider has no persistent server state, but this explicit
---contract keeps the lifecycle bridge symmetric and fail-fast.
---@param owner string
function Kora.ox.disposeOwner(owner)
    assert(type(owner) == 'string' and owner ~= '', 'ox owner must be a non-empty string.')
end
