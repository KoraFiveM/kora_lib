CREATE TABLE IF NOT EXISTS `qblib_discord_roles` (
  `guild_id`    VARCHAR(32)      NOT NULL,
  `role_id`     VARCHAR(32)      NOT NULL,
  `name`        VARCHAR(100)     NOT NULL,
  `color`       INT UNSIGNED     NOT NULL DEFAULT 0,
  `position`    SMALLINT         NOT NULL DEFAULT 0,
  `permissions` VARCHAR(32)      NOT NULL DEFAULT '0',
  `managed`     TINYINT(1)       NOT NULL DEFAULT 0,
  `mentionable` TINYINT(1)       NOT NULL DEFAULT 0,
  `updated_at`  TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`guild_id`,`role_id`),
  KEY `idx_qblib_discord_roles_name` (`guild_id`,`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `qblib_discord_members` (
  `guild_id`  VARCHAR(32)  NOT NULL,
  `user_id`   VARCHAR(32)  NOT NULL,
  `synced_at` BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (`guild_id`,`user_id`),
  KEY `idx_qblib_discord_members_synced` (`synced_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `qblib_discord_member_roles` (
  `guild_id` VARCHAR(32) NOT NULL,
  `user_id`  VARCHAR(32) NOT NULL,
  `role_id`  VARCHAR(32) NOT NULL,
  PRIMARY KEY (`guild_id`,`user_id`,`role_id`),
  KEY `idx_qblib_discord_member_roles_role` (`guild_id`,`role_id`),
  CONSTRAINT `fk_qblib_discord_member`
    FOREIGN KEY (`guild_id`,`user_id`) REFERENCES `qblib_discord_members` (`guild_id`,`user_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_qblib_discord_role`
    FOREIGN KEY (`guild_id`,`role_id`) REFERENCES `qblib_discord_roles` (`guild_id`,`role_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
