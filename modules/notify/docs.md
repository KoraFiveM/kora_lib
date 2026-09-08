# Notify module

## Overview
Shows a title/message notification (a toast) to one player, every connected player, or the local player, rendered by the NUI unless `Config.third_party_notify` routes it through your own notification resource instead.

## API

### `QB.notify.send(payload)` — client
Shows a notification on the local player.

#### Parameters
- `payload: QBNotifyPayload`
  - `title?: string`, `message?: string` — At least one is required. Both must be strings.
  - `duration?: integer` — Milliseconds. Defaults to `Config.notify.defaultDuration`, capped at `Config.notify.maxDuration`.
  - `type?: "info" | "success" | "warning" | "error"` — Visual variant (accent colour + icon). Defaults to `Config.notify.defaultType`.
  - `position?: "top-left" | "top-center" | "top-right" | "bottom-left" | "bottom-center" | "bottom-right"` — Defaults to `Config.notify.defaultPosition`.
  - `icon?: string` — Overrides the variant's default icon. Supports qblib's
    Lucide set, ox-compatible Font Awesome names, and safe HTTP/NUI image URLs.
  - `iconColor?: string` — CSS colour for the icon.
  - `iconAnimation?: string` — `spin`, `spinPulse`, `spinReverse`, `pulse`,
    `beat`, `fade`, `beatFade`, `bounce`, or `shake`.
  - `alignIcon?: "top" | "center"` — Vertical icon alignment.
  - `id?: string | number` — Replaces a live toast with the same ID.
  - `showDuration?: boolean` — Set false to hide the lifetime indicator.
  - `style?: table` — Scalar CSS values style the toast. Nested
    `title`/`description`/`message`/`text` selectors may contain scalar CSS
    values for those child regions; other nested selectors are ignored.

Notification messages render as safe GitHub-flavoured Markdown. Raw HTML is
ignored and unsafe URL protocols are rejected.

#### Example
```lua
QB.notify.send({ title = "Saved", message = "Your changes were saved.", duration = 4000 })

QB.notify.send({
    title = "Payment failed",
    message = "Not enough cash on hand.",
    type = "error",
    position = "bottom-right",
})
```

### `QB.notify.send(src, payload)` — server
Sends a notification to a specific player.

#### Parameters
- `src: integer` — Server ID of the target player, or `-1` for every connected player.
- `payload: QBNotifyPayload` — Same shape as the client version.

### `QB.notify.sendToAll(payload)` — server
Shorthand for `QB.notify.send(-1, payload)`.

### `QB.notify.assert(payload)` — shared
Validates a payload, raising an assertion error if it's malformed (used internally by `send`, exported in case you want to validate before sending). Checks the *types* of `title`/`message`, not just their presence, and that `type`/`position` are recognised values.

### `QB.notify.withDefaults(payload)` — shared
Returns a copy of `payload` with `duration`/`type`/`position` filled in from `Config.notify`. `send` applies this before handing the payload to the NUI, so the browser never has to know Lua-side config values that aren't transmitted. The caller's own table is never mutated.

## Notes
- `duration` defaults to `Config.notify.defaultDuration` (5000ms) and must be `<= Config.notify.maxDuration` (120000ms by default).
- A malformed payload never throws out of `send` — it's caught internally and the notification is silently dropped.
- Toasts stack per position, newest nearest the screen edge, capped at 6 on screen at once (oldest dropped) so a spamming caller can't grow the overlay unboundedly.
- Set `Config.third_party_notify = true` to route every notification through the `qblib:notify:send` event instead of qblib's own NUI toast, if you'd rather use a different notification resource. In that mode the payload is forwarded exactly as given — `withDefaults` is *not* applied, since a third-party resource has its own defaults.
