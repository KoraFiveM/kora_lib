local library = exports.qblib
local requireModule
local configModule

-- Requiring Lua files is deliberately consumer-local. Running this through a
-- qblib export would execute the required chunk in qblib's Lua environment,
-- leaking globals between resources and making the cache survive a consumer
-- restart. Load the factory into this resource's environment instead.
local function getRequireModule()
    if requireModule then return requireModule end

    local path = 'modules/require/loader.lua'
    local source = assert(LoadResourceFile('qblib', path), ('Unable to load @qblib/%s'):format(path))
    local chunk, compileError = load(source, ('@@qblib/%s'):format(path), 't', _ENV)
    assert(chunk, compileError)

    local createRequire = chunk()
    assert(type(createRequire) == 'function', ('@qblib/%s must return a factory function'):format(path))

    requireModule = createRequire(GetCurrentResourceName())
    return requireModule
end

-- Configuration has to run inside the CONSUMING resource: its Config table,
-- override file, and live handlers are all local to that resource. The normal
-- QB proxy deliberately routes calls into qblib instead, so config is the one
-- explicit consumer-local module alongside QB.require.
local function getConfigModule()
    if configModule then return configModule end

    local path = 'modules/config/consumer.lua'
    local source = assert(LoadResourceFile('qblib', path), ('Unable to load @qblib/%s'):format(path))
    local chunk, compileError = load(source, ('@@qblib/%s'):format(path), 't', _ENV)
    assert(chunk, compileError)

    local createConfig = chunk()
    assert(type(createConfig) == 'function', ('@qblib/%s must return a factory function'):format(path))
    configModule = createConfig(library)
    return configModule
end

-- FXServer's export dispatch has a known bug (citizenfx/fivem#2408): calling
-- an export via dot-style dispatch -- `t[k](t, ...)` or `t.k(...)` -- can
-- shift/drop arguments (observed here as a handler function arriving as
-- something other than a function), while genuine colon-call syntax
-- (`t:k(...)`) works correctly. The two are semantically equivalent in plain
-- Lua but compile to different bytecode (colon sugar emits a SELF
-- instruction; `t[k](t, ...)` doesn't), and FXServer's exports resolution
-- apparently depends on that difference.
--
-- Colon sugar only exists for a LITERAL method name at the call site, which
-- is impossible here since QB.<module>.<fn> needs a dynamically *computed*
-- export name. `load()` works around that: it compiles a fresh chunk from a
-- source STRING containing a literal `lib:name(...)` call, so the compiler
-- still emits the real SELF instruction even though `name` was assembled at
-- runtime -- unlike `library[path](library, ...)`, which never can.
--
-- Only ever called with `name` built from QB module/function keys (lowercase
-- identifiers by this codebase's own naming convention -- see AGENTS.md
-- "Conventions"), but validated anyway since it's runtime code generation
-- from property-access keys: a malformed key becoming a Lua injection vector
-- into `load()`'s source string would be a bad failure mode to leave open.
local function makeColonCall(name)
    assert(name:match("^[%a_][%w_]*$"), ("Invalid QB export name: %s"):format(name))

    -- `...` isn't a valid name to declare a local as (so `local lib, ... = ...`
    -- is a syntax error), and referencing `...` a second time later in the
    -- chunk would just re-expand to ALL of it again, receiver included --
    -- select() is what actually splits "receiver" from "the rest" here.
    -- select(1, ...) truncated by the surrounding parens = just the receiver
    -- (library, prepended by the wrapper below); select(2, ...), unparenthesized
    -- in the final argument slot, expands to every real call argument.
    local chunk = assert(load(("return (select(1, ...)):%s(select(2, ...))"):format(name)))

    return function(...)
        return chunk(library, ...)
    end
end

---@type QBLib
QB = setmetatable({}, {
    __index = function(t, k)
        if k == 'require' then
            local module = getRequireModule()
            rawset(t, k, module)
            return module
        end

        if k == 'config' then
            local module = getConfigModule()
            rawset(t, k, module)
            return module
        end

        -- Computed once per module access, not per call -- __call's own
        -- implicit self (the proxy table) still has to be stripped below,
        -- since a metamethod always receives it as its first argument
        -- regardless of what the wrapped function itself expects.
        local moduleCall = makeColonCall(k)

        -- Memoized: the sub-proxy is rawset back into QB so repeated
        -- QB.<module> accesses reuse one table instead of allocating a fresh
        -- proxy per lookup (__index only fires while the key is absent).
        local proxy = setmetatable({}, {
            -- A bare function on QB, e.g. a hypothetical QB.foo(...) ->
            -- exports.qblib:foo(...)
            __call = function(_, ...) return moduleCall(...) end,
            -- A module function, e.g. QB.notify.send(...) ->
            -- exports.qblib:notify_send(...). Memoized the same way as the
            -- module-level proxy above: rawset into the sub-proxy so the
            -- colon-call chunk for a given QB.<module>.<fn> is compiled via
            -- load() once, not on every single call.
            __index = function(subProxy, k2)
                local wrapper = makeColonCall(("%s_%s"):format(k, k2))
                rawset(subProxy, k2, wrapper)
                return wrapper
            end,
        })

        rawset(t, k, proxy)
        return proxy
    end,
})
