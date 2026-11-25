return {
    addMoney = function(name, amount, reason)
        return exports.kora_banking:AddMoney(name, amount, reason)
    end,
    removeMoney = function(name, amount, reason)
        return exports.kora_banking:RemoveMoney(name, amount, reason)
    end,
    getAccountBalance = function(name)
        return exports.kora_banking:GetAccountBalance(name)
    end,
    executeTransaction = function(key, request)
        return exports.kora_banking:ExecuteTransaction(key, request)
    end,
    createBankStatement = function(playerId, account, amount, reason, kind, accountType)
        return exports.kora_banking:CreateBankStatement(playerId, account, amount, reason, kind, accountType)
    end,
}
