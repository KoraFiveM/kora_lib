---
title: "Discord"
sidebar_position: 40
---


# Discord

Server-only Discord HTTP helpers for webhooks, REST bot requests, guild data, role management, channels, and messages. This is an outbound REST client, not a Discord Gateway connection; it does not receive Discord messages or events.

Namespace: `Kora.discord` · Source: `modules/discord/server.lua`

## How it works

Webhook functions work without a bot token. Bot functions require the server-only kora_lib_discord_bot_token convar. HTTP methods return whether a request was queued and deliver status, decoded data, raw body, headers, and errors through an optional callback. Discord 429 responses are retried once when retry_after is valid.

## Configuration and credentials

Set kora_lib_discord_webhook, kora_lib_discord_bot_token, and kora_lib_discord_guild_id as server-only set convars in server.cfg. Never use setr for the bot token. The webhook URL and default guild are optional. Restart kora_lib after setting the token so the automatic role-sync heartbeat starts. Legacy kora_lib convar names remain fallbacks.

## HTTP callback contract

HTTP helpers return true when a request was queued; the optional callback receives (ok, response). response includes status (0 for local configuration failure), decoded data when valid JSON was returned, raw body, headers, and an error string when available. A queued return does not mean the HTTP request succeeded.

## Role cache

The role directory syncs on startup and every Config.discord.roleSyncInterval (default 300000 ms), and refreshes joining players after one second. Cache freshness defaults to Config.discord.cacheMaxAge (600 seconds). getRoles may return stale data for display with an error; hasRole/hasRoles reject missing or stale snapshots for authorization. Role names are case-insensitive, but duplicate names require an exact ID.

## Functions

Public functions are grouped below by webhook, bot/REST, and cached role directory. Discord snowflake IDs must be decimal strings to avoid Lua number precision loss.

### `Kora.discord.createEmbed(options)`

Builds a Discord embed table suitable for sendWebhook or a message payload.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `options` | table | table with supported fields such as title, description, url, color, timestamp, footer, author, image, thumbnail, and fields. fields is a dense array capped at 25. Color accepts an integer or hex string; timestamp accepts true, a finite Unix timestamp, or ISO8601. |

**Returns**

- **embed** — normalized plain Lua table.

**Example**

```lua
local embed = Kora.discord.createEmbed({
    title = 'Server started',
    description = 'The server is ready.',
    color = '#808080',
    timestamp = true,
    fields = { { name = 'Build', value = '142', inline = true } },
    footer = 'kora_lib',
})
```

**Representative console output**

```text
Returns a normalized embed table; invalid fields raise before a request.
```

### `Kora.discord.sendWebhook(url?, payload, callback?)`

Posts a webhook message; this endpoint does not require the bot token.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `url?` | number | optional webhook URL, or nil to use kora_lib_discord_webhook. |
| `payload` | string \| table | string content, complete webhook payload, or embed table. |
| `callback?` | function | optional function(ok, response). |

**Returns**

- **queued** — boolean; false when the URL/configuration is unavailable.
- **callback response** — status, decoded data when valid JSON, raw body, headers, and optional error.

**Example**

```lua
Kora.discord.sendWebhook(nil, { content = 'Maintenance in ten minutes.' }, function(ok, response)
    if not ok then print(response.error) end
end)
```

**Representative console output**

```text
The callback reports the HTTP result; a successful queue is not itself proof Discord accepted the payload.
```

### `Kora.discord.botEnabled()`

Reports whether the bot token convar is configured.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `—` |  | No parameters. |

**Returns**

- **enabled** — boolean.

**Example**

```lua
if not Kora.discord.botEnabled() then return end
```

**Representative console output**

```text
false when the token is absent or empty; true when configured.
```

### `Kora.discord.botRequest(method, route, payload?, callback?, auditReason?)`

Sends a bot-authenticated request to a route relative to Discord API v10.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `method` | string | GET, POST, PUT, PATCH, or DELETE. |
| `route` | string | relative API route; arbitrary hosts are rejected. |
| `payload?` | number | optional JSON body. |
| `callback?` | function | optional response callback. |
| `auditReason?` | number | optional audit-log reason for supported endpoints. |

**Returns**

- **queued** — boolean; false when bot is disabled or input/configuration fails.
- **callback** — receives (ok, response) with status, data, body, headers, and error.

**Example**

```lua
Kora.discord.botRequest('GET', '/users/@me', nil, function(ok, response)
    if ok then print(response.data.username) end
end)
```

**Representative console output**

```text
Uses the configured bot token only with Discord API routes.
```

### `Kora.discord.getGuild(guildId?, callback)`

Fetches a guild. Nil guildId uses the configured default guild ID.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `guildId?` | number | optional decimal-string snowflake. |
| `callback` | function | response callback. |

**Returns**

- **queued** — boolean; HTTP result arrives through callback.

**Example**

```lua
Kora.discord.getGuild(nil, function(ok, response)
    if ok then print(response.data.name) end
end)
```

**Representative console output**

```text
Callback data contains the decoded guild object on success.
```

### `Kora.discord.getMember(guildId?, userId, callback)`

Fetches a guild member from Discord REST.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `guildId?` | number | optional guild snowflake string. |
| `userId` | string | Discord snowflake decimal string. |
| `callback` | function | response callback. |

**Returns**

- **queued** — boolean; HTTP result arrives through callback.

**Example**

```lua
Kora.discord.getMember(nil, discordUserId, function(ok, response)
    if ok then print(response.data.user.id) end
end)
```

**Representative console output**

```text
Callback includes member data or HTTP error information.
```

### `Kora.discord.updateMember(guildId?, userId, attributes, callback?, auditReason?)`

Updates Discord guild-member attributes.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `guildId?` | number | optional guild snowflake string. |
| `userId` | string | Discord user snowflake string. |
| `attributes` | table | Discord Modify Guild Member payload table. |
| `callback?` | function | optional response callback. |
| `auditReason?` | number | optional audit-log reason. |

**Returns**

- **queued** — boolean; request result arrives through callback.

**Example**

```lua
Kora.discord.updateMember(nil, discordUserId, { nick = 'New nickname' }, callback)
```

**Representative console output**

```text
Request uses Discord’s guild member modify endpoint.
```

### `Kora.discord.fetchGuildRoles(guildId?, callback)`

Fetches the guild role catalog from Discord.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `guildId?` | number | optional guild snowflake string. |
| `callback` | function | response callback. |

**Returns**

- **queued** — boolean; HTTP result arrives through callback.

**Example**

```lua
Kora.discord.fetchGuildRoles(nil, function(ok, response)
    if ok then for _, role in ipairs(response.data) do print(role.id, role.name) end end
end)
```

**Representative console output**

```text
Successful callback data is the role array.
```

### `Kora.discord.setMemberRoles(guildId?, userId, roleIds, callback?, auditReason?)`

Replaces the member’s complete role list.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `guildId?` | number | optional guild snowflake string. |
| `userId` | string | Discord user snowflake string. |
| `roleIds` | table | array of role ID strings. |
| `callback?` | function | optional response callback. |
| `auditReason?` | number | optional audit-log reason. |

**Returns**

- **queued** — boolean; request result arrives through callback.

**Example**

```lua
Kora.discord.setMemberRoles(nil, discordUserId, { roleIdA, roleIdB }, callback)
```

**Representative console output**

```text
Existing roles not in roleIds are removed.
```

### `Kora.discord.addMemberRole(guildId?, userId, roleId, callback?, auditReason?)`

Adds one role to a Discord member using the raw REST API.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `guildId?` | number | optional guild snowflake string. |
| `userId, roleId` | number | decimal-string snowflakes. |
| `callback?` | function | optional response callback. |
| `auditReason?` | number | optional audit-log reason. |

**Returns**

- **queued** — boolean; request result arrives through callback.

**Example**

```lua
Kora.discord.addMemberRole(nil, discordUserId, roleId, callback, 'Hired in game')
```

**Representative console output**

```text
Adds the role without replacing the member’s other roles.
```

### `Kora.discord.removeMemberRole(guildId?, userId, roleId, callback?, auditReason?)`

Removes one role from a Discord member using the raw REST API.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `guildId?` | number | optional guild snowflake string. |
| `userId, roleId` | number | decimal-string snowflakes. |
| `callback?` | function | optional response callback. |
| `auditReason?` | number | optional audit-log reason. |

**Returns**

- **queued** — boolean; request result arrives through callback.

**Example**

```lua
Kora.discord.removeMemberRole(nil, discordUserId, roleId, callback)
```

**Representative console output**

```text
Removes only the selected role.
```

### `Kora.discord.createRole(guildId?, role, callback?, auditReason?)`

Creates a guild role.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `guildId?` | number | optional guild snowflake string. |
| `role` | table | Discord Create Guild Role payload table. |
| `callback?` | function | optional response callback. |
| `auditReason?` | number | optional audit-log reason. |

**Returns**

- **queued** — boolean; request result arrives through callback.

**Example**

```lua
Kora.discord.createRole(nil, { name = 'Helper', hoist = true }, callback, 'Created by admin')
```

**Representative console output**

```text
Successful callback includes the created role object.
```

### `Kora.discord.updateRole(guildId?, roleId, role, callback?, auditReason?)`

Updates a guild role.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `guildId?` | number | optional guild snowflake string. |
| `roleId` | string | role snowflake string. |
| `role` | table | Discord Modify Guild Role payload table. |
| `callback?` | function | optional response callback. |
| `auditReason?` | number | optional audit-log reason. |

**Returns**

- **queued** — boolean; request result arrives through callback.

**Example**

```lua
Kora.discord.updateRole(nil, roleId, { name = 'Senior Helper' }, callback)
```

**Representative console output**

```text
Requires the bot to have MANAGE_ROLES and the role to be below its highest role.
```

### `Kora.discord.deleteRole(guildId?, roleId, callback?, auditReason?)`

Deletes a guild role.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `guildId?` | number | optional guild snowflake string. |
| `roleId` | string | role snowflake string. |
| `callback?` | function | optional response callback. |
| `auditReason?` | number | optional audit-log reason. |

**Returns**

- **queued** — boolean; request result arrives through callback.

**Example**

```lua
Kora.discord.deleteRole(nil, roleId, callback, 'Role retired')
```

**Representative console output**

```text
Requires MANAGE_ROLES and Discord role hierarchy to permit deletion.
```

### `Kora.discord.getChannels(guildId?, callback)`

Fetches guild channels.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `guildId?` | number | optional guild snowflake string. |
| `callback` | function | response callback. |

**Returns**

- **queued** — boolean; HTTP result arrives through callback.

**Example**

```lua
Kora.discord.getChannels(nil, function(ok, response)
    if ok then print(#response.data, 'channels') end
end)
```

**Representative console output**

```text
Successful callback data contains the channel array.
```

### `Kora.discord.getChannel(channelId, callback)`

Fetches one channel.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `channelId` | string | channel snowflake string. |
| `callback` | function | response callback. |

**Returns**

- **queued** — boolean; HTTP result arrives through callback.

**Example**

```lua
Kora.discord.getChannel(channelId, callback)
```

**Representative console output**

```text
Callback data contains the channel object on success.
```

### `Kora.discord.createChannel(guildId?, channel, callback?, auditReason?)`

Creates a guild channel.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `guildId?` | number | optional guild snowflake string. |
| `channel` | table | Discord Create Guild Channel payload; name is required by Discord. |
| `callback?` | function | optional response callback. |
| `auditReason?` | number | optional audit-log reason. |

**Returns**

- **queued** — boolean; request result arrives through callback.

**Example**

```lua
Kora.discord.createChannel(nil, { name = 'support', type = 0 }, callback)
```

**Representative console output**

```text
Requires MANAGE_CHANNELS; callback contains the created channel on success.
```

### `Kora.discord.updateChannel(channelId, attributes, callback?, auditReason?)`

Updates channel attributes.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `channelId` | string | channel snowflake string. |
| `attributes` | table | Discord Modify Channel payload table. |
| `callback?` | function | optional response callback. |
| `auditReason?` | number | optional audit-log reason. |

**Returns**

- **queued** — boolean; request result arrives through callback.

**Example**

```lua
Kora.discord.updateChannel(channelId, { topic = 'Player support' }, callback)
```

**Representative console output**

```text
Requires MANAGE_CHANNELS for changes that need it.
```

### `Kora.discord.deleteChannel(channelId, callback?, auditReason?)`

Deletes a channel.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `channelId` | string | channel snowflake string. |
| `callback?` | function | optional response callback. |
| `auditReason?` | number | optional audit-log reason. |

**Returns**

- **queued** — boolean; request result arrives through callback.

**Example**

```lua
Kora.discord.deleteChannel(channelId, callback, 'Channel retired')
```

**Representative console output**

```text
Callback reports Discord’s result.
```

### `Kora.discord.sendMessage(channelId, payload, callback?)`

Sends a message to a channel.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `channelId` | string | channel snowflake string. |
| `payload` | string \| table | content string or Discord Create Message payload table. |
| `callback?` | function | optional response callback. |

**Returns**

- **queued** — boolean; request result arrives through callback.

**Example**

```lua
Kora.discord.sendMessage(channelId, { content = 'Server online.', allowed_mentions = { parse = {} } }, callback)
```

**Representative console output**

```text
Callback contains the created message on success.
```

### `Kora.discord.editMessage(channelId, messageId, payload, callback?)`

Edits a message in a channel.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `channelId, messageId` | number | snowflake strings. |
| `payload` | string \| table | content string or Discord Edit Message payload table. |
| `callback?` | function | optional response callback. |

**Returns**

- **queued** — boolean; request result arrives through callback.

**Example**

```lua
Kora.discord.editMessage(channelId, messageId, { content = 'Updated status.' }, callback)
```

**Representative console output**

```text
Callback contains the edited message on success.
```

### `Kora.discord.deleteMessage(channelId, messageId, callback?, auditReason?)`

Deletes a message.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `channelId, messageId` | number | snowflake strings. |
| `callback?` | function | optional response callback. |
| `auditReason?` | number | optional audit-log reason. |

**Returns**

- **queued** — boolean; request result arrives through callback.

**Example**

```lua
Kora.discord.deleteMessage(channelId, messageId, callback, 'Removed expired notice')
```

**Representative console output**

```text
Callback reports Discord’s result.
```

### `Kora.discord.getGuildRoles(guildId?)`

Returns a copy of the cached guild role catalog sorted from highest to lowest role.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `guildId?` | number | optional guild snowflake string; defaults to configured guild. |

**Returns**

- **roles** — array of copied role objects, or nil plus error when disabled, unresolved, or not cached.

**Example**

```lua
local roles, err = Kora.discord.getGuildRoles()
if not roles then print(err) end
```

**Representative console output**

```text
Does not make an HTTP request; role sync populates the cache.
```

### `Kora.discord.getRole(role, guildId?)`

Resolves a cached role by exact ID or case-insensitive name.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `role` | string | role ID string or role name. |
| `guildId?` | number | optional guild snowflake string. |

**Returns**

- **role** — copied role object, or nil plus error when missing/ambiguous/uncached.

**Example**

```lua
local role, err = Kora.discord.getRole('Moderator')
```

**Representative console output**

```text
Duplicate role names are rejected; use the exact role ID.
```

### `Kora.discord.refreshMember(id, callback?)`

Fetches one member and replaces their cached and persisted role snapshot.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `id` | string \| integer | Discord snowflake string, discord:&lt;id> identifier, or online FiveM source integer. |
| `callback?` | function | optional function(ok, response). |

**Returns**

- **queued** — boolean. Callback receives the HTTP-style response; a confirmed 404 stores a fresh empty role set.

**Example**

```lua
Kora.discord.refreshMember(source, function(ok, response)
    if not ok then print(response.error) end
end)
```

**Representative console output**

```text
A failed refresh marks existing cached roles stale.
```

### `Kora.discord.getRoles(id)`

Returns cached role objects for a member, sorted by role position then name.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `id` | string \| integer | Discord snowflake string, discord:&lt;id> identifier, or online FiveM source integer. |

**Returns**

- **roles** — cached array, or nil plus error when no snapshot exists.
- **error** — optional string; stale roles may be returned for display with a stale-cache error.

**Example**

```lua
local roles, err = Kora.discord.getRoles(source)
```

**Representative console output**

```text
Synchronous cache read; does not refresh. Do not use stale results for authorization.
```

### `Kora.discord.hasRole(id, role)`

Checks a fresh cached member snapshot for one role by ID or case-insensitive name.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `id` | string \| integer | Discord snowflake string, prefixed identifier, or online FiveM source integer. |
| `role` | string | role ID or name string. |

**Returns**

- **hasRole** — boolean; false on missing/stale cache or unresolved role.
- **error** — optional reason when the check could not be safely resolved.

**Example**

```lua
local allowed, err = Kora.discord.hasRole(source, 'Moderator')
```

**Representative console output**

```text
Fails closed when the member snapshot is missing or stale.
```

### `Kora.discord.hasRoles(id, roles, requireAll?)`

Checks several roles. By default, every requested role must match.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `id` | string \| integer | supported Discord/member identifier. |
| `roles` | string \| array | non-empty array of role strings or a single role string. |
| `requireAll?` | boolean | optional boolean; defaults true, false means any role may match. |

**Returns**

- **matches** — boolean.
- **error** — optional string for missing/stale cache or unresolved role.

**Example**

```lua
local allowed = Kora.discord.hasRoles(source, { 'Admin', 'Moderator' }, false)
```

**Representative console output**

```text
With requireAll=false, returns true as soon as one role matches.
```

### `Kora.discord.hasAnyRole(id, roles)`

Convenience form of hasRoles with any-match behavior.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `id` | string \| integer | supported Discord/member identifier. |
| `roles` | string \| array | non-empty role string or array of role strings. |

**Returns**

- **matches** — boolean.
- **error** — optional resolution/cache error.

**Example**

```lua
if Kora.discord.hasAnyRole(source, { 'Admin', 'Moderator' }) then
    openStaffMenu(source)
end
```

**Representative console output**

```text
Equivalent to hasRoles(id, roles, false).
```

### `Kora.discord.hasAllRoles(id, roles)`

Convenience form of hasRoles requiring every listed role.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `id` | string \| integer | supported Discord/member identifier. |
| `roles` | string \| array | non-empty role string or array of role strings. |

**Returns**

- **matches** — boolean.
- **error** — optional resolution/cache error.

**Example**

```lua
local ok = Kora.discord.hasAllRoles(source, { 'Verified', 'Police' })
```

**Representative console output**

```text
Equivalent to hasRoles(id, roles, true).
```

### `Kora.discord.giveRole(id, role, callback?, auditReason?)`

Adds a role using a cached role ID/name, then updates a fresh cache snapshot or refreshes stale/missing member data.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `id` | string \| integer | supported Discord/member identifier. |
| `role` | string | cached role ID or unambiguous name. |
| `callback?` | function | optional function(ok, response). |
| `auditReason?` | number | optional string. |

**Returns**

- **queued** — boolean. Callback reports operation success and response.

**Example**

```lua
Kora.discord.giveRole(source, 'Moderator', function(ok, response)
    if not ok then print(response.error) end
end, 'Promoted in game')
```

**Representative console output**

```text
Role mutation uses the bot API; role names are resolved from the cached guild catalog.
```

### `Kora.discord.removeRole(id, role, callback?, auditReason?)`

Removes a role using a cached role ID/name and reconciles the member cache.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `id` | string \| integer | supported Discord/member identifier. |
| `role` | string | cached role ID or unambiguous name. |
| `callback?` | function | optional function(ok, response). |
| `auditReason?` | number | optional string. |

**Returns**

- **queued** — boolean. Callback reports operation success and response.

**Example**

```lua
Kora.discord.removeRole(source, 'Moderator', callback, 'Role revoked in game')
```

**Representative console output**

```text
Requires the bot’s role permissions and hierarchy to permit the change.
```

### `Kora.discord.syncRoles(callback?)`

Fetches the guild role catalog and every online player’s Discord roles, replaces memory caches, and persists snapshots when kora_sql is available. Only one full sync runs at a time.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `callback?` | function | optional function(ok, response). |

**Returns**

- **queued** — boolean; false when disabled or another sync is running.
- **callback response** — status/data summary with counts for roles, players, members, skipped players, errors, and database state.

**Example**

```lua
Kora.discord.syncRoles(function(ok, response)
    if ok then print(response.data.roles, response.data.members)
    else print(response.error) end
end)
```

**Representative console output**

```text
A full sync is asynchronous; callback receives the result summary.
```

## Limits and related APIs

The bot must be installed in the guild and granted only the required Discord permissions. Role changes require MANAGE_ROLES and can only affect roles below the bot’s highest role; channel management requires MANAGE_CHANNELS. When kora_sql is absent, bot and cache helpers still work in memory. Discord snowflakes must be strings. Do not expose the bot token to clients.

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/discord/docs.md` or `local/discord/docs.md`) that the reference above does not state.

### Overview

Server-only Discord helpers with two independent parts:

1. Webhooks: create embeds and post webhook messages. No bot is required.
2. REST bot: read and manage guild members, roles, channels, and messages. The
   bot client is disabled unless `kora_lib_discord_bot_token` is set.
3. Role directory: a five-minute online-player heartbeat, memory cache, optional
   kora_sql persistence, and role-name-based authorization/mutation helpers.

This is an HTTP/REST client, not a Discord Gateway connection. It performs
outbound tasks but does not listen for Discord messages or events.

### Setup

Keep credentials in `server.cfg`, using server-only `set` (never `setr`):

```cfg
## Optional default used when sendWebhook receives nil as its URL.
set kora_lib_discord_webhook "https://discord.com/api/webhooks/.../..."

## Enables every bot helper. If absent or empty, botEnabled() is false and bot
## calls return false without making an HTTP request.
set kora_lib_discord_bot_token "your-bot-token"

## Optional convenience default. Pass nil as guildId to use this ID.
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

### Callback and return contract

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

### Webhook API

#### `Kora.discord.createEmbed(options)`

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

#### `Kora.discord.sendWebhook(url, payload, callback?)`

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

### Bot API

#### State and generic escape hatch

```lua
Kora.discord.botEnabled()
Kora.discord.botRequest(method, relativeRoute, payload?, callback?, auditReason?)
```

`botRequest` supports `GET`, `POST`, `PUT`, `PATCH`, and `DELETE`. Routes must
be relative to Discord API v10 (for example `/users/@me`), ensuring the bot
token is never attached to an arbitrary host.

#### Guild members and roles

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

#### Cached role directory and authorization

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

#### Channels and messages

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
