# Discord module

## Overview

Server-only Discord helpers with two independent parts:

1. Webhooks: create embeds and post webhook messages. No bot is required.
2. REST bot: read and manage guild members, roles, channels, and messages. The
   bot client is disabled unless `qblib_discord_bot_token` is set.
3. Role directory: a five-minute online-player heartbeat, memory cache, optional
   qbsql persistence, and role-name-based authorization/mutation helpers.

This is an HTTP/REST client, not a Discord Gateway connection. It performs
outbound tasks but does not listen for Discord messages or events.

## Setup

Keep credentials in `server.cfg`, using server-only `set` (never `setr`):

```cfg
# Optional default used when sendWebhook receives nil as its URL.
set qblib_discord_webhook "https://discord.com/api/webhooks/.../..."

# Enables every bot helper. If absent or empty, botEnabled() is false and bot
# calls return false without making an HTTP request.
set qblib_discord_bot_token "your-bot-token"

# Optional convenience default. Pass nil as guildId to use this ID.
set qblib_discord_guild_id "123456789012345678"
```

Restart qblib after enabling the bot token so its background heartbeat starts.
The interval and authorization-cache TTL default to five and ten minutes,
respectively (`Config.discord.roleSyncInterval` / `cacheMaxAge`).

Discord IDs must be passed as decimal **strings**, not Lua numbers. Snowflake
IDs are too large to represent safely as ordinary JSON/Lua numbers.

The bot must already be installed in the guild. Give it only the permissions
its calls need. Role management requires `MANAGE_ROLES` and can only affect
roles below the bot's highest role; channel management requires
`MANAGE_CHANNELS`.

When qbsql is running, qblib applies `modules/discord/sql/001_discord.sql` with
qbsql's migration runner and persists the guild catalog, known members, and
their role assignments. If qbsql is absent, all bot/cache functions still work
in memory and the console reports that persistence is unavailable.

## Callback and return contract

Every HTTP function returns `true` when it queued a request and `false` when
its required convar is missing. Its optional callback receives:

```lua
function(ok, response)
    -- ok: true for any 2xx response
    -- response.status: HTTP status (0 for a locally disabled/missing config)
    -- response.data: decoded JSON, when the response contained valid JSON
    -- response.body: raw response body
    -- response.headers: response headers
    -- response.error: an error message on failure, when available
end
```

Discord 429 responses are retried once after Discord's `retry_after` delay.
A second 429 is returned to the callback normally.

## Webhook API

### `QB.discord.createEmbed(options)`

Returns a plain Discord embed table safe to pass through a FiveM export.
Supported fields are `title`, `description`, `url`, `color`, `timestamp`,
`footer`, `author`, `image`, `thumbnail`, and `fields` (up to 25).

- `color` accepts an integer, `"DC143C"`, or `"#DC143C"`.
- `timestamp = true` creates the current UTC timestamp.
- `timestamp` may alternatively be a Unix timestamp or ISO8601 string.
- `footer` and `author` accept either a string or the corresponding Discord
  object; `image` and `thumbnail` accept a URL string or `{ url = ... }`.

```lua
local embed = QB.discord.createEmbed({
    title = 'Server started',
    description = 'The server is ready for players.',
    color = '#DC143C',
    timestamp = true,
    fields = {
        { name = 'Build', value = '142', inline = true },
        { name = 'Environment', value = 'production', inline = true },
    },
    footer = 'qblib',
})
```

### `QB.discord.sendWebhook(url, payload, callback?)`

Posts a webhook message. `url = nil` uses `qblib_discord_webhook`. `payload`
may be a content string, a complete Discord webhook payload, or a single embed
table (which is wrapped in `embeds`). This works without the bot token.

```lua
QB.discord.sendWebhook(nil, { embeds = { embed } }, function(ok, response)
    if not ok then print(('Webhook failed: %s'):format(response.error)) end
end)

-- An explicit webhook and a simple content message:
QB.discord.sendWebhook(myWebhookUrl, 'Maintenance starts in ten minutes.')
```

## Bot API

### State and generic escape hatch

```lua
QB.discord.botEnabled()
QB.discord.botRequest(method, relativeRoute, payload?, callback?, auditReason?)
```

`botRequest` supports `GET`, `POST`, `PUT`, `PATCH`, and `DELETE`. Routes must
be relative to Discord API v10 (for example `/users/@me`), ensuring the bot
token is never attached to an arbitrary host.

### Guild members and roles

```lua
QB.discord.getGuild(guildId, callback)
QB.discord.getMember(guildId, userId, callback)
QB.discord.updateMember(guildId, userId, attributes, callback?, auditReason?)
QB.discord.fetchGuildRoles(guildId, callback)
QB.discord.setMemberRoles(guildId, userId, roleIds, callback?, auditReason?)
QB.discord.addMemberRole(guildId, userId, roleId, callback?, auditReason?)
QB.discord.removeMemberRole(guildId, userId, roleId, callback?, auditReason?)
QB.discord.createRole(guildId, role, callback?, auditReason?)
QB.discord.updateRole(guildId, roleId, role, callback?, auditReason?)
QB.discord.deleteRole(guildId, roleId, callback?, auditReason?)
```

`setMemberRoles` replaces the member's full role list. Use `addMemberRole` or
`removeMemberRole` when changing just one role.

```lua
QB.discord.fetchGuildRoles(nil, function(ok, response)
    if not ok then return print(response.error) end
    for _, role in ipairs(response.data) do
        print(role.id, role.name)
    end
end)

QB.discord.addMemberRole(nil, discordUserId, policeRoleId, nil,
    'Player was hired as police in-game')
```

The methods above are raw Discord REST wrappers and use Discord role IDs. The
cached helpers below are normally a better fit for gameplay/admin code because
they also accept role names.

### Cached role directory and authorization

At resource start, and every five minutes afterward, qblib fetches the complete
guild role catalog followed by the member role list for every online FiveM
player that has a `discord:<id>` identifier. A joining player is also refreshed
after one second. Only one full sync can run at once.

Run an immediate sync from the **server console only**:

```text
qblib_discord_sync
```

Player attempts to run that command are ignored even if they have broad ACE
permissions. The command prints the number of guild roles, online members,
skipped players (normally those without a Discord identifier), API failures,
and database status.

```lua
QB.discord.syncRoles(callback?)
QB.discord.refreshMember(id, callback?)

QB.discord.getGuildRoles(guildId?)
QB.discord.getRole(roleNameOrId, guildId?)
QB.discord.getRoles(id)
QB.discord.hasRole(id, roleNameOrId)
QB.discord.hasRoles(id, roleNamesOrIds, requireAll?) -- requireAll defaults true
QB.discord.hasAnyRole(id, roleNamesOrIds)
QB.discord.hasAllRoles(id, roleNamesOrIds)

QB.discord.giveRole(id, roleNameOrId, callback?, auditReason?)
QB.discord.removeRole(id, roleNameOrId, callback?, auditReason?)
```

For member methods, `id` may be:

- a Discord snowflake string (`"223456789012345678"`);
- a prefixed identifier (`"discord:223456789012345678"`); or
- an online FiveM server ID number (`source`).

Role names are case-insensitive. Discord permits duplicate names; if a name is
ambiguous, qblib refuses it and asks for the exact role ID. `getRoles` is
synchronous and returns cached role objects. It may return stale roles for an
admin display together with a second `error` result, but `hasRole`/`hasRoles`
always fail closed when the snapshot is absent, marked stale after a failed
refresh, or older than `Config.discord.cacheMaxAge`.

```lua
-- Permission check for an online FiveM player.
local allowed, err = QB.discord.hasAnyRole(source, { 'Administrator', 'Moderator' })
if not allowed then
    return false, err or 'You do not have the required Discord role.'
end

-- Admin menu operation; changes Discord, then updates cache + database.
QB.discord.giveRole(targetSource, 'Moderator', function(ok, response)
    if not ok then print(('Could not grant role: %s'):format(response.error)) end
end, 'Granted from the in-game admin menu')
```

### Channels and messages

```lua
QB.discord.getChannels(guildId, callback)
QB.discord.getChannel(channelId, callback)
QB.discord.createChannel(guildId, channel, callback?, auditReason?)
QB.discord.updateChannel(channelId, attributes, callback?, auditReason?)
QB.discord.deleteChannel(channelId, callback?, auditReason?)
QB.discord.sendMessage(channelId, payload, callback?)
QB.discord.editMessage(channelId, messageId, payload, callback?)
QB.discord.deleteMessage(channelId, messageId, callback?, auditReason?)
```

```lua
QB.discord.createChannel(nil, {
    name = 'support-tickets',
    type = 0, -- guild text channel
    topic = 'Player support',
}, function(ok, response)
    if ok then print('Created channel', response.data.id) end
end, 'Created by the FiveM server')

QB.discord.sendMessage(channelId, {
    content = 'The FiveM server is online.',
    allowed_mentions = { parse = {} },
})
```

Discord's current endpoint payload fields and permission requirements are
documented in its official [Guild](https://docs.discord.com/developers/resources/guild),
[Channel](https://docs.discord.com/developers/resources/channel), and
[Message](https://docs.discord.com/developers/resources/message) references.
