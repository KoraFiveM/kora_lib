---
title: Permissions and ACE
sidebar_position: 8
---

# Permissions and ACE

kora_lib uses FiveM ACEs, checked through [`Kora.permissions`](./api/permissions.md). `Kora.permissions.hasPermission(src, permission, prefix)` passes when the player has `prefix.permission` (when a prefix is given), `group.permission`, or `command.permission`, or a mapped Discord role.

| Permission | Where it is checked | Grant with |
| --- | --- | --- |
| `kora_lib.editor` | `/kora_zonecreator` and `/kora_place`. Derived from `Config.editor.permission` (`editor`) and `Config.editor.permissionPrefix` (`kora_lib`). | `add_ace group.admin kora_lib.editor allow` |
| `kora_lib.config.edit` | Server callbacks behind the configuration editor workspace (`Kora.config.open()`). Console is always allowed. If `kora_admin` is started and exports `canEditConfig`, its answer decides instead. If neither grants access, the `admin` permission (`group.admin`) also passes. | `add_ace group.admin kora_lib.config.edit allow` |
| `admin` | Server callback `kora_lib:blips:isAdmin`, used by the blips settings app to decide if admin-only actions are shown. | `group.admin` principal membership |

Example `server.cfg` lines:

```cfg
add_ace group.admin kora_lib.editor allow
add_ace group.admin kora_lib.config.edit allow
```

Every ACE check happens on the server. Client-side checks are only for presentation.
