-- Kora.discord (server realm) -- Discord webhook delivery and a small REST bot
-- client. Webhooks do not need the bot token; every bot operation is gated by
-- kora_lib_discord_bot_token (or the deprecated qblib_discord_bot_token) and
-- fails locally when that convar is empty.

local API_BASE = 'https://discord.com/api/v10'
local USER_AGENT = 'DiscordBot (https://github.com/qbcore2/qblib, 1.0.0)'
local MAX_RATE_LIMIT_RETRIES = 1

-- The kora_lib_* convars supersede the deprecated qblib_* names, which stay
-- readable as a fallback for servers that configured them before the rename.
local function getConvar(name, legacyName, default)
    local value = GetConvar(name, '')
    if value ~= '' then return value end
    return GetConvar(legacyName, default)
end

local EMBED_TEXT_FIELDS = { 'title', 'description', 'url' }
local FOOTER_FIELDS = { 'text', 'icon_url' }
local AUTHOR_FIELDS = { 'name', 'url', 'icon_url' }
local URL_FIELDS = { 'url' }

local function assertCallback(callback)
    assert(callback == nil or Kora.compat.isCallable(callback), 'Discord callback must be callable or nil.')
end

local function decodeResponse(statusCode, body, headers, errorData)
    local response = {
        status = tonumber(statusCode) or 0,
        body = body or '',
        headers = headers or {},
    }

    if response.body ~= '' then
        local ok, decoded = pcall(json.decode, response.body)
        if ok then response.data = decoded end
    end

    if errorData and errorData ~= '' then
        response.error = tostring(errorData)
    elseif response.status < 200 or response.status >= 300 then
        response.error = type(response.data) == 'table' and response.data.message
            or (response.body ~= '' and response.body or ('Discord returned HTTP %d.'):format(response.status))
    end

    return response
end

local function performJsonRequest(url, method, payload, headers, callback)
    local body = payload == nil and '' or json.encode(payload)

    local function perform(attempt)
        PerformHttpRequest(url, function(statusCode, responseBody, responseHeaders, errorData)
            local response = decodeResponse(statusCode, responseBody, responseHeaders, errorData)

            -- Discord tells clients exactly how long a 429 bucket is closed.
            -- Retry once without blocking the resource thread, then surface a
            -- second 429 normally so callers retain control of persistent load.
            local retryAfter = response.status == 429 and type(response.data) == 'table'
                and tonumber(response.data.retry_after) or nil
            if Kora.util.isFiniteNumber(retryAfter) and retryAfter >= 0 and attempt < MAX_RATE_LIMIT_RETRIES then
                SetTimeout(math.ceil(retryAfter * 1000), function()
                    perform(attempt + 1)
                end)
                return
            end

            if callback then
                callback(response.status >= 200 and response.status < 300, response)
            end
        end, method, body, headers)
    end

    perform(0)
end

local function copyTextObject(value, label, fields)
    if type(value) == 'string' then
        return { [fields[1]] = value }
    end

    assert(type(value) == 'table', ('Discord embed %s must be a string or table.'):format(label))
    local out = {}
    for fieldIndex = 1, #fields do
        local field = fields[fieldIndex]
        local item = value[field]
        assert(item == nil or type(item) == 'string',
            ('Discord embed %s.%s must be a string.'):format(label, field))
        out[field] = item
    end
    return out
end

local function normaliseColor(color)
    if type(color) == 'string' then
        local hex = color:gsub('^#', '')
        assert(hex:match('^%x%x%x%x%x%x$'), 'Discord embed color must be a number or six-digit hex string.')
        color = tonumber(hex, 16)
    end

    assert(type(color) == 'number' and color % 1 == 0 and color >= 0 and color <= 0xFFFFFF,
        'Discord embed color must be an integer between 0 and 16777215.')
    return color
end

---Create a validated Discord embed table. The returned table has no builder
---methods, so it can cross FiveM's export boundary and be JSON-encoded safely.
---@param options table
---@return table embed
function Kora.discord.createEmbed(options)
    assert(type(options) == 'table', 'Discord embed options must be a table.')

    local embed = {}
    for i = 1, #EMBED_TEXT_FIELDS do
        local field = EMBED_TEXT_FIELDS[i]
        local value = options[field]
        assert(value == nil or type(value) == 'string', ('Discord embed %s must be a string.'):format(field))
        embed[field] = value
    end

    if options.color ~= nil then embed.color = normaliseColor(options.color) end

    if options.timestamp ~= nil then
        assert(options.timestamp == true or type(options.timestamp) == 'string' or Kora.util.isFiniteNumber(options.timestamp),
            'Discord embed timestamp must be true, a finite Unix timestamp, or an ISO8601 string.')
        if options.timestamp == true then
            embed.timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ')
        elseif type(options.timestamp) == 'number' then
            embed.timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ', math.floor(options.timestamp))
        else
            embed.timestamp = options.timestamp
        end
    end

    if options.footer ~= nil then
        embed.footer = copyTextObject(options.footer, 'footer', FOOTER_FIELDS)
        assert(type(embed.footer.text) == 'string', 'Discord embed footer.text is required.')
    end
    if options.author ~= nil then
        embed.author = copyTextObject(options.author, 'author', AUTHOR_FIELDS)
        assert(type(embed.author.name) == 'string', 'Discord embed author.name is required.')
    end
    if options.image ~= nil then
        embed.image = copyTextObject(options.image, 'image', URL_FIELDS)
        assert(type(embed.image.url) == 'string', 'Discord embed image.url is required.')
    end
    if options.thumbnail ~= nil then
        embed.thumbnail = copyTextObject(options.thumbnail, 'thumbnail', URL_FIELDS)
        assert(type(embed.thumbnail.url) == 'string', 'Discord embed thumbnail.url is required.')
    end

    if options.fields ~= nil then
        assert(type(options.fields) == 'table', 'Discord embed fields must be an array.')
        assert(#options.fields <= 25, 'Discord embeds support at most 25 fields.')
        local fieldCount = 0
        for index in pairs(options.fields) do
            assert(type(index) == 'number' and index >= 1 and index % 1 == 0
                and index == index and index < math.huge,
                'Discord embed fields must be a dense array.')
            fieldCount = fieldCount + 1
        end
        assert(fieldCount == #options.fields, 'Discord embed fields must be a dense array.')
        embed.fields = {}

        for index = 1, #options.fields do
            local field = options.fields[index]
            assert(type(field) == 'table', ('Discord embed field %d must be a table.'):format(index))
            assert(type(field.name) == 'string', ('Discord embed field %d name must be a string.'):format(index))
            assert(type(field.value) == 'string', ('Discord embed field %d value must be a string.'):format(index))
            assert(field.inline == nil or type(field.inline) == 'boolean',
                ('Discord embed field %d inline must be a boolean.'):format(index))
            embed.fields[index] = { name = field.name, value = field.value, inline = field.inline }
        end
    end

    return embed
end

local function looksLikeEmbed(payload)
    if payload.content ~= nil or payload.embeds ~= nil then return false end
    return payload.title ~= nil or payload.description ~= nil or payload.fields ~= nil
        or payload.footer ~= nil or payload.author ~= nil or payload.image ~= nil
        or payload.thumbnail ~= nil or payload.color ~= nil or payload.timestamp ~= nil
end

local function normaliseMessagePayload(payload)
    if type(payload) == 'string' then return { content = payload } end
    assert(type(payload) == 'table', 'Discord message payload must be a string or table.')
    if looksLikeEmbed(payload) then return { embeds = { payload } } end
    return payload
end

---Post a webhook message. Pass nil as url to use kora_lib_discord_webhook.
---This API remains available whether or not the bot token convar is set.
---@param url string|nil
---@param payload string|table
---@param callback fun(ok:boolean, response:table)|nil
---@return boolean queued
function Kora.discord.sendWebhook(url, payload, callback)
    assertCallback(callback)
    assert(url == nil or type(url) == 'string', 'Discord webhook URL must be a string or nil.')

    url = url and url:match('^%s*(.-)%s*$') or getConvar('kora_lib_discord_webhook', 'qblib_discord_webhook', '')
    if url == '' then
        if callback then
            callback(false, { status = 0, error = 'Discord webhook is not configured.' })
        end
        return false
    end

    assert(url:match('^https://'), 'Discord webhook URL must use HTTPS.')
    payload = normaliseMessagePayload(payload)
    if payload.embeds ~= nil then
        assert(type(payload.embeds) == 'table' and #payload.embeds <= 10,
            'Discord webhook embeds must be an array of at most 10 embeds.')
    end

    performJsonRequest(url, 'POST', payload, { ['Content-Type'] = 'application/json' }, callback)
    return true
end

local function botToken()
    return getConvar('kora_lib_discord_bot_token', 'qblib_discord_bot_token', '')
end

---Return whether the REST bot client is enabled by its token convar.
---@return boolean
function Kora.discord.botEnabled()
    return botToken() ~= ''
end

local function botDisabled(callback)
    assertCallback(callback)
    if callback then
        callback(false, {
            status = 0,
            error = 'Discord bot is disabled; set kora_lib_discord_bot_token to enable it.',
        })
    end
    return false
end

local function requireSnowflake(value, label)
    -- Discord snowflakes exceed Lua/JSON's safe integer range. Requiring a
    -- decimal string prevents silent precision loss in routes.
    assert(type(value) == 'string' and value:match('^%d+$'),
        ('Discord %s must be a decimal string.'):format(label))
    return value
end

local function resolveGuildId(guildId)
    if guildId == nil or guildId == '' then
        guildId = getConvar('kora_lib_discord_guild_id', 'qblib_discord_guild_id', '')
    end
    assert(guildId ~= '', 'Discord guild ID is required (argument or kora_lib_discord_guild_id).')
    return requireSnowflake(guildId, 'guild ID')
end

local function encodeAuditReason(reason)
    if reason == nil then return nil end
    assert(type(reason) == 'string' and #reason > 0 and #reason <= 512,
        'Discord audit reason must be a non-empty string of at most 512 bytes.')
    return (reason:gsub('[^%w%-%._~]', function(char)
        return ('%%%02X'):format(char:byte())
    end))
end

local BOT_METHODS = { GET = true, POST = true, PUT = true, PATCH = true, DELETE = true }

---Perform an authenticated Discord API v10 request. route must be relative to
---https://discord.com/api/v10 so the bot credential can never be sent to an
---arbitrary host.
---@param method string
---@param route string
---@param payload table|nil
---@param callback fun(ok:boolean, response:table)|nil
---@param auditReason string|nil
---@return boolean queued
function Kora.discord.botRequest(method, route, payload, callback, auditReason)
    assertCallback(callback)
    local token = botToken()
    if token == '' then return botDisabled(callback) end

    assert(type(method) == 'string' and BOT_METHODS[method:upper()],
        'Discord bot method must be GET, POST, PUT, PATCH, or DELETE.')
    method = method:upper()
    assert(type(route) == 'string' and route:sub(1, 1) == '/' and not route:find('://', 1, true)
        and not route:find('[\r\n]'), 'Discord bot route must be a relative API path.')
    assert(payload == nil or type(payload) == 'table', 'Discord bot payload must be a table or nil.')

    local headers = {
        ['Authorization'] = 'Bot ' .. token,
        ['Content-Type'] = 'application/json',
        ['User-Agent'] = USER_AGENT,
    }
    local encodedReason = encodeAuditReason(auditReason)
    if encodedReason then headers['X-Audit-Log-Reason'] = encodedReason end

    performJsonRequest(API_BASE .. route, method, payload, headers, callback)
    return true
end

local function requireBot(callback)
    if Kora.discord.botEnabled() then return true end
    botDisabled(callback)
    return false
end

---@param guildId string|nil Defaults to kora_lib_discord_guild_id.
---@param callback function|nil
---@return boolean queued
function Kora.discord.getGuild(guildId, callback)
    if Kora.compat.isCallable(guildId) and callback == nil then callback, guildId = guildId, nil end
    if not requireBot(callback) then return false end
    return Kora.discord.botRequest('GET', '/guilds/' .. resolveGuildId(guildId), nil, callback)
end

---@param guildId string|nil
---@param userId string
---@param callback function|nil
---@return boolean queued
function Kora.discord.getMember(guildId, userId, callback)
    if not requireBot(callback) then return false end
    local route = ('/guilds/%s/members/%s'):format(resolveGuildId(guildId), requireSnowflake(userId, 'user ID'))
    return Kora.discord.botRequest('GET', route, nil, callback)
end

---@param guildId string|nil
---@param userId string
---@param attributes table Discord Modify Guild Member fields.
---@param callback function|nil
---@param auditReason string|nil
---@return boolean queued
function Kora.discord.updateMember(guildId, userId, attributes, callback, auditReason)
    if not requireBot(callback) then return false end
    assert(type(attributes) == 'table', 'Discord member attributes must be a table.')
    local route = ('/guilds/%s/members/%s'):format(resolveGuildId(guildId), requireSnowflake(userId, 'user ID'))
    return Kora.discord.botRequest('PATCH', route, attributes, callback, auditReason)
end

---@param guildId string|nil
---@param callback function|nil
---@return boolean queued
function Kora.discord.fetchGuildRoles(guildId, callback)
    if Kora.compat.isCallable(guildId) and callback == nil then callback, guildId = guildId, nil end
    if not requireBot(callback) then return false end
    return Kora.discord.botRequest('GET', '/guilds/' .. resolveGuildId(guildId) .. '/roles', nil, callback)
end

---@param guildId string|nil
---@param userId string
---@param roleIds string[]
---@param callback function|nil
---@param auditReason string|nil
---@return boolean queued
function Kora.discord.setMemberRoles(guildId, userId, roleIds, callback, auditReason)
    if not requireBot(callback) then return false end
    assert(type(roleIds) == 'table', 'Discord role IDs must be an array.')
    local roles = {}
    for index = 1, #roleIds do roles[index] = requireSnowflake(roleIds[index], 'role ID') end
    return Kora.discord.updateMember(guildId, userId, { roles = roles }, callback, auditReason)
end

---@param guildId string|nil
---@param userId string
---@param roleId string
---@param callback function|nil
---@param auditReason string|nil
---@return boolean queued
function Kora.discord.addMemberRole(guildId, userId, roleId, callback, auditReason)
    if not requireBot(callback) then return false end
    local route = ('/guilds/%s/members/%s/roles/%s'):format(
        resolveGuildId(guildId), requireSnowflake(userId, 'user ID'), requireSnowflake(roleId, 'role ID'))
    return Kora.discord.botRequest('PUT', route, nil, callback, auditReason)
end

---@param guildId string|nil
---@param userId string
---@param roleId string
---@param callback function|nil
---@param auditReason string|nil
---@return boolean queued
function Kora.discord.removeMemberRole(guildId, userId, roleId, callback, auditReason)
    if not requireBot(callback) then return false end
    local route = ('/guilds/%s/members/%s/roles/%s'):format(
        resolveGuildId(guildId), requireSnowflake(userId, 'user ID'), requireSnowflake(roleId, 'role ID'))
    return Kora.discord.botRequest('DELETE', route, nil, callback, auditReason)
end

---@param guildId string|nil
---@param role table Discord Create Guild Role fields.
---@param callback function|nil
---@param auditReason string|nil
---@return boolean queued
function Kora.discord.createRole(guildId, role, callback, auditReason)
    if not requireBot(callback) then return false end
    assert(type(role) == 'table', 'Discord role must be a table.')
    return Kora.discord.botRequest('POST', '/guilds/' .. resolveGuildId(guildId) .. '/roles', role, callback, auditReason)
end

---@param guildId string|nil
---@param roleId string
---@param role table Discord Modify Guild Role fields.
---@param callback function|nil
---@param auditReason string|nil
---@return boolean queued
function Kora.discord.updateRole(guildId, roleId, role, callback, auditReason)
    if not requireBot(callback) then return false end
    assert(type(role) == 'table', 'Discord role must be a table.')
    local route = ('/guilds/%s/roles/%s'):format(resolveGuildId(guildId), requireSnowflake(roleId, 'role ID'))
    return Kora.discord.botRequest('PATCH', route, role, callback, auditReason)
end

---@param guildId string|nil
---@param roleId string
---@param callback function|nil
---@param auditReason string|nil
---@return boolean queued
function Kora.discord.deleteRole(guildId, roleId, callback, auditReason)
    if not requireBot(callback) then return false end
    local route = ('/guilds/%s/roles/%s'):format(resolveGuildId(guildId), requireSnowflake(roleId, 'role ID'))
    return Kora.discord.botRequest('DELETE', route, nil, callback, auditReason)
end

---@param guildId string|nil
---@param callback function|nil
---@return boolean queued
function Kora.discord.getChannels(guildId, callback)
    if Kora.compat.isCallable(guildId) and callback == nil then callback, guildId = guildId, nil end
    if not requireBot(callback) then return false end
    return Kora.discord.botRequest('GET', '/guilds/' .. resolveGuildId(guildId) .. '/channels', nil, callback)
end

---@param channelId string
---@param callback function|nil
---@return boolean queued
function Kora.discord.getChannel(channelId, callback)
    if not requireBot(callback) then return false end
    return Kora.discord.botRequest('GET', '/channels/' .. requireSnowflake(channelId, 'channel ID'), nil, callback)
end

---@param guildId string|nil
---@param channel table Discord Create Guild Channel fields; name is required by Discord.
---@param callback function|nil
---@param auditReason string|nil
---@return boolean queued
function Kora.discord.createChannel(guildId, channel, callback, auditReason)
    if not requireBot(callback) then return false end
    assert(type(channel) == 'table' and type(channel.name) == 'string',
        'Discord channel must be a table with a string name.')
    return Kora.discord.botRequest('POST', '/guilds/' .. resolveGuildId(guildId) .. '/channels', channel, callback, auditReason)
end

---@param channelId string
---@param attributes table Discord Modify Channel fields.
---@param callback function|nil
---@param auditReason string|nil
---@return boolean queued
function Kora.discord.updateChannel(channelId, attributes, callback, auditReason)
    if not requireBot(callback) then return false end
    assert(type(attributes) == 'table', 'Discord channel attributes must be a table.')
    return Kora.discord.botRequest('PATCH', '/channels/' .. requireSnowflake(channelId, 'channel ID'), attributes,
        callback, auditReason)
end

---@param channelId string
---@param callback function|nil
---@param auditReason string|nil
---@return boolean queued
function Kora.discord.deleteChannel(channelId, callback, auditReason)
    if not requireBot(callback) then return false end
    return Kora.discord.botRequest('DELETE', '/channels/' .. requireSnowflake(channelId, 'channel ID'), nil,
        callback, auditReason)
end

---@param channelId string
---@param payload string|table Discord Create Message fields.
---@param callback function|nil
---@return boolean queued
function Kora.discord.sendMessage(channelId, payload, callback)
    if not requireBot(callback) then return false end
    return Kora.discord.botRequest('POST', '/channels/' .. requireSnowflake(channelId, 'channel ID') .. '/messages',
        normaliseMessagePayload(payload), callback)
end

---@param channelId string
---@param messageId string
---@param payload string|table Discord Edit Message fields.
---@param callback function|nil
---@return boolean queued
function Kora.discord.editMessage(channelId, messageId, payload, callback)
    if not requireBot(callback) then return false end
    local route = ('/channels/%s/messages/%s'):format(
        requireSnowflake(channelId, 'channel ID'), requireSnowflake(messageId, 'message ID'))
    return Kora.discord.botRequest('PATCH', route, normaliseMessagePayload(payload), callback)
end

---@param channelId string
---@param messageId string
---@param callback function|nil
---@param auditReason string|nil
---@return boolean queued
function Kora.discord.deleteMessage(channelId, messageId, callback, auditReason)
    if not requireBot(callback) then return false end
    local route = ('/channels/%s/messages/%s'):format(
        requireSnowflake(channelId, 'channel ID'), requireSnowflake(messageId, 'message ID'))
    return Kora.discord.botRequest('DELETE', route, nil, callback, auditReason)
end

-- Cached/persisted role directory
-- Caches are guild-keyed so low-level calls to another guild can't contaminate the
-- default guild's authorization data.
local guildRoleCache = {}   -- guildId -> { byId, byName, list, syncedAt }
local guildMemberCache = {} -- guildId -> userId -> { roles = set, syncedAt, stale }
local databaseReady = false
local databaseInitializing = false
local databaseWarningPrinted = false
local syncInProgress = false

local function discordConfig(name, fallback)
    return Config and Config.discord and Config.discord[name] or fallback
end

local function copyRole(role)
    return {
        id = role.id,
        name = role.name,
        color = role.color,
        position = role.position,
        permissions = role.permissions,
        managed = role.managed,
        mentionable = role.mentionable,
    }
end

local function cacheGuildRoles(guildId, roles, syncedAt)
    local cache = { byId = {}, byName = {}, list = {}, syncedAt = syncedAt or os.time() }

    roles = roles or {}
    for roleIndex = 1, #roles do
        local rawRole = roles[roleIndex]
        if type(rawRole) == 'table' and type(rawRole.id) == 'string' and type(rawRole.name) == 'string' then
            local role = copyRole(rawRole)
            role.color = tonumber(role.color) or 0
            role.position = tonumber(role.position) or 0
            role.permissions = tostring(role.permissions or '0')
            role.managed = role.managed == true or role.managed == 1
            role.mentionable = role.mentionable == true or role.mentionable == 1
            cache.byId[role.id] = role
            cache.list[#cache.list + 1] = role

            local key = role.name:lower()
            if cache.byName[key] == nil then
                cache.byName[key] = role.id
            else
                -- Discord permits duplicate role names. Name-based mutation is
                -- unsafe in that case, so retain an explicit ambiguity marker.
                cache.byName[key] = false
            end
        end
    end

    table.sort(cache.list, function(a, b)
        if a.position ~= b.position then return a.position > b.position end
        return a.name:lower() < b.name:lower()
    end)
    guildRoleCache[guildId] = cache
    return cache
end

local function cacheMemberRoles(guildId, userId, roleIds, syncedAt)
    guildMemberCache[guildId] = guildMemberCache[guildId] or {}
    local entry = { roles = {}, syncedAt = syncedAt or os.time(), stale = false }
    roleIds = roleIds or {}
    for roleIndex = 1, #roleIds do
        local roleId = roleIds[roleIndex]
        if type(roleId) == 'string' and roleId:match('^%d+$') then entry.roles[roleId] = true end
    end
    guildMemberCache[guildId][userId] = entry
    return entry
end

local function markMemberStale(guildId, userId)
    local entry = guildMemberCache[guildId] and guildMemberCache[guildId][userId]
    if entry then entry.stale = true end
end

local function memberIsFresh(entry)
    if not entry or entry.stale then return false end
    local maxAgeSeconds = math.max(1, discordConfig('cacheMaxAge', 600000) / 1000)
    return os.time() - (tonumber(entry.syncedAt) or 0) <= maxAgeSeconds
end

local function discordIdForPlayer(src)
    src = tonumber(src)
    if not src then return nil end
    for index = 0, GetNumPlayerIdentifiers(src) - 1 do
        local identifier = GetPlayerIdentifier(src, index)
        local id = identifier and identifier:match('^discord:(%d+)$')
        if id then return id end
    end
    return nil
end

local function resolveUserId(id)
    if type(id) == 'number' then
        local discordId = discordIdForPlayer(id)
        if not discordId then return nil, ('Player %s has no Discord identifier.'):format(tostring(id)) end
        return discordId
    end

    if type(id) ~= 'string' then return nil, 'Discord user ID must be a decimal string or online server ID.' end
    id = id:match('^%s*(.-)%s*$')
    id = id:match('^discord:(%d+)$') or id
    if not id:match('^%d+$') then return nil, 'Discord user ID must be a decimal string.' end
    return id
end

local function resolveCachedRole(guildId, role)
    if type(role) ~= 'string' then return nil, 'Discord role must be a role ID or name string.' end
    role = role:match('^%s*(.-)%s*$')
    if role == '' then return nil, 'Discord role cannot be empty.' end

    local cache = guildRoleCache[guildId]
    if not cache then return nil, 'Discord guild role catalog is not cached yet.' end
    if cache.byId[role] then return role, cache.byId[role] end

    local roleId = cache.byName[role:lower()]
    if roleId == false then return nil, ('Discord role name %q is ambiguous; use its role ID.'):format(role) end
    if not roleId then return nil, ('Discord role %q was not found.'):format(role) end
    return roleId, cache.byId[roleId]
end

local function fnv1a(value)
    local hash = 0xCBF29CE484222325
    local prime = 0x100000001B3
    for index = 1, #value do
        hash = hash ~ value:byte(index)
        hash = (hash * prime) & 0xFFFFFFFFFFFFFFFF
    end
    return hash
end

local function migrationChecksum(value)
    return (('%016x%016x'):format(fnv1a(value), fnv1a(value:reverse())) .. string.rep('0', 32))
end

local function awaitSql(invoke)
    local pending = promise.new()
    invoke(function(result, err)
        pending:resolve({ result = result, error = err })
    end)
    local ok, response = pcall(Citizen.Await, pending)
    if not ok then return nil, tostring(response) end
    if response.error then return nil, tostring(response.error) end
    return response.result
end

local function sqlQuery(sql, params)
    local resource = GetCurrentResourceName()
    return awaitSql(function(callback)
        exports.kora_sql:query(sql, params or {}, callback, resource)
    end)
end

local function sqlTransaction(statements)
    local resource = GetCurrentResourceName()
    return awaitSql(function(callback)
        exports.kora_sql:transaction(statements, nil, callback, resource)
    end)
end

local function waitForQbSql()
    local deadline = GetGameTimer() + discordConfig('databaseTimeout', 60000)

    while true do
        local state = GetResourceState('kora_sql')
        if state == 'missing' or state == 'stopped' or state == 'uninitialized' then
            return false, ('qbsql is %s'):format(state)
        end
        if state == 'started' then
            local ok, ready = pcall(function() return exports.kora_sql:isReady() end)
            if ok and ready then return true end
        end
        if GetGameTimer() >= deadline then return false, 'qbsql did not become ready before the timeout' end
        Wait(100)
    end
end

local function loadDatabaseCache()
    local roleRows, roleErr = sqlQuery([[
        SELECT `guild_id`,`role_id` AS `id`,`name`,`color`,`position`,`permissions`,`managed`,`mentionable`
        FROM `qblib_discord_roles`
    ]])
    if not roleRows then return false, roleErr end

    local rolesByGuild = {}
    for roleIndex = 1, #roleRows do
        local role = roleRows[roleIndex]
        rolesByGuild[role.guild_id] = rolesByGuild[role.guild_id] or {}
        rolesByGuild[role.guild_id][#rolesByGuild[role.guild_id] + 1] = role
    end
    for guildId, roles in pairs(rolesByGuild) do
        if not guildRoleCache[guildId] then cacheGuildRoles(guildId, roles, 0) end
    end

    local memberRows, memberErr = sqlQuery('SELECT `guild_id`,`user_id`,`synced_at` FROM `qblib_discord_members`')
    if not memberRows then return false, memberErr end
    local loadedMembers = {}
    for memberIndex = 1, #memberRows do
        local member = memberRows[memberIndex]
        guildMemberCache[member.guild_id] = guildMemberCache[member.guild_id] or {}
        if not guildMemberCache[member.guild_id][member.user_id] then
            cacheMemberRoles(member.guild_id, member.user_id, {}, tonumber(member.synced_at) or 0)
            loadedMembers[member.guild_id .. ':' .. member.user_id] = true
        end
    end

    local assignmentRows, assignmentErr = sqlQuery(
        'SELECT `guild_id`,`user_id`,`role_id` FROM `qblib_discord_member_roles`')
    if not assignmentRows then return false, assignmentErr end
    for assignmentIndex = 1, #assignmentRows do
        local assignment = assignmentRows[assignmentIndex]
        local guild = guildMemberCache[assignment.guild_id]
        local member = guild and guild[assignment.user_id]
        if member and loadedMembers[assignment.guild_id .. ':' .. assignment.user_id] then
            member.roles[assignment.role_id] = true
        end
    end
    return true
end

local function ensureDatabase()
    if databaseReady then return true end
    if databaseInitializing then return false, 'Discord database initialization is already in progress.' end
    databaseInitializing = true

    local ready, readyErr = waitForQbSql()
    if not ready then
        databaseInitializing = false
        if not databaseWarningPrinted then
            databaseWarningPrinted = true
            print(('^3[kora_lib:discord]^7 %s; role caching will be memory-only.'):format(readyErr))
        end
        return false, readyErr
    end

    local resource = GetCurrentResourceName()
    local sql = LoadResourceFile(resource, 'modules/discord/sql/001_discord.sql')
    if not sql then
        databaseInitializing = false
        return false, 'missing modules/discord/sql/001_discord.sql'
    end

    local migrated, migrateErr = awaitSql(function(callback)
        exports.kora_sql:migrate(resource, {
            {
                version = 1,
                name = 'discord_roles',
                sql = sql,
                checksum = migrationChecksum(sql),
            },
        }, callback, resource)
    end)
    if not migrated then
        databaseInitializing = false
        return false, migrateErr
    end

    local loaded, loadErr = loadDatabaseCache()
    databaseInitializing = false
    if not loaded then return false, loadErr end
    databaseReady = true
    return true
end

local function persistGuildRoles(guildId, roles)
    if not databaseReady then return false, 'Discord role database is unavailable.' end
    local statements = {}

    if #roles > 0 then
        local values, params = {}, {}
        for roleIndex = 1, #roles do
            local role = roles[roleIndex]
            values[#values + 1] = '(?,?,?,?,?,?,?,?)'
            params[#params + 1] = guildId
            params[#params + 1] = role.id
            params[#params + 1] = role.name
            params[#params + 1] = tonumber(role.color) or 0
            params[#params + 1] = tonumber(role.position) or 0
            params[#params + 1] = tostring(role.permissions or '0')
            params[#params + 1] = role.managed and 1 or 0
            params[#params + 1] = role.mentionable and 1 or 0
        end
        statements[#statements + 1] = {
            query = [[
                INSERT INTO `qblib_discord_roles`
                    (`guild_id`,`role_id`,`name`,`color`,`position`,`permissions`,`managed`,`mentionable`)
                VALUES ]] .. table.concat(values, ',') .. [[
                ON DUPLICATE KEY UPDATE
                    `name`=VALUES(`name`),`color`=VALUES(`color`),`position`=VALUES(`position`),
                    `permissions`=VALUES(`permissions`),`managed`=VALUES(`managed`),
                    `mentionable`=VALUES(`mentionable`)
            ]],
            values = params,
        }
    end

    local deleteParams = { guildId }
    local deleteSql = 'DELETE FROM `qblib_discord_roles` WHERE `guild_id` = ?'
    if #roles > 0 then
        local placeholders = {}
        for roleIndex = 1, #roles do
            local role = roles[roleIndex]
            placeholders[#placeholders + 1] = '?'
            deleteParams[#deleteParams + 1] = role.id
        end
        deleteSql = deleteSql .. ' AND `role_id` NOT IN (' .. table.concat(placeholders, ',') .. ')'
    end
    statements[#statements + 1] = { query = deleteSql, values = deleteParams }

    local result, err = sqlTransaction(statements)
    return result ~= nil, err
end

local function persistMemberRoles(guildId, userId, entry)
    if not databaseReady then return false, 'Discord role database is unavailable.' end
    local statements = {
        {
            query = [[
                INSERT INTO `qblib_discord_members` (`guild_id`,`user_id`,`synced_at`) VALUES (?,?,?)
                ON DUPLICATE KEY UPDATE `synced_at`=VALUES(`synced_at`)
            ]],
            values = { guildId, userId, entry.syncedAt },
        },
        {
            query = 'DELETE FROM `qblib_discord_member_roles` WHERE `guild_id` = ? AND `user_id` = ?',
            values = { guildId, userId },
        },
    }

    local roleIds = {}
    for roleId in pairs(entry.roles) do roleIds[#roleIds + 1] = roleId end
    table.sort(roleIds)
    if #roleIds > 0 then
        local values, params = {}, {}
        for roleIdIndex = 1, #roleIds do
            local roleId = roleIds[roleIdIndex]
            values[#values + 1] = '(?,?,?)'
            params[#params + 1] = guildId
            params[#params + 1] = userId
            params[#params + 1] = roleId
        end
        statements[#statements + 1] = {
            query = 'INSERT INTO `qblib_discord_member_roles` (`guild_id`,`user_id`,`role_id`) VALUES '
                .. table.concat(values, ','),
            values = params,
        }
    end

    local result, err = sqlTransaction(statements)
    return result ~= nil, err
end

local function persistMemberSoon(guildId, userId, entry)
    CreateThread(function()
        local ready, readyErr = ensureDatabase()
        if not ready then return end
        local ok, err = persistMemberRoles(guildId, userId, entry)
        if not ok then
            print(('^3[kora_lib:discord]^7 could not persist roles for %s: %s'):format(userId, tostring(err or readyErr)))
        end
    end)
end

local function localFailure(callback, message)
    assertCallback(callback)
    if callback then callback(false, { status = 0, error = message }) end
    return false
end

---Return the cached guild role catalog, ordered from highest to lowest role.
---@param guildId string|nil Defaults to kora_lib_discord_guild_id.
---@return table[]|nil roles
---@return string|nil error
function Kora.discord.getGuildRoles(guildId)
    if not Kora.discord.botEnabled() then return nil, 'Discord bot is disabled.' end
    local ok, resolved = pcall(resolveGuildId, guildId)
    if not ok then return nil, tostring(resolved) end
    local cache = guildRoleCache[resolved]
    if not cache then return nil, 'Discord guild role catalog is not cached yet.' end
    local out = {}
    for index = 1, #cache.list do out[index] = copyRole(cache.list[index]) end
    return out
end

---Resolve a cached role by exact ID or case-insensitive name.
---@param role string
---@param guildId string|nil
---@return table|nil role
---@return string|nil error
function Kora.discord.getRole(role, guildId)
    if not Kora.discord.botEnabled() then return nil, 'Discord bot is disabled.' end
    local ok, resolved = pcall(resolveGuildId, guildId)
    if not ok then return nil, tostring(resolved) end
    local _, cachedOrErr = resolveCachedRole(resolved, role)
    if type(cachedOrErr) == 'string' then return nil, cachedOrErr end
    return copyRole(cachedOrErr)
end

---Refresh one member from Discord and replace their cached/persisted role set.
---id may be a Discord ID string, a discord:<id> string, or an online server ID.
---@param id string|integer
---@param callback fun(ok:boolean, response:table)|nil
---@return boolean queued
function Kora.discord.refreshMember(id, callback)
    if not requireBot(callback) then return false end
    local userId, userErr = resolveUserId(id)
    if not userId then return localFailure(callback, userErr) end
    local ok, guildId = pcall(resolveGuildId, nil)
    if not ok then return localFailure(callback, tostring(guildId)) end

    return Kora.discord.getMember(guildId, userId, function(requestOk, response)
        if requestOk and type(response.data) == 'table' and type(response.data.roles) == 'table' then
            local entry = cacheMemberRoles(guildId, userId, response.data.roles)
            persistMemberSoon(guildId, userId, entry)
        elseif response.status == 404 then
            -- A confirmed non-member has a fresh, empty role set. This makes
            -- authorization fail closed while preserving a useful lookup.
            local entry = cacheMemberRoles(guildId, userId, {})
            persistMemberSoon(guildId, userId, entry)
        else
            markMemberStale(guildId, userId)
        end
        if callback then callback(requestOk, response) end
    end)
end

---Return a member's cached role objects. Stale data is returned for display,
---but accompanied by an error; hasRole/hasRoles reject it for authorization.
---@param id string|integer
---@return table[]|nil roles
---@return string|nil error
function Kora.discord.getRoles(id)
    if not Kora.discord.botEnabled() then return nil, 'Discord bot is disabled.' end
    local userId, userErr = resolveUserId(id)
    if not userId then return nil, userErr end
    local ok, guildId = pcall(resolveGuildId, nil)
    if not ok then return nil, tostring(guildId) end
    local entry = guildMemberCache[guildId] and guildMemberCache[guildId][userId]
    if not entry then return nil, 'Discord member roles are not cached yet.' end

    local roles, catalog = {}, guildRoleCache[guildId]
    for roleId in pairs(entry.roles) do
        local role = catalog and catalog.byId[roleId]
        roles[#roles + 1] = role and copyRole(role) or { id = roleId, name = roleId }
    end
    table.sort(roles, function(a, b)
        local ap, bp = tonumber(a.position) or -1, tonumber(b.position) or -1
        if ap ~= bp then return ap > bp end
        return tostring(a.name):lower() < tostring(b.name):lower()
    end)
    if not memberIsFresh(entry) then return roles, 'Discord member role cache is stale.' end
    return roles
end

---@param id string|integer
---@param role string Role ID or name.
---@return boolean hasRole
---@return string|nil error
function Kora.discord.hasRole(id, role)
    if not Kora.discord.botEnabled() then return false, 'Discord bot is disabled.' end
    local userId, userErr = resolveUserId(id)
    if not userId then return false, userErr end
    local ok, guildId = pcall(resolveGuildId, nil)
    if not ok then return false, tostring(guildId) end
    local entry = guildMemberCache[guildId] and guildMemberCache[guildId][userId]
    if not memberIsFresh(entry) then return false, 'Discord member roles are missing or stale.' end
    local roleId, roleErr = resolveCachedRole(guildId, role)
    if not roleId then return false, roleErr end
    return entry.roles[roleId] == true
end

---Check several role names/IDs. requireAll defaults to true.
---@param id string|integer
---@param roles string[]|string
---@param requireAll boolean|nil
---@return boolean matches
---@return string|nil error
function Kora.discord.hasRoles(id, roles, requireAll)
    if type(roles) == 'string' then roles = { roles } end
    if type(roles) ~= 'table' or #roles == 0 then return false, 'Discord roles must be a non-empty array or string.' end
    requireAll = requireAll ~= false

    for roleIndex = 1, #roles do
        local role = roles[roleIndex]
        local has, err = Kora.discord.hasRole(id, role)
        if err then return false, err end
        if requireAll and not has then return false end
        if not requireAll and has then return true end
    end
    return requireAll
end

---@param id string|integer
---@param roles string[]|string
---@return boolean matches
---@return string|nil error
function Kora.discord.hasAnyRole(id, roles)
    return Kora.discord.hasRoles(id, roles, false)
end

---@param id string|integer
---@param roles string[]|string
---@return boolean matches
---@return string|nil error
function Kora.discord.hasAllRoles(id, roles)
    return Kora.discord.hasRoles(id, roles, true)
end

local function mutateCachedRole(action, id, role, callback, auditReason)
    if not requireBot(callback) then return false end
    local userId, userErr = resolveUserId(id)
    if not userId then return localFailure(callback, userErr) end
    local ok, guildId = pcall(resolveGuildId, nil)
    if not ok then return localFailure(callback, tostring(guildId)) end
    local roleId, roleErr = resolveCachedRole(guildId, role)
    if not roleId then return localFailure(callback, roleErr) end

    local operation = action == 'give' and Kora.discord.addMemberRole or Kora.discord.removeMemberRole
    return operation(guildId, userId, roleId, function(requestOk, response)
        if not requestOk then
            if callback then callback(false, response) end
            return
        end

        local entry = guildMemberCache[guildId] and guildMemberCache[guildId][userId]
        if memberIsFresh(entry) then
            entry.roles[roleId] = action == 'give' or nil
            entry.syncedAt = os.time()
            persistMemberSoon(guildId, userId, entry)
            if callback then callback(true, response) end
            return
        end

        -- A delta cannot make an absent/stale snapshot complete. Re-fetch the
        -- whole member before declaring the local authorization cache current.
        Kora.discord.refreshMember(userId, function(refreshOk, refreshResponse)
            response.cacheRefreshed = refreshOk
            if not refreshOk then response.cacheError = refreshResponse and refreshResponse.error end
            if callback then callback(true, response) end
        end)
    end, auditReason)
end

---Give a member a role by role ID or case-insensitive cached role name.
---@param id string|integer Discord user ID or online server ID.
---@param role string
---@param callback function|nil
---@param auditReason string|nil
---@return boolean queued
function Kora.discord.giveRole(id, role, callback, auditReason)
    return mutateCachedRole('give', id, role, callback, auditReason)
end

---Remove a member role by role ID or case-insensitive cached role name.
---@param id string|integer Discord user ID or online server ID.
---@param role string
---@param callback function|nil
---@param auditReason string|nil
---@return boolean queued
function Kora.discord.removeRole(id, role, callback, auditReason)
    return mutateCachedRole('remove', id, role, callback, auditReason)
end

local function awaitRest(invoke)
    local pending = promise.new()
    invoke(function(ok, response) pending:resolve({ ok = ok, response = response }) end)
    local ok, result = pcall(Citizen.Await, pending)
    if not ok then return false, { status = 0, error = tostring(result) } end
    return result.ok, result.response
end

local function runFullRoleSync()
    local ok, guildId = pcall(resolveGuildId, nil)
    if not ok then return false, tostring(guildId) end

    local summary = { guildId = guildId, roles = 0, players = 0, members = 0, skipped = 0, errors = 0 }
    local dbOk, dbErr = ensureDatabase()
    summary.database = dbOk
    summary.databaseError = dbErr

    local rolesOk, rolesResponse = awaitRest(function(callback)
        Kora.discord.fetchGuildRoles(guildId, callback)
    end)
    if not rolesOk or type(rolesResponse.data) ~= 'table' then
        return false, rolesResponse.error or 'Discord did not return a guild role array.'
    end

    local catalog = cacheGuildRoles(guildId, rolesResponse.data)
    summary.roles = #catalog.list
    if databaseReady then
        local persisted, persistErr = persistGuildRoles(guildId, catalog.list)
        if not persisted then summary.databaseError = persistErr end
    end

    local players = GetPlayers()
    summary.players = #players
    local seen = {}
    for sourceStringIndex = 1, #players do
        local sourceString = players[sourceStringIndex]
        local userId = discordIdForPlayer(sourceString)
        if not userId or seen[userId] then
            summary.skipped = summary.skipped + 1
        else
            seen[userId] = true
            local memberOk, memberResponse = awaitRest(function(callback)
                Kora.discord.getMember(guildId, userId, callback)
            end)

            local entry
            if memberOk and type(memberResponse.data) == 'table' and type(memberResponse.data.roles) == 'table' then
                entry = cacheMemberRoles(guildId, userId, memberResponse.data.roles)
                summary.members = summary.members + 1
            elseif memberResponse.status == 404 then
                entry = cacheMemberRoles(guildId, userId, {})
                summary.members = summary.members + 1
            else
                markMemberStale(guildId, userId)
                summary.errors = summary.errors + 1
            end

            if entry and databaseReady then
                local persisted, persistErr = persistMemberRoles(guildId, userId, entry)
                if not persisted then
                    summary.databaseError = persistErr
                    summary.errors = summary.errors + 1
                end
            end
        end
    end

    return true, summary
end

---Fetch the guild role catalog and every online player's member roles, then
---replace the in-memory cache and kora_sql snapshots. Only one sync may run at once.
---@param callback fun(ok:boolean, response:table)|nil
---@return boolean queued
function Kora.discord.syncRoles(callback)
    assertCallback(callback)
    if not Kora.discord.botEnabled() then return botDisabled(callback) end
    if syncInProgress then return localFailure(callback, 'A Discord role sync is already running.') end
    syncInProgress = true

    CreateThread(function()
        local ran, ok, result = pcall(runFullRoleSync)
        syncInProgress = false

        if not ran then
            if callback then callback(false, { status = 0, error = tostring(ok) }) end
        elseif ok then
            if callback then callback(true, { status = 200, data = result }) end
        elseif callback then
            callback(false, { status = 0, error = tostring(result) })
        end
    end)
    return true
end

-- Console-only on purpose: role names/IDs and sync diagnostics should not be
-- exposed through a player command merely because an ACE wildcard permits it.
local function discordSyncCommand(source)
    if source ~= 0 then return end
    if not Kora.discord.botEnabled() then
        print('^3[kora_lib:discord]^7 bot disabled; set kora_lib_discord_bot_token and restart kora_lib.')
        return
    end

    local queued = Kora.discord.syncRoles(function(ok, response)
        if not ok then
            print(('^1[kora_lib:discord]^7 role sync failed: %s'):format(tostring(response.error)))
            return
        end
        local data = response.data
        print(('^2[kora_lib:discord]^7 synced %d guild roles and %d/%d online members (%d skipped, %d errors).'):format(
            data.roles, data.members, data.players, data.skipped, data.errors))
        if not data.database then
            print(('^3[kora_lib:discord]^7 database persistence unavailable: %s'):format(tostring(data.databaseError)))
        elseif data.databaseError then
            print(('^3[kora_lib:discord]^7 database sync warning: %s'):format(tostring(data.databaseError)))
        end
    end)
    if queued then print('^5[kora_lib:discord]^7 role sync started...') end
end

RegisterCommand('kora_lib_discord_sync', discordSyncCommand, false)
-- Deprecated alias for the pre-rename console command.
RegisterCommand('qblib_discord_sync', discordSyncCommand, false)

AddEventHandler('playerJoining', function()
    if not Kora.discord.botEnabled() then return end
    local joiningSource = source
    SetTimeout(1000, function()
        local userId = discordIdForPlayer(joiningSource)
        if userId then
            Kora.discord.refreshMember(userId, function(ok, response)
                if not ok and response.status ~= 404 then
                    print(('^3[kora_lib:discord]^7 could not refresh joining player %s: %s'):format(
                        tostring(joiningSource), tostring(response.error)))
                end
            end)
        end
    end)
end)

-- The token convar is intentionally sampled at resource start for background
-- work. Explicit bot functions still read it per call, but enabling the bot's
-- heartbeat requires a kora_lib restart after setting the convar.
CreateThread(function()
    if not Kora.discord.botEnabled() then return end

    Kora.discord.syncRoles(function(ok, response)
        if not ok then
            print(('^3[kora_lib:discord]^7 initial role sync failed: %s'):format(tostring(response.error)))
        elseif response.data.databaseError then
            print(('^3[kora_lib:discord]^7 initial role database sync warning: %s'):format(
                tostring(response.data.databaseError)))
        end
    end)

    while true do
        Wait(discordConfig('roleSyncInterval', 300000))
        Kora.discord.syncRoles(function(ok, response)
            if not ok then
                print(('^3[kora_lib:discord]^7 heartbeat role sync failed: %s'):format(tostring(response.error)))
            elseif response.data.databaseError then
                print(('^3[kora_lib:discord]^7 heartbeat role database sync warning: %s'):format(
                    tostring(response.data.databaseError)))
            end
        end)
    end
end)
