return {
    giveKeys = function(src, plate, allowWhenDisabled)
        return exports.kora_vehiclekeys:giveKeys(src, plate, allowWhenDisabled)
    end,
    removeKeys = function(src, plate)
        return exports.kora_vehiclekeys:removeKeys(src, plate)
    end,
    hasKeys = function(src, plate)
        return exports.kora_vehiclekeys:hasKeys(src, plate)
    end,
}
