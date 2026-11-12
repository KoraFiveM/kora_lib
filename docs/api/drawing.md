---
title: "Drawing"
sidebar_position: 25
---


# Drawing

Draws text at a point in the game world, for example an E prompt above an ATM. The text lasts for one frame, so draw it repeatedly while it should remain visible. A distance limit prevents extra drawing work for labels far from the player.

Namespace: `Kora.drawing` · Source: `modules/drawing/client.lua`

## text3d options

If options or a field is omitted, Config.drawing.text3d supplies the default. A `?` after a name means the option is optional.

| Option | Type | Description |
| --- | --- | --- |
| `font?` | integer | Non-negative game font id. |
| `scale?` | number | Positive finite text size. |
| `color?` | table | RGBA channels r, g, b, a; each is an integer from 0 to 255. |
| `maxDistance?` | number | Finite non-negative metres from player. Beyond it no drawing natives run. |
| `outline?` | boolean | Whether text has an outline. |

## When to use it

Use this for short in-world prompts and labels. Stop the loop when the prompt is no longer needed, such as when the player walks away or the target disappears.

## Functions

text3d draws one frame; call it in a loop while you want the label to stay visible.

### `Kora.drawing.text3d(coords, text, options?)`

Draws a single frame of world-space text. It does not register a persistent label.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `coords` | vector3 | Finite world position. |
| `text` | string | Non-empty text. Use GTA token ~n~ for a new line. |
| `options?` | table | Optional font, scale, RGBA color, distance, and outline. |

**Returns**

- **return** — no value.

**Example**

```lua
CreateThread(function()
    while DoesEntityExist(targetEntity) do
        Kora.drawing.text3d(GetEntityCoords(targetEntity), '[E] Open')
        Wait(0)
    end
end)
```

**Representative console output**

```text
The label is drawn repeatedly once per frame while targetEntity exists.
```

## Limits and related APIs

Only available on client because it draws on the calling player’s screen. Explicit false is validated as a value; it does not mean use the default.

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/drawing/docs.md` or `local/drawing/docs.md`) that the reference above does not state.

### API

#### `Kora.drawing.text3d(coords, text, options)`
Draws one frame of world-space 3D text anchored at `coords`. Not a persistent registration -- like a raw `DrawMarker` call, call it again every frame it should stay visible.

##### Example
```lua
CreateThread(function()
    while HasTarget() do
        Kora.drawing.text3d(GetEntityCoords(targetEntity), "[E] Open")
        Wait(0)
    end
end)
```

Called cross-resource via export (e.g. from a targeting resource):
```lua
exports.kora_lib:drawing_text3d(promptCoords, ("%d options"):format(#options), { scale = 0.4 })
```
