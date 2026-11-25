local serviceEvents = {
    clothing = { 'illenium-appearance:client:openClothingShopMenu', false },
    barber = { 'illenium-appearance:client:OpenBarberShop' },
    tattoo = { 'illenium-appearance:client:OpenTattooShop' },
    surgeon = { 'illenium-appearance:client:OpenSurgeonShop' },
    creation = { 'illenium-appearance:client:openClothingShopMenu', true },
}

function Kora.bridge.openAdminSession(targetSrc, service)
    local serviceEvent = serviceEvents[service]
    if not serviceEvent then
        return false, ('Unsupported illenium-appearance service %q.'):format(tostring(service))
    end

    TriggerClientEvent(serviceEvent[1], targetSrc, serviceEvent[2])
    return true
end

exports('bridge_openAdminSession', Kora.bridge.openAdminSession)
