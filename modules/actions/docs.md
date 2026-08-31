# Actions module

`QB.actions.run` composes a resource-owned server authorization step with one
exclusive client progressbar or server-validated minigame. It does not grant
items, validate locations, or decide rewards: those remain in the resource's
`begin`/`complete` server handlers.

```lua
QB.actions.run({
    label = station.label,
    duration = station.duration,
    minigame = station.minigame,
    disable = { move = true, combat = true },
    begin = function(drug, stage)
        return QB.callback.trigger('my-resource:server:begin', drug, stage)
    end,
    complete = function(result, drug, stage)
        TriggerServerEvent('my-resource:server:complete', drug, stage,
            result.token, result.completed, result.proof)
    end,
}, drugName, stageName)
```

Only one action can run at a time. A rejected `begin` returns `false, reason`;
otherwise the first return is `true` after `complete` has been called.

`QB.actions.isActive()` reports whether this client currently has an action in
progress.
