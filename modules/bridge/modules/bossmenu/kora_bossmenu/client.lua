return {
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
