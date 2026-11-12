---
title: Troubleshooting
sidebar_position: 15
---

# Troubleshooting

| Symptom | Likely cause and fix |
| --- | --- |
| kora_lib refuses to start | `kora_theme` is missing or started later. Ensure `kora_theme` first (it is declared with `dependency`). |
| `Kora` is nil in a consumer | The consumer manifest lacks `shared_script '@kora_lib/init.lua'`. See [Installation](./installation.md). |
| `No such export` for a `Kora` function | Function is in a different realm, or kora_lib is not started. Check the realm on its reference page. |
| `attempt to call a table value` on a throttle handle | Handles from `Kora.timers.throttle` lose their `__call` across the export boundary; call `.run(...)`. See [Timers](./reference/timers.md). |
| `/kora_zonecreator` or `/kora_place` says you lack access | Grant `kora_lib.editor`. See [Permissions and ACE](./permissions.md). |
| Configuration editor will not open | The player lacks `kora_lib.config.edit` and `admin`, or `kora_admin` denies. |
| Discord bot helpers return false without a request | `kora_lib_discord_bot_token` is unset or empty. See [Configuration](./configuration.md). |
| Discord role data is not persisted | `kora_sql` is not started or not ready; a warning is printed. See [Database](./database.md). |
| A legacy resource cannot import `@ox_lib/...` | `provide` cannot satisfy file imports; install the optional named `ox_lib` resource. See [Installation](./installation.md). |
| Blank NUI | `web/build/` missing from the deployed folder, or the manifest `files` globs were changed. |
