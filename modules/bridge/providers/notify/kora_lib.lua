if not IsDuplicityVersion() then
    Kora.bridge.register('notify', 'kora_lib', {
        send = function(payload)
            return Kora.notify.send(payload)
        end,
    })
end