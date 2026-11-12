---
title: Database
sidebar_position: 11
---

# Database

kora_lib has no database requirement. Only the [Discord](./api/discord.md) role directory optionally persists data, through the `kora_sql` resource (`exports.kora_sql:ensureTables`, `query` and `transaction`). `kora_sql` is not declared in `fxmanifest.lua`; kora_lib checks `GetResourceState('kora_sql')` and waits up to `Config.discord.databaseTimeout` (60 seconds by default) for `isReady()`. If it is unavailable, the role directory runs from memory only and prints a warning.

Tables are created automatically with `utf8mb4_unicode_ci` collation when the bot is enabled.

## `kora_lib_discord_roles`

| Column | Type | Notes |
| --- | --- | --- |
| `guild_id` | `varchar(32)` | Primary key part. |
| `role_id` | `varchar(32)` | Primary key part. |
| `name` | `varchar(100)` | Indexed with `guild_id`. |
| `color` | `int` unsigned | Default `0`. |
| `position` | `smallint` | Default `0`. |
| `permissions` | `varchar(32)` | Default `'0'`. |
| `managed` | `tinyint(1)` | Default `0`. |
| `mentionable` | `tinyint(1)` | Default `0`. |
| `updated_at` | `timestamp` | Defaults to and updates with `CURRENT_TIMESTAMP`. |

## `kora_lib_discord_members`

| Column | Type | Notes |
| --- | --- | --- |
| `guild_id` | `varchar(32)` | Primary key part. |
| `user_id` | `varchar(32)` | Primary key part. |
| `synced_at` | `bigint` unsigned | Indexed. |

## `kora_lib_discord_member_roles`

| Column | Type | Notes |
| --- | --- | --- |
| `guild_id` | `varchar(32)` | Primary key part. |
| `user_id` | `varchar(32)` | Primary key part; foreign key to members (`ON DELETE CASCADE`). |
| `role_id` | `varchar(32)` | Primary key part; foreign key to roles (`ON DELETE CASCADE`). |
