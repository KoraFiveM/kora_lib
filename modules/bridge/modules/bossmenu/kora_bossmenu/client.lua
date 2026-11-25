Kora.bridge.openBossMenu = function(roleType)
    return exports.kora_bossmenu:openBossMenu(roleType)
end
Kora.bridge.openApplication = function(jobName, roleType)
    return exports.kora_bossmenu:openApplication(jobName, roleType)
end
Kora.bridge.addBossMenuItem = function(data, id)
    return exports.kora_bossmenu:AddBossMenuItem(data, id)
end
Kora.bridge.removeBossMenuItem = function(id)
    return exports.kora_bossmenu:RemoveBossMenuItem(id)
end
Kora.bridge.addGangMenuItem = function(data, id)
    return exports.kora_bossmenu:AddGangMenuItem(data, id)
end
Kora.bridge.removeGangMenuItem = function(id)
    return exports.kora_bossmenu:RemoveGangMenuItem(id)
end
