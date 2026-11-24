local adapter
if IsDuplicityVersion() then
    adapter = {
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
else
    adapter = {
        openBossMenu = function(roleType)
            return exports.kora_bossmenu:openBossMenu(roleType)
        end,
        openApplication = function(jobName, roleType)
            return exports.kora_bossmenu:openApplication(jobName, roleType)
        end,
        addBossMenuItem = function(data, id)
            return exports.kora_bossmenu:AddBossMenuItem(data, id)
        end,
        removeBossMenuItem = function(id)
            return exports.kora_bossmenu:RemoveBossMenuItem(id)
        end,
        addGangMenuItem = function(data, id)
            return exports.kora_bossmenu:AddGangMenuItem(data, id)
        end,
        removeGangMenuItem = function(id)
            return exports.kora_bossmenu:RemoveGangMenuItem(id)
        end,
    }
end

Kora.bridge.register('bossmenu', 'kora_bossmenu', adapter)