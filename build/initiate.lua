---Annotation-only declaration of CfxLua's promise (the deferred library
---exposed via promise.new()), so `---@return promise` annotations across the
---modules resolve to a real class for LuaLS instead of an unknown name.
---@class promise
---@field state string
---@field resolve fun(self: promise, value: any)
---@field reject fun(self: promise, err: any)
---@field next fun(self: promise, onResolved: (fun(value: any): any), onRejected: (fun(err: any): any)?): promise

QB = setmetatable({}, {
    __index = function(self, key)
        local module = {}
        rawset(self, key, module)
        return module
    end
})
