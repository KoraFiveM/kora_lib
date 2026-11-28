# Version check module

Compares the version in the calling resource's fxmanifest.lua with the version declared in a remote raw GitHub fxmanifest.lua. If the installed version is older than the remote one, it prints a link to the patch-notes file's GitHub page instead of printing patch-note details; a resource running a newer version stays quiet.

## API

### Kora.versioncheck.check(remoteManifestUrl, patchNotesUrl) -- server

Call this from the resource's server-side code. Both URLs must be publicly readable raw GitHub file URLs. The first must point to an fxmanifest.lua that declares its version using a form such as version '0.1.2'; the caller's own fxmanifest.lua must also declare a version. Version values may include v, pre-release, and build suffixes.

    Kora.versioncheck.check(
        'https://raw.githubusercontent.com/KoraFiveM/server-checker/main/fxmanifest.lua',
        'https://raw.githubusercontent.com/KoraFiveM/server-checker/main/PATCHNOTES.md'
    )

The request is asynchronous. When the installed version is older than the remote one, the server console prints the installed and current versions followed by a copyable GitHub patch-notes page URL. For matching versions, or when the installed version is newer, it prints nothing. The function returns true when it starts the request, or false if it cannot identify the calling resource or read its manifest version.
