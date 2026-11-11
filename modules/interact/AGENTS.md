# Interact module

- `client.lua` is a client-only, game-input-driven zone interaction module. It never grants NUI focus and all browser traffic must go through `Kora.nui`.
- Public functions are `Kora.interact.open`, `close`, `isActive`, `addCircleZone`, `addBoxZone`, `removeZone`, `addTargetModel`, and `addTargetEntity`.
- Preserve the UI contract in `web/src/components/interact/InteractSelect.tsx`: `openInteract`, `scroll`, `select`, `hideInteract`, plus `selectOption` and `closeInteract` NUI callbacks. The selector receives labels only; do not expose action/event data to the NUI.
- Zone creation delegates to `Kora.zones`; do not revive legacy `RegisterZone` or `exportChange` helpers. Keep target option filtering and dispatch server-authoritative where appropriate.
- `Config.ui.interact` is the feature switch. All controls come from `Config.interact` and are disabled only while a selector is active.
- Keep `docs.md` and `test/smoke/interact.lua` in sync with all public API or contract changes.
