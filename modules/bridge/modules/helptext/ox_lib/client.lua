function Kora.bridge.drawText(text, options)
    return exports.ox_lib:showTextUi(text, options)
end

function Kora.bridge.updateText(id, text, options)
    return exports.ox_lib:showTextUi(text, options)
end

function Kora.bridge.hideText(id)
    return exports.ox_lib:hideTextUi()
end

exports("bridge_drawText", Kora.bridge.drawText)
exports("bridge_updateText", Kora.bridge.updateText)
exports("bridge_hideText", Kora.bridge.hideText)
