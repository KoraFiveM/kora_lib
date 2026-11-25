Kora.bridge.showHelpText = function(text, options)
    return Kora.textui.show(text, options)
end
Kora.bridge.updateHelpText = function(id, text, options)
    return Kora.textui.update(id, text, options)
end
Kora.bridge.hideHelpText = function(id)
    return Kora.textui.hide(id)
end
