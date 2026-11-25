Kora.bridge.openWardrobe = function()
    return exports.kora_clothing:OpenWardrobe()
end
Kora.bridge.openClothingRoom = function(options)
    return exports.kora_clothing:OpenClothingRoom(options)
end
Kora.bridge.applyAppearanceToPed = function(ped, model, skin)
    return exports.kora_clothing:ApplyAppearanceToPed(ped, model, skin)
end
Kora.bridge.applyStarterAppearance = function()
    return exports.kora_clothing:applyStarterAppearance()
end
Kora.bridge.reloadSkin = function()
    return exports.kora_clothing:reloadSkin()
end
