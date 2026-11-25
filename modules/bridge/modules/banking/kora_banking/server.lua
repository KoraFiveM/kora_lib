Kora.bridge.addSocietyMoney = function(name, amount, reason)
    return exports.kora_banking:AddMoney(name, amount, reason)
end
Kora.bridge.removeSocietyMoney = function(name, amount, reason)
    return exports.kora_banking:RemoveMoney(name, amount, reason)
end
Kora.bridge.getSocietyAccountBalance = function(name)
    return exports.kora_banking:GetAccountBalance(name)
end
Kora.bridge.executeSocietyTransaction = function(key, request)
    return exports.kora_banking:ExecuteTransaction(key, request)
end
Kora.bridge.createSocietyBankStatement = function(playerId, account, amount, reason, kind, accountType)
    return exports.kora_banking:CreateBankStatement(playerId, account, amount, reason, kind, accountType)
end
