---
title: Version check
---

# Version check

Server-side helper for comparing a resource's installed version against the version declared in its raw GitHub fxmanifest.lua and printing a link to the patch-notes page when an update is available.

See the module guide (../../modules/versioncheck/docs.md) for setup.

## Functions

### Kora.versioncheck.check(remoteManifestUrl, patchNotesUrl) -- server

Starts an asynchronous request for the remote fxmanifest.lua. If the caller's installed version differs, it prints the version comparison and converts the raw patch-notes URL into a GitHub page URL. The calling resource is identified through the export invocation; its installed version comes from its fxmanifest.lua metadata.

    Kora.versioncheck.check(
        'https://raw.githubusercontent.com/KoraFiveM/server-checker/main/fxmanifest.lua',
        'https://raw.githubusercontent.com/KoraFiveM/server-checker/main/PATCHNOTES.md'
    )
