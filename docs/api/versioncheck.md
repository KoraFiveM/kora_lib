---
title: Version check
---

# Version check

Server-side helper for checking a resource's installed version against the latest value in a raw GitHub version file and printing the patch notes the resource is missing.

See the [module guide](../../modules/versioncheck/docs.md) for setup and the expected patch-note format.

## Functions

### `Kora.versioncheck.check(remoteVersionUrl, patchNotesUrl)` -- server

Starts asynchronous requests for a raw version file and, if the caller's installed version differs, a raw Markdown patch-notes file. The calling resource is identified through the export invocation; its installed `version` comes from its parsed `fxmanifest.lua` metadata.

Patch-note headings should be top-level version bullets in oldest-to-newest order. Nested details after the installed version through the latest version are printed without their Markdown bullet markers; pre-release suffixes are supported.

```lua
Kora.versioncheck.check(
    'https://raw.githubusercontent.com/KoraFiveM/server-checker/main/version.txt',
    'https://raw.githubusercontent.com/KoraFiveM/server-checker/main/PATCHNOTES.md'
)
```
