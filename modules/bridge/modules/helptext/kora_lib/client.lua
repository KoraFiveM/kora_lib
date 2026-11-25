function Kora.bridge.drawText(text, options)
    return Kora.textui.show(text, options)
end

function Kora.bridge.updateText(id, text, options)
    return Kora.textui.update(id, text, options)
end

function Kora.bridge.hideText(id)
    return Kora.textui.hide(id)
end

exports("bridge_drawText", Kora.bridge.drawText)
exports("bridge_updateText", Kora.bridge.updateText)
exports("bridge_hideText", Kora.bridge.hideText)
