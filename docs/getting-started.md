---
title: Installation
permalink: /getting-started/
---

# Installation

qblib is a FiveM resource. It requires `qbtheme`, which owns the shared palette and must start first.

## Install the resources

Place both resources in your server's resources directory, then ensure them in order:

```cfg
ensure qbtheme
ensure qblib
```

qblib's manifest also declares `qbtheme` as a dependency, so FiveM will reject an invalid start order instead of leaving the interface partially configured.

## Add qblib to a resource

Declare the dependency and load the proxy from the consuming resource's `fxmanifest.lua`:

```lua
fx_version 'cerulean'
game 'gta5'

dependency 'qblib'
shared_script '@qblib/init.lua'

client_script 'client.lua'
server_script 'server.lua'
```

Loading the proxy as a shared script makes `QB` available to the consumer's shared, client, and server scripts. Individual functions are still limited to the realms stated on their reference pages.

## Verify the installation

Add a temporary client command to a consumer resource:

```lua
RegisterCommand('qblib_check', function()
    QB.notify.send({
        title = 'qblib is ready',
        message = ('Player %s is connected.'):format(QB.cache.serverId()),
        type = 'success',
    })
end, false)
```

Restart the consumer and run `/qblib_check`. A notification with your server ID confirms that the proxy, client exports, cache, theme, and NUI are available.

## Editor types

The shipped `types.lua` is annotation-only. qblib does not execute it at runtime; `init.lua` points Lua language servers to its declarations. For the best completion and diagnostics, use a Lua language server configured for the CfxLua runtime and make sure the installed resource files are part of its workspace.

## Updating

Update `qbtheme` and `qblib` together when a release notes a shared interface or token change. Keep server-specific configuration in `config.local.lua`; qblib deliberately leaves that file untracked so updates do not overwrite local values. Review the [configuration reference]({{ site.baseurl }}/reference/config/) before moving settings out of authored resource files.

Next: [Using the API]({{ site.baseurl }}/using-the-api/).
