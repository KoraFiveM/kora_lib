for key, value in pairs(QB) do
    -- compat/ is internal wiring used by qblib's legacy bridges. It must be
    -- loaded into the shared QB table so separate Lua chunks can reuse it,
    -- but it is not part of qblib's consumer-facing export API.
    if key ~= "compat" then
        local kind = type(value)

        if kind == "function" then
            -- A bare function attached directly to QB (none exist today; every
            -- current module is a table) -- a hypothetical QB.foo(...) would
            -- export as exports.qblib:foo(...)
            exports(key, value)
        elseif kind == "table" then
            -- QB.stream.loadModel(...) -> exports.qblib:stream_loadModel(...)
            for name, func in pairs(value) do
                if type(func) == "function" then
                    exports(key .. "_" .. name, func)
                end
            end
        end
    end
end
