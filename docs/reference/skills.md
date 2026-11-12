---
title: "Skills bridge"
sidebar_position: 46
---

# Skills bridge

`Kora.skills` is an optional bridge for servers running `kora_skills`. It does not
make kora_lib depend on that resource: every function is safe when `kora_skills` is
absent, stopped, or restarting.

The bridge API is `Kora.skills.isAvailable()`, `Kora.skills.get(...)`,
`Kora.skills.getAll(...)`, `Kora.skills.hasLevel(...)`, `Kora.skills.add(...)`, and
`Kora.skills.adjustMinigame(...)`.

Client:

```lua
if Kora.skills.hasLevel('mining', 20) then
    -- Client-side presentation gate only; the server must repeat this check.
end

local options = Kora.skills.adjustMinigame('mining', 'skillbar', { zoneSize = 0.18 })
```

Server:

```lua
local skill = Kora.skills.get(src, 'mining')
if not Kora.skills.hasLevel(src, 'mining', 20) then return end

local added, err = Kora.skills.add(src, 'mining', 25, mineCoords, 4.0)
```

`Kora.skills.add` is server-only and requires positive integer player source and
award amount, a non-empty skill name, and finite coordinates/distance when a
location is supplied. `hasLevel` requires a positive integer level.
`adjustMinigame` also requires a positive integer player source plus non-empty
skill and game-type names. It maps an already-resolved minigame configuration through the
player's configured skill bonus; it never permits a client to mint a proof or
bypass the minigame server checks.

Client reads and presentation-only minigame adjustment use the same non-empty
skill/game-type and positive integer level requirements. They remain optional:
when `kora_skills` is unavailable, reads return no data and adjustment leaves the
provided options unchanged.
