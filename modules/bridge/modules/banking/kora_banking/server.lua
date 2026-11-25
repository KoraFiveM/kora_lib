
function Kora.bridge.addSocietyMoney(name, amount, reason)
    return exports.kora_banking:AddMoney(name, amount, reason)
end
function Kora.bridge.removeSocietyMoney(name, amount, reason)
    return exports.kora_banking:RemoveMoney(name, amount, reason)
end
function Kora.bridge.getSocietyAccountBalance(name)
    return exports.kora_banking:GetAccountBalance(name)
end
function Kora.bridge.executeSocietyTransaction(key, request)
    return exports.kora_banking:ExecuteTransaction(key, request)
end
function Kora.bridge.createSocietyBankStatement(playerId, account, amount, reason, kind, accountType)
    return exports.kora_banking:CreateBankStatement(playerId, account, amount, reason, kind, accountType)
end
