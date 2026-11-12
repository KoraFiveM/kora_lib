---
title: Documentation upkeep
sidebar_position: 18
---

# Documentation upkeep

The guide beside each module is the in-repository source for that module's public behavior:

```text
modules/<name>/docs.md
local/<name>/docs.md
```

The documentation site imports only the `docs/` folder, so each of those guides is mirrored in `docs/api/<name>.md` (with `title` and `sidebar_position` front matter), indexed in [API reference](./api/index.md) and [API module map](./reference.md). The `docs/api/` page is the legacy function reference (parameter tables, returns, examples) followed by an "Additional notes from the module guide" section holding the guide's extra behaviour. **When you change a module, update its `docs/api/<name>.md` page in the same change**, and keep `docs.md` in step. The mirrors were created with a few corrections to claims that contradicted the code (deprecated-name fallbacks that do not exist); apply the same corrections to the in-repository guides when you next touch them.

## Documenting an API change

When a public function or contract changes:

1. Update the LuaLS declaration in `types.lua`.
2. Update the module's `docs.md` and its `docs/api/<name>.md` page with realm, signature, parameters, result shape, expected failures, lifecycle or ownership behavior, and a minimal example where usage is not obvious.
3. Update the matching smoke test in `test/smoke/`.
4. If this is a new module, add a row to [API reference](./api/index.md) and [API module map](./reference.md). The smoke test requires the module's `/reference/<name>/` path to appear in that file.
5. Run `test/run.sh`.

The API contract smoke test (`test/smoke/api_contract.lua`) discovers normal `Kora.<module>.<function>` definitions and fails when their namespace or function is missing from `types.lua`, or when the exact symbol is absent from the adjacent `docs.md`. It also reads `docs/reference.md`.

Pages must be plain Markdown with `title` and numeric `sidebar_position` front matter, relative links only, and no raw angle brackets or braces outside code (they are parsed as MDX).
