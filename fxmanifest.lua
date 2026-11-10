fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'kora_lib'
author 'Jamie'
version '1.1.7'
description 'Lightweight Lua library exposing a shared Kora namespace over FiveM exports'

dependency 'kora_theme'

-- `provide` only satisfies another resource's `dependency` check; the exports themselves are
-- bridged by the __cfx_export_ identity registration in compat/client/* via Kora.compat.provideExport.
provide 'qb-menu'
provide 'qb-input'
provide 'progressbar'
provide 'qb-radialmenu'
provide 'qb-minigames'
-- kora_lib's screenshot module implements screenshot-basic's public exports so
-- existing resources can migrate without a second, permanently-rendering NUI
-- resource. The legacy export identities are registered by its late compat bridge.
provide 'screenshot-basic'

-- Consumers pull the Kora proxy in with: shared_script '@kora_lib/init.lua'
-- It must be listed here so the client can fetch it.
files {
    'init.lua',
    -- Kora.require executes in each consumer's Lua environment rather than as a
    -- kora_lib export, so init.lua loads this small factory on demand.
    'modules/require/loader.lua',
    -- Like Kora.require, Kora.config executes in each consuming resource so it
    -- can safely own that resource's Config table and config.local.lua.
    'modules/config/consumer.lua',
    -- Loaded into each consumer so compatibility handlers belong to and stop
    -- with the resource that provides the alias.
    'compat/provider.lua',
    -- Stateless hot-path helpers execute in the consumer that imports
    -- init.lua. stream is client-only so model/asset natives belong to the
    -- calling script; init.lua selects only files valid for the current realm.
    'modules/loops/shared.lua',
    'modules/util/shared.lua',
    'modules/util/client.lua',
    'modules/stream/client.lua',
    'types.lua', -- annotation-only LuaLS API declarations; never loaded as a runtime script
    -- Lookup bundles are loaded on demand with LoadResourceFile; source JSON
    -- stays out of the runtime resource (source.json only records provenance).
    'modules/lookup/data/*.lua',
    'modules/lookup/data/source.json',
    'locales/*.json',
    'web/build/index.html',
    -- A bare trailing '**' does NOT match files in FiveM's resource globber; it needs '/*'
    -- (otherwise the hashed JS/CSS bundles are never served and the NUI never mounts).
    'web/build/assets/**/*'
}

-- web/build is committed (see AGENTS.md "UI (web/) layout") -- FiveM serves it
-- statically, there's no build step at resource-start time.
ui_page 'web/build/index.html'

-- Load order is significant:
--   1. build/initiate.lua  creates the empty Kora table
--   2. local/** + modules/**  populate Kora.<module>.<function>
--   3. build/finalise.lua  turns every entry into a `<module>_<function>` export
--
-- finalise must be the LAST file loaded in each environment, so it lives in
-- client_scripts/server_scripts rather than shared_scripts (shared always
-- loads before the environment-specific block).
shared_scripts {
    'config.lua',
    'build/initiate.lua',
    'local/**/shared.lua',
    'modules/**/shared.lua',
    -- Shared so compatibility providers can register aliases in either realm.
    'compat/shared.lua'
}

-- local/resources must load before every other local/ module: callback and events call
-- Kora.resources.registry()/serverRegistry() at load time. A `local/**/client.lua` glob would sort
-- "resources" after them alphabetically, so local/ is listed explicitly; add new local/ modules here, after resources.
-- compat/client/* load after modules/**/client.lua (they call Kora.nui.*/Kora.minigames.* directly) and before
-- finalise. Calling those modules directly, not via exports.kora_lib, keeps GetInvokingResource() pointing at
-- the real external caller.
client_scripts {
    '@kora_theme/client/bridge.lua',
    'local/resources/client.lua',
    'local/callback/client.lua',
    'local/events/client.lua',
    'modules/**/client.lua',
    -- The configuration editor needs the config consumer and AppShell, both
    -- supplied by the preceding module glob.
    'modules/config/editor_client.lua',
    -- Loaded after every module client so the built-in settings app can use
    -- both the blip registry and the shared AppShell without load-order races.
    'modules/blips/settings.lua',
    'compat/client/qb-menu.lua',
    'compat/client/qb-input.lua',
    'compat/client/progressbar.lua',
    'compat/client/qb-radialmenu.lua',
    'compat/client/qb-minigames.lua',
    'compat/client/screenshot-basic.lua',
    -- Optional FFT hooks: returns immediately unless fft_kora_hooks is true. Must
    -- precede finalise.lua so the exported Kora.nui.send carries its observer.
    'fft_hooks.lua',
    'build/finalise.lua'
}

server_scripts {
    'server/config.lua',
    'local/resources/server.lua',
    'local/callback/server.lua',
    'local/events/server.lua',
    'modules/**/server.lua',
    'modules/config/editor_server.lua',
    'build/finalise.lua'
}

-- kora_qa: Gherkin test scenarios (converted legacy tests), see [kora]/kora_qa/README.md
qa_feature 'tests/*.feature'
