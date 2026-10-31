for key, value in pairs(Kora) do
    -- compat/ is internal wiring used by kora_lib's legacy bridges. It must be
    -- loaded into the shared Kora table so separate Lua chunks can reuse it,
    -- but it is not part of kora_lib's consumer-facing export API.
    if key ~= "compat" then
        local kind = type(value)

        if kind == "function" then
            -- A bare function attached directly to Kora (none exist today; every
            -- current module is a table) -- a hypothetical Kora.foo(...) would
            -- export as exports.kora_lib:foo(...)
            exports(key, value)
        elseif kind == "table" then
            -- Kora.stream.loadModel(...) -> exports.kora_lib:stream_loadModel(...)
            for name, func in pairs(value) do
                if type(func) == "function" then
                    exports(key .. "_" .. name, func)
                end
            end
        end
    end
end

-- Consumers keep a few stateless modules in their own Lua environment. Tell
-- already-running consumers to pull fresh source after a kora_lib restart; the
-- event carries no functions or state across the resource boundary.
local isServer = type(IsDuplicityVersion) == 'function' and IsDuplicityVersion()
TriggerEvent(isServer and 'kora_lib:server:updated' or 'kora_lib:client:updated')
-- Deprecated alias: consumers that loaded an older init.lua still listen on the
-- pre-rename event name.
TriggerEvent(isServer and 'qblib:server:updated' or 'qblib:client:updated')
