# permissions module guide

## Purpose
A thin, generic wrapper over FiveM's ace/principal system. Moved out of qbcore: `getLevel`/`hasPermission` never touched qbcore's player/identity model, only ace principals -- the only part of qbcore's old permissions module that genuinely needs the framework is `addPermission` (it resolves a player's identity to grant a runtime principal), which stayed in qbcore.

## Why the level list and prefix are parameters, not config
qbcore's permission vocabulary (`'user'`/`'mod'`/`'admin'`/`'god'`) and its ace namespace (`qbcore.<level>`) are product choices, not something qblib should hardcode -- qblib is a shared resource, and baking in one consumer's vocabulary would make it awkward for anything else (e.g. a standalone admin resource) to use the same ACE-checking logic under its own namespace without colliding with or being confused for qbcore's. `getLevel(src, levels, prefix)` and `hasPermission(src, permission, prefix)` take both as arguments instead; qbcore's own `Core.permissions.getPermission`/`hasPermission` are one-line wrappers that supply its `LEVELS` table and `'qbcore'` prefix.

## Implementation notes
- **`getLevel` always matches `'user'`** if it's in the `levels` list, regardless of any ace grant -- it's the vocabulary's floor, not something that needs an explicit principal.
- **Both `group.<level>` and `<prefix>.<level>`/`<prefix>.<permission>` are checked** -- `group.*` lets a server reuse ace groups already granted for other purposes (e.g. a `group.admin` set up for a different resource) without redeclaring them under this prefix too.
- **`hasPermission` additionally checks `command.<permission>`** -- a narrower principal for granting one specific command/permission string without granting the whole level it would otherwise imply.
- **Server-only** -- `IsPlayerAceAllowed` only exists server-side; there's nothing for a client realm to do here.

## Testing
`test/smoke/permissions.lua` mocks `IsPlayerAceAllowed` with a settable principal set per test. Covers: `getLevel` returning the highest matching level and falling back to `'user'`, `group.<level>` and `<prefix>.<level>` both granting a level, `hasPermission` always allowing `'user'`, and its `command.<permission>` fallback.
