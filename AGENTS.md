# kora_lib agent guide

## Project overview
This repository is a lightweight Lua library for FiveM-style export registration. The public API is built around a global `Kora` table that is populated by modules and exposed via the `exports` system.

## File layout
- `init.lua` initializes the dynamic `Kora` namespace proxy.
- `build/initiate.lua` creates the base `Kora` table.
- `build/finalise.lua` exports each top-level `Kora` function/table to the resource environment.
- `modules/` contains feature modules, each under its own subfolder.
- `local/` contains infrastructure modules (`resources`, `callback`, `events`) that other modules build on — same per-folder `shared`/`client`/`server` layout and same `Kora.<module>` registration as `modules/`, just loaded from a separate tree. `modules/**` is globbed in `fxmanifest.lua`, but `local/**` is listed file-by-file instead: `local/resources` must load before `local/callback`/`local/events` (they call `Kora.resources.registry()`/`serverRegistry()` at their own load time), and a `local/**/client.lua`-style glob expands alphabetically — "resources" would sort after both. Add a new `local/` module's `client.lua`/`server.lua` to that explicit list in `fxmanifest.lua`, after `local/resources`.
- `compat/provider.lua` is loaded into each consumer by `init.lua`; this keeps
  provided export aliases owned by the resource that registered them.

## Conventions
- Use one module per folder inside `modules/`.
- Keep module names lowercase and namespaced under `Kora.<module>`.
- Exported functions should be attached to the module table, for example `Kora.stream.loadModel`.
- Prefer simple, explicit Lua APIs with doc comments.
- Validate arguments early and fail with clear assertions.
- Keep utility functions small and deterministic.

## Module registration pattern
A module should be defined like this:

```lua
function Kora.stream.loadModel(model, cb)
    -- implementation
end
```

`Kora.<module>` does not need to be initialized manually. The `__index` metatable on `Kora` (`build/initiate.lua`) auto-creates the module table the first time it's referenced.

The finalization step automatically converts each module entry into an exported function name like `stream_loadModel` when the build script runs.

## UI conventions

All NUI is **headless**:
- The NUI page renders nothing and holds no input/mouse focus by default. It only becomes visible/focused in direct response to an explicit message from Lua, and must give up focus the instant that interaction ends.
- Prefer world-space/game-input interaction (raycasts, `RegisterKeyMapping`, scroll wheel) over NUI mouse focus wherever focus would otherwise fight the player's camera control — e.g. `modules/zones`' in-world creator places points by aiming + a keypress rather than clicking through a menu.
- Every module that talks to the NUI goes through `Kora.nui.*` (`modules/nui/`) rather than calling `SendNUIMessage`/`RegisterNUICallback` directly, so focus handling and the message contract stay in one place.

### UI (`web/`) layout
The NUI frontend is a React app under `web/`, built with Vite to `web/build/` (source in `web/src/`). `web/build/` is committed — FiveM serves it statically, there's no build step at resource-start time — while `web/node_modules/` is not. Rebuild with `pnpm install && pnpm build` inside `web/` after any UI change and commit the result.

The NUI has exactly one permanent theme (dark) — it's a fixed game overlay, not a user-configurable app, so there's no light/dark toggle to serve (`web/src/styles/globals.css`). Every `Kora.nui.request` call carries a random per-request token the NUI must echo back in its response (`web/src/lib/fetchNui.ts`'s `respondToNui`) — see `modules/nui/AGENTS.md` for why.

The palette and token derivation live in the standalone `kora_theme` resource.
`modules/theme` permanently forwards the legacy `Kora.theme` API to kora_theme;
kora_lib must not introduce a second palette or token implementation.

### Legacy compat (`compat/`)
The standalone `qb-menu`, `qb-input` and `qb-minigames` resources are deprecated in favour of `Kora.nui.openMenu`/`openContextMenu`/`openRadialMenu`/`openInputDialog` and `Kora.minigames.play`. `compat/client/qb-menu.lua` and `compat/client/qb-input.lua` keep `exports['qb-menu']:openMenu/closeMenu` and `exports['qb-input']:ShowInput` working unmodified by translating them onto those same `Kora.nui.*` calls and registering under the `qb-menu`/`qb-input` export identities (`provide 'qb-menu'`/`provide 'qb-input'` plus the `__cfx_export_` hijack — same pattern as `kora_target/client/compat/ox-target.lua` and `kora_core/compat/*`). `compat/client/qb-minigames.lua` does the same for `exports['qb-minigames']:Hacking/KeyMinigame/Lockpick/StartPinpad/Quiz/Skillbar/WordGuess/WordScramble` against `Kora.minigames.play` — see `modules/minigames/docs.md`'s "Legacy compat" section for its two documented mechanic divergences (Lockpick, Skillbar). They load after `modules/**/client.lua` (they call `Kora.nui.*`/`Kora.minigames.*`) and before `build/finalise.lua`, same ordering rule kora_core's own `compat/*` uses. See `modules/nui/docs.md`'s "Legacy compat" section for the qb-menu/qb-input field mapping and caveats.

## Naming guidance
- Module names should be nouns or domain names such as `stream`, `inventory`, `player`, `vehicle`.
- Function names should be camelCase, with descriptive verbs where possible.
- Avoid creating deeply nested namespaces beyond `Kora.<module>.<function>`.

## Maintenance rules
- Update the module docs when adding or removing public functions.
- Keep examples minimal and grounded in current usage.
- Prefer consistency over clever abstractions.
- Do not introduce hidden global state unless it is clearly intended and documented.

## Testing
- `test/smoke/` has one plain-Lua smoke test file per module (`test/smoke/<module>.lua`), covering its public `Kora.<module>` API against mocked FiveM natives. `test/mocks.lua` holds natives shared across modules (CreateThread/Wait, RegisterNetEvent/TriggerServerEvent/TriggerClientEvent, promise, joaat, ...); natives specific to one module (e.g. `CreatePed`, `glm.vec3`) are mocked directly in that module's own smoke test file. `test/harness.lua` is the tiny assert/report framework they share.
- Run the full suite with `test/run.sh` (needs `lua` on PATH; set `LUA=lua5.4` etc. to pick a specific interpreter). Each file is also runnable on its own, e.g. `lua test/smoke/zones.lua`.
- When adding a new module, add a matching `test/smoke/<module>.lua` alongside it. When changing a module's public API, update its smoke test in the same change — don't let it silently fall out of sync with the code or its docs.md.
- `mocks.install()` returns a handle with helpers worth knowing before hand-rolling your own: `fire(name, ...)` dispatches a lifecycle event (`playerDropped`, `onClientResourceStop`), `lastEntry(entries, name)` pulls the most recent recorded event of a given name out of `triggeredServerEvents`/`triggeredClientEvents`, and `step()` resumes every still-suspended `CreateThread` coroutine once. `step()` is what makes tick-driven behavior testable at all — the mock `CreateThread` resumes each thread exactly once, so anything a `while true ... Wait() end` loop does on later iterations (zone enter/exit tracking, the cache refresh) only happens if a test asks for it.
- Two client/server files that both define the *same* `Kora.<module>.<fn>` name (e.g. `Kora.notify.send`, `Kora.callback.register`) will collide if loaded into one mocked process, since the second file's definition wins that table slot. Existing smoke tests (`test/smoke/notify.lua`, `test/smoke/callback.lua`) work around this by capturing a direct reference to each realm's function right after its file loads, before the other realm's file overwrites it — follow that pattern rather than assuming `Kora.<module>.<fn>` is stable across both dofiles.

## Documentation

User-facing documentation lives in `docs/` (Markdown, published via the Kora Docusaurus site, kora_docs_next). Read `docs/index.md` first; it links every page.

Docs layout (update the matching page when behaviour changes):
- `docs/index.md` - hub: overview, features, documentation map.
- `docs/installation.md` - install order, adding the proxy to a resource, step-by-step manifest walkthrough, troubleshooting start-up, optional legacy imports.
- `docs/how-to-use.md` - how to read the API pages and make a first call.
- `docs/commands.md` - commands and key mappings kora_lib registers.
- `docs/api/index.md` and `docs/api/<module>.md` - one page per `Kora` module: parameter tables, returns, examples, then "Additional notes from the module guide".
- Topic pages: `configuration.md`, `events.md`, `exports.md`, `permissions.md`, `database.md`, `dependencies.md`, `ui.md`, `performance.md`, `legacy-compat.md`, `using-the-api.md`, `troubleshooting.md`, `contributing.md`, `reference.md` (module path map) and `migration/` (ox_lib).

Feature and behaviour changes must update the matching docs in the same change. When you add, change, or remove a feature, config option, command, export, event, item, permission, or database table/column, update the matching page in `docs/` in the same change. Keep docs accurate to the code; do not document behaviour that does not exist.

Each module's guide exists twice: `modules/<name>/docs.md` or `local/<name>/docs.md` (required by `test/smoke/api_contract.lua`) and its published page `docs/api/<name>.md`, which is what the documentation site imports. Change both in the same commit and keep their content in step. `docs/reference.md` must keep listing `/reference/<name>/` for every module (the smoke test reads it).

Docs rules: plain Markdown with `title`/`sidebar_position` front matter (no `id`/`slug`), relative links only between docs pages, assets inside `docs/`, fenced code blocks with a language, and no raw `<`, `>`, `{`, `}` outside code (pages are parsed as MDX). The release version comes from `fxmanifest.lua`'s `version` field.

## Shared contribution standards

Read [CONTRIBUTING.md](CONTRIBUTING.md) before editing. Humans and agents follow
the same Kora standards and self-contained local Lua checks. Preserve the domain
constraints above and in module guides; record policy conflicts explicitly.
