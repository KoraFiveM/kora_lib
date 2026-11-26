local prompts = {}
local nextPromptId = 0
local activePromptId

local function currentOwner()
    if type(GetInvokingResource) == 'function' then
        local invoking = GetInvokingResource()
        if invoking then return invoking end
    end
    return GetCurrentResourceName()
end

local function latestPrompt()
    local latestId
    for id in pairs(prompts) do
        if not latestId or id > latestId then latestId = id end
    end
    return latestId, latestId and prompts[latestId]
end

local function renderPrompt()
    local id, prompt = latestPrompt()
    if not id then
        if activePromptId then exports.lation_ui:hideText() end
        activePromptId = nil
        return
    end

    exports.lation_ui:showText({ title = prompt.text }, prompt.options)
    activePromptId = id
end

local function ownsPrompt(prompt)
    local caller = type(GetInvokingResource) == 'function' and GetInvokingResource() or nil
    return not caller or prompt.owner == caller
end

function Kora.bridge.drawText(text, options, owner)
    nextPromptId = nextPromptId + 1
    local id = nextPromptId
    prompts[id] = {
        text = text,
        options = options or {},
        owner = owner or currentOwner(),
    }
    renderPrompt()
    return id
end

function Kora.bridge.updateText(id, text, options)
    local prompt = prompts[id]
    if not prompt or not ownsPrompt(prompt) then return false end

    prompt.text = text
    if options ~= nil then prompt.options = options end
    if activePromptId == id then renderPrompt() end
    return true
end

function Kora.bridge.hideText(id)
    local prompt = prompts[id]
    if not prompt or not ownsPrompt(prompt) then return false end

    prompts[id] = nil
    if activePromptId == id then renderPrompt() end
    return true
end

AddEventHandler('onClientResourceStop', function(resource)
    local activeRemoved = false
    for id, prompt in pairs(prompts) do
        if prompt.owner == resource then
            prompts[id] = nil
            if activePromptId == id then activeRemoved = true end
        end
    end
    if activeRemoved then renderPrompt() end
end)

exports("bridge_drawText", Kora.bridge.drawText)
exports("bridge_updateText", Kora.bridge.updateText)
exports("bridge_hideText", Kora.bridge.hideText)
