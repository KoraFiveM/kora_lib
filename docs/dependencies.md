---
title: Dependencies and compatibility
sidebar_position: 12
---

# Dependencies and compatibility

| Resource | Required | Used for |
| --- | --- | --- |
| `kora_theme` | Yes (`dependency` in the manifest) | Shared palette; its `client/bridge.lua` is loaded as a client script and `Kora.theme` forwards to it. |
| `kora_sql` | Optional | Persistence of the Discord role directory. See [Database](./database.md). |
| `kora_admin` | Optional | If started, its `canEditConfig` export decides who may use the configuration editor. See [Permissions and ACE](./permissions.md). |
| `kora_core` | Optional | The qb-menu, qb-radialmenu and interaction bridges read item, job and player data through `kora_core` exports inside `pcall`; they degrade when it is absent. |
| `kora_qa` | Optional | Runs the `tests/*.feature` scenarios declared with `qa_feature` and receives `Kora.qa` marks. |
| `chat` | Optional | Receives command suggestions from the editor commands. |

Resources provided through the manifest: `qb-menu`, `qb-input`, `progressbar`, `qb-radialmenu`, `qb-minigames`, `screenshot-basic`. `provide` only satisfies `dependency` checks; the actual exports are registered by the compat files. Details and caveats are in [Legacy compatibility](./legacy-compat.md). The optional separate `ox_lib` and `PolyZone` resources are covered in [ox_lib compatibility](./migration/ox-lib.md).

Game: `gta5`, `fx_version 'cerulean'`, `lua54 'yes'`. See `version` in `fxmanifest.lua` for the release version.
