# Skills bridge

`QB.skills` is an optional bridge for servers running `qbskills`. It does not
make qblib depend on that resource: every function is safe when `qbskills` is
absent, stopped, or restarting.

The bridge API is `QB.skills.isAvailable()`, `QB.skills.get(...)`,
`QB.skills.getAll(...)`, `QB.skills.hasLevel(...)`, `QB.skills.add(...)`, and
`QB.skills.adjustMinigame(...)`.

Client:

```lua
if QB.skills.hasLevel('mining', 20) then
    -- Client-side presentation gate only; the server must repeat this check.
end

local options = QB.skills.adjustMinigame('mining', 'skillbar', { zoneSize = 0.18 })
```

Server:

```lua
local skill = QB.skills.get(src, 'mining')
if not QB.skills.hasLevel(src, 'mining', 20) then return end

local added, err = QB.skills.add(src, 'mining', 25, mineCoords, 4.0)
```

`QB.skills.add` is server-only. `adjustMinigame` maps an already-resolved
minigame configuration through the player's configured skill bonus; it never
permits a client to mint a proof or bypass the minigame server checks.
