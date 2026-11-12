---
title: "Notify"
sidebar_position: 16
---


# Notify

## Client

Shows a short toast on the local player. The notification is rendered by kora_lib’s NUI unless the server enables a third-party notification provider. Toasts are temporary feedback; use a dialog or menu when the player must make a decision.

Namespace: `Kora.notify` · Source: `modules/notify/client.lua`

### Notification payload

Set at least title or message. Omitted appearance fields use Config.notify defaults. A `?` after a name means the option is optional.

| Option | Type | Description |
| --- | --- | --- |
| `title?` | string | Optional heading text. At least title or message must be supplied. |
| `message?` | string | Optional body text. Supports safe Markdown; raw HTML and unsafe URL schemes are ignored. |
| `duration?` | integer | Display time in milliseconds. Defaults to Config.notify.defaultDuration (5000); capped by maxDuration (120000 by default). |
| `type?` | 'info' \| 'success' \| 'warning' \| 'error' | Visual variant and icon. Defaults to configured type. Legacy aliases inform and warn are normalized. |
| `position?` | string | Toast placement: top-left, top-center, top-right, bottom-left, bottom-center, bottom-right, center-left, center-right, top, or bottom. |
| `icon?` | string | Overrides the default icon. Supports the built-in Lucide set, compatible Font Awesome names, and safe image URLs. |
| `iconColor?` | string | CSS color for the icon. |
| `iconAnimation?` | string | Animation name: spin, spinPulse, spinReverse, pulse, beat, fade, beatFade, bounce, or shake. |
| `alignIcon?` | 'top' \| 'center' | Vertical alignment for the icon. |
| `id?` | string \| number | Toast identity. A new toast with the same live ID replaces the existing one. |
| `showDuration?` | boolean | Set false to hide the lifetime indicator. |
| `style?` | table | Scalar CSS values for the toast. Nested title, description, message, and text selectors may also contain scalar CSS values. |

### Toast limits and routing

At most six toasts appear at one position; older toasts are dropped when that limit is exceeded. With Config.third_party_notify enabled, the raw payload is forwarded to the configured notification event and kora_lib does not apply its own defaults.

### Functions

Send one notification payload to the local player.

#### `Kora.notify.send(payload)`

Shows a notification on this client. Malformed payloads are caught and dropped so a notification cannot break the gameplay code that requested it.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `payload` | KoraNotifyPayload | Table containing at least a title or message, plus optional appearance settings listed above. |

**Returns**

- **return** — no value.

**Example**

```lua
Kora.notify.send({ title = 'Saved', message = 'Your changes were saved.', duration = 4000, type = 'success' })
```

**Representative console output**

```text
Shows a success toast for four seconds.
```

## Server

Sends a notification to one player or broadcasts one payload to all connected players. The receiving client applies its own configured defaults and renders the toast.

Namespace: `Kora.notify` · Source: `modules/notify/server.lua`

### Functions

Send to a player with send, or use sendToAll for a server-wide message.

#### `Kora.notify.send(src, payload)`

Requests a notification for one connected client. Use -1 to send to every connected player.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Positive target player server ID, or -1 for all connected players. |
| `payload` | KoraNotifyPayload | Same fields as the client payload table. |

**Returns**

- **return** — no value.

**Example**

```lua
Kora.notify.send(source, { title = 'Order ready', message = 'Your vehicle is outside.', type = 'success' })
```

**Representative console output**

```text
The target player sees an order-ready notification.
```

#### `Kora.notify.sendToAll(payload)`

Sends the same notification to every connected player. Prefer this to looping over player IDs manually.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `payload` | KoraNotifyPayload | Notification table using the same fields as client send. |

**Returns**

- **return** — no value.

**Example**

```lua
Kora.notify.sendToAll({ title = 'Restart', message = 'The server restarts in 10 minutes.', type = 'warning' })
```

**Representative console output**

```text
Every connected client receives the restart warning.
```

## Shared

Provides payload validation and normalization helpers used by both notification realms. You can use them before building a notification, though send already calls them internally.

Namespace: `Kora.notify` · Source: `modules/notify/shared.lua`

### Functions

Validate payloads, fill configured defaults into a copy, and normalize legacy type aliases.

#### `Kora.notify.assert(payload)`

Checks the notification table and raises an assertion error if its types, type variant, position, duration, or required text are invalid.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `payload` | table | Notification payload to validate. |

**Returns**

- **return** — no value; invalid data raises an error.

**Example**

```lua
local ok = pcall(function()
    Kora.notify.assert({ message = 'Saved', type = 'success' })
end)
print('Valid:', ok)
```

**Representative console output**

```text
Prints true for a valid payload; malformed values cause pcall to return false.
```

#### `Kora.notify.withDefaults(payload)`

Returns a copy with omitted duration, type, and position filled from Config.notify. The input table is not mutated.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `payload` | table | Payload to copy and complete. Explicit invalid settings are not silently replaced. |

**Returns**

- **payloadCopy** — new table with defaults filled in.

**Example**

```lua
local toast = Kora.notify.withDefaults({ message = 'Saved' })
print(toast.duration, toast.type, toast.position)
```

**Representative console output**

```text
Prints the configured default duration, type, and position.
```

#### `Kora.notify.normalizeType(notifyType)`

Converts legacy inform to info and warn to warning. Other values are returned unchanged so validation can reject unknown types.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `notifyType` | string? | Type alias or canonical notification type. |

**Returns**

- **type** — canonical alias when recognized; otherwise original value.

**Example**

```lua
local kind = Kora.notify.normalizeType('inform')
print(kind)
```

**Representative console output**

```text
Prints info.
```

#### `Kora.notify.normalize(payload)`

Returns a payload copy with its type alias normalized. Other fields are retained.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `payload` | table | Notification payload. |

**Returns**

- **payload** — normalized copy, or original table when no alias needs changing.

**Example**

```lua
local normalized = Kora.notify.normalize({ message = 'Hello', type = 'warn' })
print(normalized.type)
```

**Representative console output**

```text
Prints warning.
```

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/notify/docs.md` or `local/notify/docs.md`) that the reference above does not state.

### API

#### `Kora.notify.send(payload)` — client
Shows a notification on the local player.

##### Parameters
- `payload: KoraNotifyPayload`
  - `title?: string`, `message?: string` — At least one is required. Both must be strings.
  - `duration?: integer` — Milliseconds. Defaults to `Config.notify.defaultDuration`, capped at `Config.notify.maxDuration`.
  - `type?: "info" | "success" | "warning" | "error"` — Visual variant (accent colour + icon). Defaults to `Config.notify.defaultType`.
  - `position?: "top-left" | "top-center" | "top-right" | "bottom-left" | "bottom-center" | "bottom-right" | "center-left" | "center-right" | "top" | "bottom"` — Defaults to `Config.notify.defaultPosition`.
  - `icon?: string` — Overrides the variant's default icon. Supports kora_lib's
    Lucide set, ox-compatible Font Awesome names, and safe HTTP/NUI image URLs.
  - `iconColor?: string` — CSS colour for the icon.
  - `iconAnimation?: string` — `spin`, `spinPulse`, `spinReverse`, `pulse`,
    `beat`, `fade`, `beatFade`, `bounce`, or `shake`.
  - `alignIcon?: "top" | "center"` — Vertical icon alignment.
  - `id?: string | finite number` — Replaces a live toast with the same ID.
  - `showDuration?: boolean` — Set false to hide the lifetime indicator.
  - `style?: table` — Scalar CSS values style the toast. Nested
    `title`/`description`/`message`/`text` selectors may contain scalar CSS
    values for those child regions; other nested selectors are ignored.

Notification messages render as safe GitHub-flavoured Markdown. Raw HTML is
ignored and unsafe URL protocols are rejected.

#### `Kora.notify.send(src, payload)` — server
Sends a notification to a specific player.

##### Parameters
- `src: integer` — Server ID of the target player, or `-1` for every connected player.
- `payload: KoraNotifyPayload` — Same shape as the client version.

`src` must be `-1` or a positive integer server ID. Invalid recipients are
logged and dropped, just like malformed payloads.
