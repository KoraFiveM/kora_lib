function Kora.bridge.openWardrobe()
    return exports.kora_clothing:OpenWardrobe()
end

function Kora.bridge.openClothingRoom(options)
    return exports.kora_clothing:OpenClothingRoom(options)
end

function Kora.bridge.applyAppearanceToPed(ped, model, skin)
    return exports.kora_clothing:ApplyAppearanceToPed(ped, model, skin)
end

function Kora.bridge.applyStarterAppearance()
    return exports.kora_clothing:applyStarterAppearance()
end

function Kora.bridge.reloadSkin()
    return exports.kora_clothing:reloadSkin()
end
