---
title: "Discord module"
sidebar_position: 40
---

# Discord module

## Overview

Server-only Discord helpers with two independent parts:

1. Webhooks: create embeds and post webhook messages. No bot is required.
2. REST bot: read and manage guild members, roles, channels, and messages. The
   bot client is disabled unless `kora_lib_discord_bot_token` is set.
3. Role directory: a five-minute online-player heartbeat, memory cache, optional
   kora_sql persistence, and role-name-based authorization/mutation helpers.

This is an HTTP/REST client, not a Discord Gateway connection. It performs
outbound tasks but does not listen for Discord messages or events.

## Setup

Keep credentials in `server.cfg`, using server-only `set` (never `setr`):

```cfg
# Optional default used when sendWebhook receives nil as its URL.
set kora_lib_discord_webhook "https://discord.com/api/webhooks/.../..."

# Enables every bot helper. If absent or empty, botEnabled() is false and bot
# calls return false without making an HTTP request.
set kora_lib_discord_bot_token "your-bot-token"

# Optional convenience default. Pass nil as guildId to use this ID.
set kora_lib_discord_guild_id "123456789012345678"
```

Restart kora_lib after enabling the bot token so its background heartbeat starts.

The `kora_lib_discord_sync` console command (console only; it does nothing when run by a player) forces an immediate role sync. The role directory's
database tables are named `kora_lib_discord_*` (see [Database](../database.md)).
The interval and authorization-cache TTL default to five and ten minutes,
respectively (`Config.discord.roleSyncInterval` / `cacheMaxAge`).

Discord IDs must be passed as decimal **strings**, not Lua numbers. Snowflake
IDs are too large to represent safely as ordinary JSON/Lua numbers.

The bot must already be installed in the guild. Give it only the permissions
its calls need. Role management requires `MANAGE_ROLES` and can only affect
roles below the bot's highest role; channel management requires
`MANAGE_CHANNELS`.

When kora_sql is running, kora_lib declares its tables in `modules/discord/server.lua` and applies them with
kora_sql's declarative schema handler (`ensureTables`) and persists the guild catalog, known members, and
their role assignments. If kora_sql is absent, all bot/cache functions still work
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

Discord 429 responses are retried once after Discord's finite `retry_after`
delay. A missing or invalid delay, and a second 429, are returned to the
callback normally.

## Webhook API

### `Kora.discord.createEmbed(options)`

Returns a plain Discord embed table safe to pass through a FiveM export.
Supported fields are `title`, `description`, `url`, `color`, `timestamp`,
`footer`, `author`, `image`, `thumbnail`, and `fields` (up to 25).

- `color` accepts an integer, `"DC143C"`, or `"#DC143C"`.
- `timestamp = true` creates the current UTC timestamp.
- `timestamp` may alternatively be a finite Unix timestamp or ISO8601 string.
- `footer` and `author` accept either a string or the corresponding Discord
  object; `image` and `thumbnail` accept a URL string or `{ url = ... }`.

```lua
local embed = Kora.discord.createEmbed({
    title = 'Server started',
    description = 'The server is ready for players.',
    color = '#DC143C',
    timestamp = true,
    fields = {
        { name = 'Build', value = '142', inline = true },
        { name = 'Environment', value = 'production', inline = true },
    },
    footer = 'kora_lib',
})
```

### `Kora.discord.sendWebhook(url, payload, callback?)`

Posts a webhook message. `url = nil` uses `kora_lib_discord_webhook`. `payload`
may be a content string, a complete Discord webhook payload, or a single embed
table (which is wrapped in `embeds`). This works without the bot token.

```lua
Kora.discord.sendWebhook(nil, { embeds = { embed } }, function(ok, response)
    if not ok then print(('Webhook failed: %s'):format(response.error)) end
end)

-- An explicit webhook and a simple content message:
Kora.discord.sendWebhook(myWebhookUrl, 'Maintenance starts in ten minutes.')
```

## Bot API

### State and generic escape hatch

```lua
Kora.discord.botEnabled()
Kora.discord.botRequest(method, relativeRoute, payload?, callback?, auditReason?)
```

`botRequest` supports `GET`, `POST`, `PUT`, `PATCH`, and `DELETE`. Routes must
be relative to Discord API v10 (for example `/users/@me`), ensuring the bot
token is never attached to an arbitrary host.

### Guild members and roles

```lua
Kora.discord.getGuild(guildId, callback)
Kora.discord.getMember(guildId, userId, callback)
Kora.discord.updateMember(guildId, userId, attributes, callback?, auditReason?)
Kora.discord.fetchGuildRoles(guildId, callback)
Kora.discord.setMemberRoles(guildId, userId, roleIds, callback?, auditReason?)
Kora.discord.addMemberRole(guildId, userId, roleId, callback?, auditReason?)
Kora.discord.removeMemberRole(guildId, userId, roleId, callback?, auditReason?)
Kora.discord.createRole(guildId, role, callback?, auditReason?)
Kora.discord.updateRole(guildId, roleId, role, callback?, auditReason?)
Kora.discord.deleteRole(guildId, roleId, callback?, auditReason?)
```

`setMemberRoles` replaces the member's full role list. Use `addMemberRole` or
`removeMemberRole` when changing just one role.

```lua
Kora.discord.fetchGuildRoles(nil, function(ok, response)
    if not ok then return print(response.error) end
    for _, role in ipairs(response.data) do
        print(role.id, role.name)
    end
end)

Kora.discord.addMemberRole(nil, discordUserId, policeRoleId, nil,
    'Player was hired as police in-game')
```

The methods above are raw Discord REST wrappers and use Discord role IDs. The
cached helpers below are normally a better fit for gameplay/admin code because
they also accept role names.

### Cached role directory and authorization

At resource start, and every five minutes afterward, kora_lib fetches the complete
guild role catalog followed by the member role list for every online FiveM
player that has a `discord:<id>` identifier. A joining player is also refreshed
after one second. Only one full sync can run at once.

Run an immediate sync from the **server console only**:

```text
kora_lib_discord_sync
```

Player attempts to run that command are ignored even if they have broad ACE
permissions. The command prints the number of guild roles, online members,
skipped players (normally those without a Discord identifier), API failures,
and database status.

```lua
Kora.discord.syncRoles(callback?)
Kora.discord.refreshMember(id, callback?)

Kora.discord.getGuildRoles(guildId?)
Kora.discord.getRole(roleNameOrId, guildId?)
Kora.discord.getRoles(id)
Kora.discord.hasRole(id, roleNameOrId)
Kora.discord.hasRoles(id, roleNamesOrIds, requireAll?) -- requireAll defaults true
Kora.discord.hasAnyRole(id, roleNamesOrIds)
Kora.discord.hasAllRoles(id, roleNamesOrIds)

Kora.discord.giveRole(id, roleNameOrId, callback?, auditReason?)
Kora.discord.removeRole(id, roleNameOrId, callback?, auditReason?)
```

For member methods, `id` may be:

- a Discord snowflake string (`"223456789012345678"`);
- a prefixed identifier (`"discord:223456789012345678"`); or
- an online FiveM server ID number (`source`).

Role names are case-insensitive. Discord permits duplicate names; if a name is
ambiguous, kora_lib refuses it and asks for the exact role ID. `getRoles` is
synchronous and returns cached role objects. It may return stale roles for an
admin display together with a second `error` result, but `hasRole`/`hasRoles`
always fail closed when the snapshot is absent, marked stale after a failed
refresh, or older than `Config.discord.cacheMaxAge`.

```lua
-- Permission check for an online FiveM player.
local allowed, err = Kora.discord.hasAnyRole(source, { 'Administrator', 'Moderator' })
if not allowed then
    return false, err or 'You do not have the required Discord role.'
end

-- Admin menu operation; changes Discord, then updates cache + database.
Kora.discord.giveRole(targetSource, 'Moderator', function(ok, response)
    if not ok then print(('Could not grant role: %s'):format(response.error)) end
end, 'Granted from the in-game admin menu')
```

### Channels and messages

```lua
Kora.discord.getChannels(guildId, callback)
Kora.discord.getChannel(channelId, callback)
Kora.discord.createChannel(guildId, channel, callback?, auditReason?)
Kora.discord.updateChannel(channelId, attributes, callback?, auditReason?)
Kora.discord.deleteChannel(channelId, callback?, auditReason?)
Kora.discord.sendMessage(channelId, payload, callback?)
Kora.discord.editMessage(channelId, messageId, payload, callback?)
Kora.discord.deleteMessage(channelId, messageId, callback?, auditReason?)
```

```lua
Kora.discord.createChannel(nil, {
    name = 'support-tickets',
    type = 0, -- guild text channel
    topic = 'Player support',
}, function(ok, response)
    if ok then print('Created channel', response.data.id) end
end, 'Created by the FiveM server')

Kora.discord.sendMessage(channelId, {
    content = 'The FiveM server is online.',
    allowed_mentions = { parse = {} },
})
```

Embed `fields`, when supplied, must be a dense array of at most 25 entries;
malformed lists are rejected before kora_lib encodes or sends a webhook.

Discord's current endpoint payload fields and permission requirements are
documented in its official [Guild](https://docs.discord.com/developers/resources/guild),
[Channel](https://docs.discord.com/developers/resources/channel), and
[Message](https://docs.discord.com/developers/resources/message) references.
