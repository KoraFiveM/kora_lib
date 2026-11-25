local appearanceResource = exports['illenium-appearance']

function Kora.bridge.openWardrobe()
    TriggerEvent('illenium-appearance:client:openClothingShopMenu')
end

exports('bridge_openWardrobe', Kora.bridge.openWardrobe)

function Kora.bridge.openClothingRoom(options)
    if type(options) == 'string' then
        local menuEvents = {
            clothing = 'illenium-appearance:client:openClothingShopMenu',
            barber = 'illenium-appearance:client:OpenBarberShop',
            tattoo = 'illenium-appearance:client:OpenTattooShop',
            surgeon = 'illenium-appearance:client:OpenSurgeonShop',
            creation = 'illenium-appearance:client:openClothingShopMenu',
            wardrobe = 'illenium-appearance:client:openClothingShopMenu',
        }
        local eventName = menuEvents[options]
        if not eventName then return false, ('Unsupported illenium-appearance service %q.'):format(options) end
        TriggerEvent(eventName, options == 'creation')
        return true
    end

    local config = type(options) == 'table' and options or GetDefaultConfig()
    if type(options) ~= 'table' then
        config.components = true
        config.props = true
    end

    return appearanceResource:startPlayerCustomization(function(appearance)
        if appearance then
            TriggerServerEvent('illenium-appearance:server:saveAppearance', appearance)
        end
    end, config)
end

exports('bridge_openClothingRoom', Kora.bridge.openClothingRoom)

function Kora.bridge.applyAppearanceToPed(ped, model, appearance)
    if model then
        if ped == PlayerPedId() then
            ped = appearanceResource:setPlayerModel(model)
        else
            local modelHash = type(model) == 'number' and model or joaat(model)
            RequestModel(modelHash)
            while not HasModelLoaded(modelHash) do Wait(0) end
            SetEntityModel(ped, modelHash)
            SetModelAsNoLongerNeeded(modelHash)
        end
    end
    return appearanceResource:setPedAppearance(ped, appearance)
end

exports('bridge_applyAppearanceToPed', Kora.bridge.applyAppearanceToPed)

function Kora.bridge.applyStarterAppearance()
    TriggerEvent('illenium-appearance:client:reloadSkin')
end

exports('bridge_applyStarterAppearance', Kora.bridge.applyStarterAppearance)

function Kora.bridge.reloadSkin()
    TriggerEvent('illenium-appearance:client:reloadSkin')
end

exports('bridge_reloadSkin', Kora.bridge.reloadSkin)
