-- QB.permissions (server realm) -- thin wrappers over FiveM's ace system. The
-- level vocabulary and ace/group namespace are caller-supplied rather than
-- baked in, so multiple resources can share this ACE-based access model
-- under their own principal prefix (e.g. 'qbcore.admin') without qblib
-- needing to know any of their vocabularies.

---Resolve the highest privilege level a player holds.
---@param src integer
---@param levels string[] -- ordered most-privileged first; 'user' always matches
---@param prefix string -- ace/group principal namespace, e.g. 'qbcore'
---@return string
function QB.permissions.getLevel(src, levels, prefix)
    for _, level in ipairs(levels) do
        if level == 'user' or IsPlayerAceAllowed(src, prefix .. '.' .. level) or IsPlayerAceAllowed(src, 'group.' .. level) then
            return level
        end
    end
    return 'user'
end

---@param src integer
---@param permission string
---@param prefix string -- ace/group/command principal namespace, e.g. 'qbcore'
---@return boolean
function QB.permissions.hasPermission(src, permission, prefix)
    if permission == 'user' then return true end
    return IsPlayerAceAllowed(src, prefix .. '.' .. permission)
        or IsPlayerAceAllowed(src, 'group.' .. permission)
        or IsPlayerAceAllowed(src, 'command.' .. permission)
end
