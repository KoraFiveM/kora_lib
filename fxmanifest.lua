fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'kora_lib'
-- Keep the legacy resource name resolvable for exports['qblib'] callers.
provide 'qblib'
author 'Jamie'
version '1.0.0'
description 'Lightweight Lua library exposing a shared QB namespace over FiveM exports'

dependency 'kora_theme'

-- qb-menu, qb-input, qb-radialmenu and qb-minigames are being deprecated in
-- favour of QB.nui.openMenu/openContextMenu/openRadialMenu/openInputDialog
-- and QB.minigames.play -- `provide` only satisfies another resource's
-- `dependency '<name>'` check; what actually makes
-- exports['qb-menu']:openMenu(...)/exports['qb-input']:ShowInput(...)/
-- exports['qb-radialmenu']:AddOption(...)/exports['qb-minigames']:Hacking(...)
-- (etc.) reach compat/client/qb-menu.lua/qb-input.lua/qb-radialmenu.lua/
-- qb-minigames.lua is the __cfx_export_ identity bridge those files register
-- through QB.compat.provideExport (see their own header comments).
provide 'qb-menu'
provide 'qb-input'
provide 'progressbar'
provide 'qb-radialmenu'
provide 'qb-minigames'
-- kora_lib's screenshot module implements screenshot-basic's public exports so
-- existing resources can migrate without a second, permanently-rendering NUI
-- resource. The legacy export identities are registered by its late compat bridge.
provide 'screenshot-basic'

-- Consumers pull the QB proxy in with: shared_script '@kora_lib/init.lua'
-- It must be listed here so the client can fetch it.
files {
    'init.lua',
    -- QB.require executes in each consumer's Lua environment rather than as a
    -- kora_lib export, so init.lua loads this small factory on demand.
    'modules/require/loader.lua',
    -- Like QB.require, QB.config executes in each consuming resource so it
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
    'modules/discord/sql/*.sql',
    'locales/*.json',
    'web/build/index.html',
    -- A bare trailing '**' does NOT match files in FiveM's resource globber --
    -- it needs the '/*' (compare citizen's own system_resources/monitor, which
    -- ships 'nui/**/*'). With 'web/build/assets/**' the hashed JS/CSS bundles
    -- were silently never served: index.html loaded (it's listed explicitly),
    -- but its <script> 404'd, so React never mounted, nothing ever rendered,
    -- and every QB.nui.request sat until it timed out.
    'web/build/assets/**/*'
}

-- web/build is committed (see AGENTS.md "UI (web/) layout") -- FiveM serves it
-- statically, there's no build step at resource-start time.
ui_page 'web/build/index.html'

-- Load order is significant:
--   1. build/initiate.lua  creates the empty QB table
--   2. local/** + modules/**  populate QB.<module>.<function>
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

-- local/resources must load before every other local/ module: callback and
-- events (and any future local module built the same way) create a
-- QB.resources.registry()/serverRegistry() at their own load time, which
-- requires that function to already exist. A `local/**/client.lua` glob
-- expands in alphabetical folder order, which happens to put "resources"
-- AFTER "callback"/"events" -- so local/ can't be a single glob here. Listed
-- explicitly (not a `local/resources/client.lua` entry ALONGSIDE a
-- `local/**/client.lua` glob -- that would match and load the same file
-- twice). Add new local/ modules to this list explicitly, after resources.
-- compat/client/* load after 'modules/**/client.lua' (they call QB.nui.*/
-- QB.minigames.* directly) and before finalise, same reasoning
-- kora_core/fxmanifest.lua gives for its own compat/* placement: each compat
-- function calls those modules DIRECTLY rather than through
-- exports.kora_lib:..., so GetInvokingResource() inside it still resolves to
-- the real external caller (qb-menu/qb-input/qb-radialmenu/qb-minigames
-- consumer), not to kora_lib itself.
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
