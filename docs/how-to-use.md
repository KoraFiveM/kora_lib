---
title: "How to use"
sidebar_position: 3
---


# How to use

Once Kora Lib is installed, browse the functions in the sidebar to find what you need. Every function has a short explanation and an example you can copy into your own resource.

## Load Kora Lib in your resource

Every resource that uses Kora Lib loads it from its `fxmanifest.lua`. Below is a trimmed copy of the manifest of a real resource, `kora_garages`. The highlighted line is the one that makes the `Kora` tools available in all of your Lua files.

```lua title="fxmanifest.lua" {16}
fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'kora_garages'
provide 'qb-garages'
version '0.3.6'
description 'Player-owned vehicle garages: store/retrieve, job and gang fleets, private house garages, and an impound lot with a fee'

dependency 'kora_theme'
dependency 'kora_lib'
dependency 'kora_core'
dependency 'kora_target'
dependency 'kora_sql'

shared_script '@kora_lib/init.lua' -- ADD THIS LINE IN THE FX MANIFEST TO LOAD ALL OF Kora_lib
shared_script '@kora_core/init.lua'

shared_scripts {
    'shared/config.lua',
}

server_scripts {
    '@kora_sql/init.lua',
    'server/schema.lua',
    'server/property.lua',
    'server/server.lua',
    'server/compat.lua',
}

client_scripts {
    'client/client.lua',
    'client/compat.lua',
}
```

- The `dependency` lines make FiveM start Kora Lib, and any other Kora resources you list, before your resource.
- Put `@kora_lib/init.lua` in `shared_script` (or at the top of `shared_scripts`) above your own files, so `Kora` is ready by the time they run.
- Each Kora resource has its own `init.lua`: add `@kora_core/init.lua` for Kora Core and `@kora_sql/init.lua` for Kora SQL. Kora SQL is server-only, so its line goes in `server_scripts`.
- New to editing a manifest? The Installation page has a step-by-step example.

## Make your first call

1. **Find what you want to do** — Kora Lib is a set of tools for creating or customizing resources for your server. Use the menu on the left to explore what’s available. Prints shows messages in your server console, Zones detects when players enter or leave an area, and NUI builds the menus and forms players see on screen. Click a category to see what it does and examples of how to use it.

2. **Open the page for your code** — Inside a category, choose the page that matches the Lua file you’re writing in: client, server, or shared. Each page lists every function’s inputs, what it returns, and an example.

3. **Check the parameters before copying** — Parameters are the values you put inside the parentheses. Each row shows the name, the type of value it expects, and what it does. A `?` after a name means you can leave it out. If a function takes an options table, its fields are listed above the functions.

4. **Try the example with your own values** — Swap the sample names, such as `vehicle` or `coords`, for variables from your own resource, and keep the arguments in the same order as the signature.

   ```lua
   Kora.print.info('resource started', GetCurrentResourceName())
   ```

5. **Check what comes back** — Some functions return a value, like a handle or true/false. When something can’t be completed, others return `false, reason` or `nil, reason`. Check the Returns section, and show or log the reason whenever you get one.

   ```lua
   local ok, reason = Kora.vehicle.delete(vehicle)
   if not ok then
       Kora.print.warn('Could not delete vehicle:', reason)
   end
   ```

## Where your code should make decisions

Use client code for what the player sees or controls, like a menu, marker, or progress bar. Use server code for anything that matters to your economy: money, inventory, permissions, ownership, and rewards. Players can modify their client, so the server must double-check important requests before it changes anything.

## Functions that wait for a response

Some functions pause until the player answers a dialog, a minigame ends, or a request comes back. The function’s page tells you when this happens. Call these from a thread, such as inside `CreateThread` or a command handler, so the pause can happen safely.
