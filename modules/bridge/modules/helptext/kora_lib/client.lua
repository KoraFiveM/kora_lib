function Kora.bridge.showHelpText(text, options)
    return Kora.textui.show(text, options)
end
function Kora.bridge.updateHelpText(id, text, options)
    return Kora.textui.update(id, text, options)
end
function Kora.bridge.hideHelpText(id)
    return Kora.textui.hide(id)
end
