# Print helpers

Shared structured-console helpers. Each function accepts any number of values, formats them on one line, and adds a colored severity prefix:

```lua
QB.print.debug(...)
QB.print.info(...)
QB.print.warn(...)
QB.print.error(...)
QB.print.success(...)
```

Tables are encoded as indented JSON with sorted keys. Numbers, booleans, strings, `nil`, and functions are converted to readable text without changing the values passed by the caller.
If a table cannot be JSON-encoded (for example, it contains a cycle), the
helper falls back to its Lua string representation rather than throwing from a
diagnostic call.

```lua
QB.print.info('player loaded', {
    source = source,
    license = license,
})
```

These are presentation helpers, not persistent logging. Use `QB.logging.event` when an event needs ring-buffer statistics or optional Discord delivery.
