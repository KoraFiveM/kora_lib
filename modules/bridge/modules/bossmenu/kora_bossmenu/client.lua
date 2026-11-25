function Kora.bridge.openBossMenu(roleType)
    return exports.kora_bossmenu:openBossMenu(roleType)
end

function Kora.bridge.openApplication(jobName, roleType)
    return exports.kora_bossmenu:openApplication(jobName, roleType)
end

function Kora.bridge.addBossMenuItem(data, id)
    return exports.kora_bossmenu:AddBossMenuItem(data, id)
end

function Kora.bridge.removeBossMenuItem(id)
    return exports.kora_bossmenu:RemoveBossMenuItem(id)
end

function Kora.bridge.addGangMenuItem(data, id)
    return exports.kora_bossmenu:AddGangMenuItem(data, id)
end

function Kora.bridge.removeGangMenuItem(id)
    return exports.kora_bossmenu:RemoveGangMenuItem(id)
end

exports("bridge_openBossMenu", Kora.bridge.openBossMenu)
exports("bridge_openApplication", Kora.bridge.openApplication)
exports("bridge_addBossMenuItem", Kora.bridge.addBossMenuItem)
exports("bridge_removeBossMenuItem", Kora.bridge.removeBossMenuItem)
exports("bridge_addGangMenuItem", Kora.bridge.addGangMenuItem)
exports("bridge_removeGangMenuItem", Kora.bridge.removeGangMenuItem)
