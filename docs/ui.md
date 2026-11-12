---
title: User interface
sidebar_position: 11
---

# User interface

kora_lib ships one NUI page, a React app built with Vite from `web/src/` into `web/build/`. `web/build/` is committed because FiveM serves it statically (`ui_page 'web/build/index.html'`); rebuild with `pnpm install && pnpm build` inside `web/` after UI changes.

The NUI is headless: it renders nothing and holds no focus until Lua sends an explicit message, and releases focus as soon as the interaction ends. Every module reaches it through [`Kora.nui`](./reference/nui.md), which adds a per-request token that the browser must echo back. It uses a single dark theme whose palette comes from `kora_theme`.

Interfaces provided: menus, context menus, radial menus, input dialogs, alerts, apps (including the blips settings app and the configuration editor workspace), notifications, text UI, progress bars, interaction selector and minigames. Each is documented on its module page in the [API index](./reference.md). The callback names the browser uses are listed in [Events and callbacks](./events.md).
