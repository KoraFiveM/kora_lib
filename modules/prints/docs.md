# Print helpers (compatibility)

`Kora.print.debug`, `Kora.print.info`, `Kora.print.warn`, `Kora.print.error` and
`Kora.print.success` retain their variadic call shape. They now delegate to
`Kora.logging` with event `legacy.print`; success maps to info. Scalar arguments
form the message; table arguments become structured, recursively redacted fields.
Debug now obeys the configured logging threshold. Calls never intentionally dump
whole objects or bypass central filtering.

New code uses `Kora.logging.info('player.loaded', 'Player loaded', { playerId = src })`.
See [Logging](../logging/docs.md) for levels, capture and JSON export. This
adapter does not provide durable audit storage or automatic Discord delivery.
