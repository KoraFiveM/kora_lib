local adapter
if IsDuplicityVersion() then
    adapter = {
        openAdminSession = function(targetSrc, service)
            return exports.kora_clothing:OpenAdminSession(targetSrc, service)
        end,
    }
else
    adapter = {
        openWardrobe = function()
            return exports.kora_clothing:OpenWardrobe()
        end,
        openClothingRoom = function(options)
            return exports.kora_clothing:OpenClothingRoom(options)
        end,
        applyAppearanceToPed = function(ped, model, skin)
            return exports.kora_clothing:ApplyAppearanceToPed(ped, model, skin)
        end,
        applyStarterAppearance = function()
            return exports.kora_clothing:applyStarterAppearance()
        end,
        reloadSkin = function()
            return exports.kora_clothing:reloadSkin()
        end,
    }
end

Kora.bridge.register('clothing', 'kora_clothing', adapter)