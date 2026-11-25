function Kora.bridge.drawText(text, options)
    return exports.lation_ui:showText({title = text}, options)
end

function Kora.bridge.updateText(id, text, options)
    return exports.lation_ui:showText({title = text}, options)
end

function Kora.bridge.hideText(id)
    return exports.lation_ui:hideText()
end

exports("bridge_drawText", Kora.bridge.drawText)
exports("bridge_updateText", Kora.bridge.updateText)
exports("bridge_hideText", Kora.bridge.hideText)
