# Version check module

Compares the version in the calling resource's fxmanifest.lua with a remote raw GitHub version file. The first URL returns a version such as 0.1.2; the local version comes from the invoking resource's manifest. If versions differ, it prints a link to the patch-notes file's GitHub page instead of printing the patch-note details.

## API

### Kora.versioncheck.check(remoteVersionUrl, patchNotesUrl) -- server

Call this from the resource's server-side code. Both URLs must be publicly readable raw file URLs. The first must contain a plain version such as 0.1.2; the caller's fxmanifest.lua must declare a version value. Version values may include v, pre-release, and build suffixes.

    Kora.versioncheck.check(
        'https://raw.githubusercontent.com/KoraFiveM/server-checker/main/version.txt',
        'https://raw.githubusercontent.com/KoraFiveM/server-checker/main/PATCHNOTES.md'
    )

The request is asynchronous. When the installed and remote versions differ, the server console prints the installed and current versions followed by a copyable GitHub patch-notes page URL. For matching versions, it prints nothing. The function returns true when it starts the request, or false if it cannot identify the calling resource or read its manifest version.
