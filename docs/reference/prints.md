---
title: "Print helpers"
sidebar_position: 49
---

# Print helpers

Shared structured-console helpers. Each function accepts any number of values, formats them on one line, and adds a colored severity prefix:

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
