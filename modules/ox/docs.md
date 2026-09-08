# ox_lib provider bridge

`QB.ox` is the internal provider used by the separately named `ox_lib`
compatibility resource. Third-party scripts continue to load
`@ox_lib/init.lua` and call `lib.*`; they should not call this module directly.

The shim appends the originating resource name as private metadata. qblib uses
that owner for NUI requests, focus leases, progress/skill-check sessions, TextUI,
registered contexts, menus, and radial items, and disposes only that owner's
state when the consumer stops.

The bridge translates ox_lib alert, clipboard, context, input, menu, notify,
progress, radial, skill-check, TextUI, focus, and locale calls onto qblib's
single browser surface. It preserves ox_lib return values and callback/event
dispatch.

TextUI `style` accepts both property tables and CSS declaration strings. A
string is parsed only as declarations for the prompt's inline style; it cannot
install selectors or global stylesheet rules, and pointer events remain
disabled. Calling `hideTextUI` with no active ox-owned prompt is a no-op, so it
cannot disturb a native qblib TextUI entry beneath the compatibility layer.

List-menu values, checkboxes, live callbacks, start positions, close keys, and
`close=false` selections use authenticated non-terminal NUI events. Radial
submenu transitions, keep-open selections, and live registry changes use the
same request token, so neither surface closes and reopens merely to deliver a
callback or update.

Ox context and list menus send `presentation = "panel"` in the internal
`openMenu` payload. This selects qblib's compact non-modal surface: there is no
backdrop or search filter, while keyboard selection and Escape/Backspace close
behavior remain available. A context with a parent also sends `back = true`.
The header Back control then emits the authenticated, non-terminal NUI event
`back` with an empty data object. Submenu confirmation is non-terminal too.
The provider changes the active definition and sends a token-authenticated
`updateMenu` envelope containing the complete next `OpenMenuPayload`; the
browser resets the current root/title/rows/start selection in place. A stale or
wrong-token update is ignored. This keeps one mounted panel/request throughout
parent and child navigation. The public qblib dialog presentation is unchanged.

## Internal provider contract

The `ox_lib` compatibility resource is the only intended caller of these
owner-aware functions:

- dialogs and focus: `QB.ox.alertDialog`, `QB.ox.closeAlertDialog`,
  `QB.ox.inputDialog`, `QB.ox.closeInputDialog`, `QB.ox.setClipboard`,
  `QB.ox.setNuiFocus`, and `QB.ox.resetNuiFocus`;
- context menus: `QB.ox.registerContext`, `QB.ox.showContext`,
  `QB.ox.getOpenContextMenu`, and `QB.ox.hideContext`;
- menus: `QB.ox.registerMenu`, `QB.ox.showMenu`, `QB.ox.hideMenu`,
  `QB.ox.setMenuOptions`, and `QB.ox.getOpenMenu`;
- notifications and progress: `QB.ox.notify`, `QB.ox.defaultNotify`,
  `QB.ox.progressBar`, `QB.ox.progressCircle`, `QB.ox.cancelProgress`, and
  `QB.ox.progressActive`;
- radial menus: `QB.ox.registerRadial`, `QB.ox.getCurrentRadialId`,
  `QB.ox.hideRadial`, `QB.ox.addRadialItem`, `QB.ox.removeRadialItem`,
  `QB.ox.clearRadialItems`, `QB.ox.disableRadial`, and
  `QB.ox.showRadialMenu`;
- skill checks and TextUI: `QB.ox.skillCheck`, `QB.ox.cancelSkillCheck`,
  `QB.ox.skillCheckActive`, `QB.ox.showTextUI`, `QB.ox.hideTextUI`, and
  `QB.ox.isTextUIOpen`;
- locale/lifecycle: `QB.ox.getLocaleKey`, `QB.ox.setLocale`, and
  `QB.ox.disposeOwner`.

`QB.ox.setLocale` accepts the selected key, decoded ox locale catalog, and
origin owner. qblib retains the small browser-label subset and exposes it to
the NUI through both a startup handshake and live updates, so the persisted
ox locale is not lost when the compatibility resource starts before the page
has mounted.

All functions fail fast on a missing origin owner. Registrations and active
UI leases are removed by `disposeOwner`, so restarting one consumer cannot
leave its entries or focus attached to another resource.
