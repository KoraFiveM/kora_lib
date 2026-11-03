# Print helpers

Shared structured-console helpers for readable, structured output in the FiveM console. Every helper accepts zero or more values, formats each argument independently, joins the results with spaces, and writes one line with a severity prefix. These helpers do not save records or send them to Discord; use `Kora.logging.event` for tracked events.

## API

### `Kora.print.debug(...)`
Writes a diagnostic line with the `[DEBUG]` prefix. Use it for details useful while tracing a flow; remove or gate high-volume calls in frequently running code.

#### Parameters
- `...: any` — Any number of values. Tables are encoded as indented JSON with sorted keys when possible. Other values use Lua's `tostring`; `nil` is written as `nil`, and numbers receive a console color reset around them.

#### Returns
- No return value — The formatted line is sent to the console with `print`.

### `Kora.print.info(...)`
Writes an informational line with the `[INFO]` prefix. Use it for useful lifecycle or operational messages that do not indicate a warning or failure.

#### Parameters
- `...: any` — Any number of values formatted by the shared formatter.

#### Returns
- No return value — The formatted line is sent to the console with `print`.

### `Kora.print.warn(...)`
Writes a warning line with the `[WARNING]` prefix. Use it when an operation can continue but the caller should notice an unusual condition.

#### Parameters
- `...: any` — Any number of values formatted by the shared formatter.

#### Returns
- No return value — The formatted line is sent to the console with `print`.

### `Kora.print.error(...)`
Writes an error line with the `[ERROR]` prefix. It reports a failure but does not throw, retry, or alter control flow.

#### Parameters
- `...: any` — Any number of values formatted by the shared formatter.

#### Returns
- No return value — The formatted line is sent to the console with `print`.

### `Kora.print.success(...)`
Writes a success line with the `[SUCCESS]` prefix. Use it for a completed operation that is useful to see in the console.

#### Parameters
- `...: any` — Any number of values formatted by the shared formatter.

#### Returns
- No return value — The formatted line is sent to the console with `print`.

```lua
Kora.print.debug(...)
Kora.print.info(...)
Kora.print.warn(...)
Kora.print.error(...)
Kora.print.success(...)
```

Tables are encoded as indented JSON with sorted keys. Numbers, booleans, strings, `nil`, and functions are converted to readable text without changing the values passed by the caller.
If a table cannot be JSON-encoded (for example, it contains a cycle), the
helper falls back to its Lua string representation rather than throwing from a
diagnostic call.

```lua
Kora.print.info('player loaded', {
    source = source,
    license = license,
})
```

These are presentation helpers, not persistent logging. Use `Kora.logging.event` when an event needs ring-buffer statistics or optional Discord delivery.
