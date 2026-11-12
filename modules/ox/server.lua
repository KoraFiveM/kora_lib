---Releases server-side compatibility state owned by a stopped ox_lib consumer (currently none; kept for lifecycle symmetry).
---@param owner string
function Kora.ox.disposeOwner(owner)
    assert(type(owner) == 'string' and owner ~= '', 'ox owner must be a non-empty string.')
end
