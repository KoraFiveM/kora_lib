return {
    show = function(text, options)
        return Kora.textui.show(text, options)
    end,
    update = function(id, text, options)
        return Kora.textui.update(id, text, options)
    end,
    hide = function(id)
        return Kora.textui.hide(id)
    end,
}
