function Kora.bridge.addBusinessMoney(jobName, amount, reason)
    return exports.kora_bossmenu:addBusinessMoney(jobName, amount, reason)
end

function Kora.bridge.removeBusinessMoney(jobName, amount, reason)
    return exports.kora_bossmenu:removeBusinessMoney(jobName, amount, reason)
end

function Kora.bridge.getBusinessBalance(jobName)
    return exports.kora_bossmenu:getBusinessBalance(jobName)
end

function Kora.bridge.bossmenuAddMoney(jobName, amount)
    return exports.kora_bossmenu:AddMoney(jobName, amount)
end

function Kora.bridge.bossmenuRemoveMoney(jobName, amount)
    return exports.kora_bossmenu:RemoveMoney(jobName, amount)
end

function Kora.bridge.addGangMoney(gangName, amount)
    return exports.kora_bossmenu:AddGangMoney(gangName, amount)
end

function Kora.bridge.removeGangMoney(gangName, amount)
    return exports.kora_bossmenu:RemoveGangMoney(gangName, amount)
end

function Kora.bridge.getGangBalance(gangName)
    return exports.kora_bossmenu:GetGangAccount(gangName)
end

exports("bridge_addBusinessMoney", Kora.bridge.addBusinessMoney)
exports("bridge_removeBusinessMoney", Kora.bridge.removeBusinessMoney)
exports("bridge_getBusinessBalance", Kora.bridge.getBusinessBalance)
exports("bridge_bossmenuAddMoney", Kora.bridge.bossmenuAddMoney)
exports("bridge_bossmenuRemoveMoney", Kora.bridge.bossmenuRemoveMoney)
exports("bridge_addGangMoney", Kora.bridge.addGangMoney)
exports("bridge_removeGangMoney", Kora.bridge.removeGangMoney)
exports("bridge_getGangBalance", Kora.bridge.getGangBalance)
