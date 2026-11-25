---
title: Version check
---

# Version check

Server-side helper for checking a resource's installed version against its latest raw GitHub manifest and printing the patch notes the resource is missing.

See the [module guide](../../modules/versioncheck/docs.md) for setup and the expected patch-note format.

## Functions

### `Kora.versioncheck.check(remoteManifestUrl, patchNotesUrl)` -- server

Starts asynchronous requests for a raw `fxmanifest.lua` and, if the caller's installed version differs, a raw Markdown patch-notes file. The calling resource is identified through the export invocation and its `version` is read from FiveM's resource metadata parsed from its `fxmanifest.lua`.

Patch-note headings should be top-level bullets containing `major.minor.patch`; nested bullet details for versions newer than the installed version and no newer than the remote version are printed without their Markdown bullet markers.

```lua
Kora.versioncheck.check(
    'https://raw.githubusercontent.com/KoraFiveM/server-checker/main/fxmanifest.lua',
    'https://raw.githubusercontent.com/KoraFiveM/server-checker/main/PATCHNOTES.md'
)
```
