# qblib agent guide

## Project overview
This repository is a lightweight Lua library for FiveM-style export registration. The public API is built around a global `QB` table that is populated by modules and exposed via the `exports` system.

## File layout
- `init.lua` initializes the dynamic `QB` namespace proxy.
- `build/initiate.lua` creates the base `QB` table.
- `build/finalise.lua` exports each top-level `QB` function/table to the resource environment.
- `modules/` contains feature modules, each under its own subfolder.
- `local/` contains infrastructure modules (`resources`, `callback`, `events`) that other modules build on — same per-folder `shared`/`client`/`server` layout and same `QB.<module>` registration as `modules/`, just loaded from a separate tree. `modules/**` is globbed in `fxmanifest.lua`, but `local/**` is listed file-by-file instead: `local/resources` must load before `local/callback`/`local/events` (they call `QB.resources.registry()`/`serverRegistry()` at their own load time), and a `local/**/client.lua`-style glob expands alphabetically — "resources" would sort after both. Add a new `local/` module's `client.lua`/`server.lua` to that explicit list in `fxmanifest.lua`, after `local/resources`.

## Conventions
- Use one module per folder inside `modules/`.
- Keep module names lowercase and namespaced under `QB.<module>`.
- Exported functions should be attached to the module table, for example `QB.stream.loadModel`.
- Prefer simple, explicit Lua APIs with doc comments.
- Validate arguments early and fail with clear assertions.
- Keep utility functions small and deterministic.

## Module registration pattern
A module should be defined like this:

```lua
function QB.stream.loadModel(model, cb)
    -- implementation
end
```

`QB.<module>` does not need to be initialized manually. The `__index` metatable on `QB` (`build/initiate.lua`) auto-creates the module table the first time it's referenced.

The finalization step automatically converts each module entry into an exported function name like `stream_loadModel` when the build script runs.

## UI conventions

All NUI is **headless**:
- The NUI page renders nothing and holds no input/mouse focus by default. It only becomes visible/focused in direct response to an explicit message from Lua, and must give up focus the instant that interaction ends.
- Prefer world-space/game-input interaction (raycasts, `RegisterKeyMapping`, scroll wheel) over NUI mouse focus wherever focus would otherwise fight the player's camera control — e.g. `modules/zones`' in-world creator places points by aiming + a keypress rather than clicking through a menu.
- Every module that talks to the NUI goes through `QB.nui.*` (`modules/nui/`) rather than calling `SendNUIMessage`/`RegisterNUICallback` directly, so focus handling and the message contract stay in one place.

### UI (`web/`) layout
The NUI frontend is a React app under `web/`, built with Vite to `web/build/` (source in `web/src/`). `web/build/` is committed — FiveM serves it statically, there's no build step at resource-start time — while `web/node_modules/` is not. Rebuild with `pnpm install && pnpm build` inside `web/` after any UI change and commit the result.

The NUI has exactly one permanent theme (dark) — it's a fixed game overlay, not a user-configurable app, so there's no light/dark toggle to serve (`web/src/styles/globals.css`). Every `QB.nui.request` call carries a random per-request token the NUI must echo back in its response (`web/src/lib/fetchNui.ts`'s `respondToNui`) — see `modules/nui/AGENTS.md` for why.

`Config.ui.accentColor` and the HSL tokens derived from it live in `modules/theme`, not inline in `modules/nui` — that's what lets an external resource pull the same tokens for its own NUI (`QB.theme.tokens()`) instead of only qblib's own frontend being able to match the configured brand.

### Legacy compat (`compat/`)
The standalone `qb-menu`, `qb-input` and `qb-minigames` resources are deprecated in favour of `QB.nui.openMenu`/`openContextMenu`/`openRadialMenu`/`openInputDialog` and `QB.minigames.play`. `compat/client/qb-menu.lua` and `compat/client/qb-input.lua` keep `exports['qb-menu']:openMenu/closeMenu` and `exports['qb-input']:ShowInput` working unmodified by translating them onto those same `QB.nui.*` calls and registering under the `qb-menu`/`qb-input` export identities (`provide 'qb-menu'`/`provide 'qb-input'` plus the `__cfx_export_` hijack — same pattern as `qbtarget/client/compat/ox-target.lua` and `qbcore/compat/*`). `compat/client/qb-minigames.lua` does the same for `exports['qb-minigames']:Hacking/KeyMinigame/Lockpick/StartPinpad/Quiz/Skillbar/WordGuess/WordScramble` against `QB.minigames.play` — see `modules/minigames/docs.md`'s "Legacy compat" section for its two documented mechanic divergences (Lockpick, Skillbar). They load after `modules/**/client.lua` (they call `QB.nui.*`/`QB.minigames.*`) and before `build/finalise.lua`, same ordering rule qbcore's own `compat/*` uses. See `modules/nui/docs.md`'s "Legacy compat" section for the qb-menu/qb-input field mapping and caveats.

## Naming guidance
- Module names should be nouns or domain names such as `stream`, `inventory`, `player`, `vehicle`.
- Function names should be camelCase, with descriptive verbs where possible.
- Avoid creating deeply nested namespaces beyond `QB.<module>.<function>`.

## Maintenance rules
- Update the module docs when adding or removing public functions.
- Keep examples minimal and grounded in current usage.
- Prefer consistency over clever abstractions.
- Do not introduce hidden global state unless it is clearly intended and documented.

## Testing
- `test/smoke/` has one plain-Lua smoke test file per module (`test/smoke/<module>.lua`), covering its public `QB.<module>` API against mocked FiveM natives. `test/mocks.lua` holds natives shared across modules (CreateThread/Wait, RegisterNetEvent/TriggerServerEvent/TriggerClientEvent, promise, joaat, ...); natives specific to one module (e.g. `CreatePed`, `glm.vec3`) are mocked directly in that module's own smoke test file. `test/harness.lua` is the tiny assert/report framework they share.
- Run the full suite with `test/run.sh` (needs `lua` on PATH; set `LUA=lua5.4` etc. to pick a specific interpreter). Each file is also runnable on its own, e.g. `lua test/smoke/zones.lua`.
- When adding a new module, add a matching `test/smoke/<module>.lua` alongside it. When changing a module's public API, update its smoke test in the same change — don't let it silently fall out of sync with the code or its docs.md.
- `mocks.install()` returns a handle with helpers worth knowing before hand-rolling your own: `fire(name, ...)` dispatches a lifecycle event (`playerDropped`, `onClientResourceStop`), `lastEntry(entries, name)` pulls the most recent recorded event of a given name out of `triggeredServerEvents`/`triggeredClientEvents`, and `step()` resumes every still-suspended `CreateThread` coroutine once. `step()` is what makes tick-driven behavior testable at all — the mock `CreateThread` resumes each thread exactly once, so anything a `while true ... Wait() end` loop does on later iterations (zone enter/exit tracking, the cache refresh) only happens if a test asks for it.
- Two client/server files that both define the *same* `QB.<module>.<fn>` name (e.g. `QB.notify.send`, `QB.callback.register`) will collide if loaded into one mocked process, since the second file's definition wins that table slot. Existing smoke tests (`test/smoke/notify.lua`, `test/smoke/callback.lua`) work around this by capturing a direct reference to each realm's function right after its file loads, before the other realm's file overwrites it — follow that pattern rather than assuming `QB.<module>.<fn>` is stable across both dofiles.
