# permissions module guide

## Purpose
The central, generic server-side wrapper over FiveM's ace/principal system and
optional `Kora.discord` role authorization. It remains independent of kora_core's
player/identity model; runtime principal mutation belongs to consumers such as
kora_core.

## Why the level list and prefix are parameters, not config
kora_core's permission vocabulary (`'user'`/`'mod'`/`'admin'`/`'god'`) and its ace namespace (`kora_core.<level>`) are product choices, not something kora_lib should hardcode. `getLevel`, `hasLevel`, and `hasPermission` take a legacy prefix string or `{ prefix?, discordRoles? }`; kora_core can keep passing `'kora_core'`, while an admin resource can opt into its own Discord role map.

## Implementation notes
- **`getLevel` always matches `'user'`** if it's in the `levels` list, regardless of any ace grant -- it's the vocabulary's floor, not something that needs an explicit principal.
- **Both `group.<level>` and `<prefix>.<level>`/`<prefix>.<permission>` are checked** -- `group.*` lets a server reuse ace groups already granted for other purposes (e.g. a `group.admin` set up for a different resource) without redeclaring them under this prefix too.
- **`hasPermission` additionally checks `command.<permission>`** -- a narrower principal for granting one specific command/permission string without granting the whole level it would otherwise imply.
- **Discord is additive and fail-closed.** Only explicitly mapped levels or
  permissions consult `Kora.discord.hasAnyRole`. Bot/cache/identifier errors do
  not grant access and never suppress an ACE result. Keep ACE checks first so
  `group.admin` never depends on Discord availability.
- **`hasLevel` owns cascading.** The supplied level array is ordered highest
  to lowest; a resolved `admin` therefore satisfies a `mod` requirement without
  manual ACE principal chaining.
- **Public checks require a real player source.** `0`, fractional, and
  non-finite IDs are rejected before ACE or Discord calls; console authorization
  belongs to the caller's command path.
- **Server-only** -- `IsPlayerAceAllowed` only exists server-side; there's nothing for a client realm to do here.

## Testing
`test/smoke/permissions.lua` mocks `IsPlayerAceAllowed` and
`Kora.discord.hasAnyRole`. It covers ACE precedence (including `group.admin`),
Discord mapping/cascading/fail-closed behavior, optional prefixes, and exact
`command.<permission>` checks.
