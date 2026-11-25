Kora.bridge.addBusinessMoney = function(jobName, amount, reason)
    return exports.kora_bossmenu:addBusinessMoney(jobName, amount, reason)
end
Kora.bridge.removeBusinessMoney = function(jobName, amount, reason)
    return exports.kora_bossmenu:removeBusinessMoney(jobName, amount, reason)
end
Kora.bridge.getBusinessBalance = function(jobName)
    return exports.kora_bossmenu:getBusinessBalance(jobName)
end
Kora.bridge.bossmenuAddMoney = function(jobName, amount)
    return exports.kora_bossmenu:AddMoney(jobName, amount)
end
Kora.bridge.bossmenuRemoveMoney = function(jobName, amount)
    return exports.kora_bossmenu:RemoveMoney(jobName, amount)
end
Kora.bridge.addGangMoney = function(gangName, amount)
    return exports.kora_bossmenu:AddGangMoney(gangName, amount)
end
Kora.bridge.removeGangMoney = function(gangName, amount)
    return exports.kora_bossmenu:RemoveGangMoney(gangName, amount)
end
Kora.bridge.getGangBalance = function(gangName)
    return exports.kora_bossmenu:GetGangAccount(gangName)
end
