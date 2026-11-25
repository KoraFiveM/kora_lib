return {
    addBusinessMoney = function(jobName, amount, reason)
        return exports.kora_bossmenu:addBusinessMoney(jobName, amount, reason)
    end,
    removeBusinessMoney = function(jobName, amount, reason)
        return exports.kora_bossmenu:removeBusinessMoney(jobName, amount, reason)
    end,
    getBusinessBalance = function(jobName)
        return exports.kora_bossmenu:getBusinessBalance(jobName)
    end,
    addMoney = function(jobName, amount)
        return exports.kora_bossmenu:AddMoney(jobName, amount)
    end,
    removeMoney = function(jobName, amount)
        return exports.kora_bossmenu:RemoveMoney(jobName, amount)
    end,
    addGangMoney = function(gangName, amount)
        return exports.kora_bossmenu:AddGangMoney(gangName, amount)
    end,
    removeGangMoney = function(gangName, amount)
        return exports.kora_bossmenu:RemoveGangMoney(gangName, amount)
    end,
    getGangBalance = function(gangName)
        return exports.kora_bossmenu:GetGangAccount(gangName)
    end,
}
