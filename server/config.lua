-- Server-only kora_lib configuration. Discord settings govern the bot-backed
-- authorization cache and must not be included in the client resource bundle.

Config.discord = {
    roleSyncInterval = 300000, -- ms; refresh the guild role catalog and every online player's roles (5 minutes)
    cacheMaxAge = 600000,      -- ms; hasRole/hasRoles fail closed once a member snapshot is older than this
    databaseTimeout = 60000,   -- ms to wait for optional kora_sql before continuing with memory-only caching
}
