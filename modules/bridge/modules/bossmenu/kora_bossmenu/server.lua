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
