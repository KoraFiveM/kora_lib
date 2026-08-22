fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'qblib'
author 'Jamie'
version '1.0.0'
description 'Lightweight Lua library exposing a shared QB namespace over FiveM exports'

-- Consumers pull the QB proxy in with: shared_script '@qblib/init.lua'
-- It must be listed here so the client can fetch it.
files {
    'init.lua',
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
    'modules/**/shared.lua'
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
client_scripts {
    'local/resources/client.lua',
    'local/callback/client.lua',
    'local/events/client.lua',
    'modules/**/client.lua',
    'build/finalise.lua'
}

server_scripts {
    'local/resources/server.lua',
    'local/callback/server.lua',
    'local/events/server.lua',
    'modules/**/server.lua',
    'build/finalise.lua'
}
