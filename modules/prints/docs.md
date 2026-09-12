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

```lua
QB.print.info('player loaded', {
    source = source,
    license = license,
})
```

These are presentation helpers, not persistent logging. Use `QB.logging.event` when an event needs ring-buffer statistics or optional Discord delivery.
