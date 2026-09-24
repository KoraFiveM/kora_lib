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
Input-dialog and TextUI option tables default only when omitted; explicit
non-table values fail at the call site.

Input-dialog rows and their `options` lists must be tables. Empty lists remain
valid, while sparse or keyed lists and non-table option entries fail before a
field can disappear during translation. The same rule applies when registering multiple context
definitions; a single context remains a keyed definition table. Context option
maps may use either numeric or string keys, but every option value must be a
table.
Radial registration likewise requires a non-empty ID and dense `items` array
(or an empty one); dynamically added radial items also require non-empty IDs.

List-menu options follow the same rule: registration and whole-list
`setMenuOptions` updates require a dense array (or an empty list) of option
tables. A single indexed update requires an existing positive integer index and
an option table. Updating an open list menu patches that same panel immediately;
subsequent callbacks use the replacement option data.

List-menu values, checkboxes, live callbacks, start positions, close keys, and
`close=false` selections use token-validated non-terminal NUI events. Radial
submenu transitions, keep-open selections, and live registry changes use the
same request token, so neither surface closes and reopens merely to deliver a
callback or update. Re-registering the currently open context refreshes that
same panel immediately.

Ox context and list menus send `presentation = "panel"` in the internal
`openMenu` payload. This selects qblib's compact non-modal surface: there is no
backdrop or search filter, while keyboard selection and Escape/Backspace close
behavior remain available. A context with a parent also sends `back = true`.
The header Back control then emits the token-validated, non-terminal NUI event
`back` with an empty data object. Submenu confirmation is non-terminal too.
The provider changes the active definition and sends a token-matched
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

`alertDialog` accepts a non-negative finite integer timeout in milliseconds;
pass `nil` or `false` to leave the dialog open until it is answered or closed.

Custom `skillCheck` difficulties require finite numeric `areaSize` and
`speedMultiplier` values. Its optional input-key list must be a non-empty dense
array, so every requested key reaches the browser. The existing speed clamp
still handles zero or negative multipliers compatibly.

`notify` retains ox's lenient default: a missing, invalid, or non-finite
duration uses `3000` milliseconds.
