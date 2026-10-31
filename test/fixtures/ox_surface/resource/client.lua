-- function lib.commented() end
function lib.notify(data)
    SendNUIMessage({ action = 'notify', data = data })
end
lib.setThing = function() end
RegisterNUICallback('uiDone', function(_, cb) cb(1) end)
RegisterNetEvent('ox_lib:notify', lib.notify)
AddEventHandler(('__ox_cb_%s'):format('x'), function() end)
