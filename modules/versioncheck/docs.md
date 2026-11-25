# Version check module

Compares the version in the calling resource's `fxmanifest.lua` with a remote raw GitHub version file. The first URL returns just a version such as `0.1.2`; the local version is read from the invoking resource's `fxmanifest.lua`. If the versions differ, it fetches a Markdown patch-notes file and prints details for versions newer than the installed version, up to the remote version.

## API

### `Kora.versioncheck.check(remoteVersionUrl, patchNotesUrl)` -- server

Call this from the resource's server-side code. Both URLs must be publicly readable raw file URLs. The first must contain a plain version such as `0.1.2`; the caller's `fxmanifest.lua` must declare a `version` value. Version values and patch-note headings must use `major.minor.patch` numbers; optional `v`, pre-release, and build suffixes are accepted. Keep patch-note sections in oldest-to-newest order.

Patch-note versions use top-level bullets. Detail lines are indented beneath their version:

```markdown
- 0.1.1
  - added extra security modules
  - refactor of creator module

- 0.1.2
  - did things
```

```lua
Kora.versioncheck.check(
    'https://raw.githubusercontent.com/KoraFiveM/server-checker/main/version.txt',
    'https://raw.githubusercontent.com/KoraFiveM/server-checker/main/PATCHNOTES.md'
)
```

The request is asynchronous. When the installed and remote versions differ, the server console prints an out-of-date line followed by patch-note details newer than the installed version. For an installed version of `0.1.1` and remote version `0.1.2`, the output is:

```text
server-checker is out of date: your version 0.1.1 | current version 0.1.2
did things
```

The function returns `true` when it starts the request, or `false` if it cannot identify the calling resource or read its manifest version. Equal versions produce no output.
