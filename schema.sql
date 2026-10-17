-- TabMonitor Database Schema
-- Compatible with MySQL 5.7+ / 8.x and MariaDB 10.x+ on Webglobe shared hosting.
-- All tables use the prefix 'tab_'.

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- -------------------------------------------------------------
-- 1. Settings Table
-- Stores configurable application settings (e.g., low battery threshold).
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `tab_settings` (
    `setting_key` VARCHAR(50) NOT NULL,
    `setting_value` VARCHAR(255) NOT NULL,
    `description` VARCHAR(255) DEFAULT NULL,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`setting_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Default settings seed
INSERT INTO `tab_settings` (`setting_key`, `setting_value`, `description`)
VALUES
    ('low_battery_threshold', '20', 'Threshold percentage below which a device is flagged as low battery'),
    ('report_interval_minutes', '15', 'Interval in minutes between tablet battery reports (min 5, default 15)'),
    ('force_sync_requested_at', '0', 'Timestamp of last teacher force sync command broadcast to tablet fleet')
ON DUPLICATE KEY UPDATE `description` = VALUES(`description`);

-- -------------------------------------------------------------
-- 2. Pre-registered Devices Table
-- Tablets must be pre-registered here to submit reports or connect.
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `tab_devices` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `device_id` VARCHAR(64) NOT NULL UNIQUE,
    `name` VARCHAR(100) NOT NULL,
    `assigned_room` VARCHAR(100) DEFAULT NULL,
    `is_active` TINYINT(1) NOT NULL DEFAULT 1,
    `last_battery_level` SMALLINT DEFAULT NULL,
    `last_is_charging` TINYINT(1) DEFAULT NULL,
    `last_reported_at` DATETIME DEFAULT NULL,
    `last_ip` VARCHAR(45) DEFAULT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX `idx_tab_devices_active` (`is_active`),
    INDEX `idx_tab_devices_reported` (`last_reported_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Initial seed of pre-registered tablets
INSERT INTO `tab_devices` (`device_id`, `name`, `assigned_room`, `is_active`)
VALUES
    ('TAB-001', 'Tablet 01', 'Classroom 101', 1),
    ('TAB-002', 'Tablet 02', 'Classroom 101', 1),
    ('TAB-003', 'Tablet 03', 'Classroom 102', 1),
    ('TAB-004', 'Tablet 04', 'Classroom 102', 1),
    ('TAB-005', 'Tablet 05', 'IT Lab', 1)
ON DUPLICATE KEY UPDATE `name` = VALUES(`name`);

-- -------------------------------------------------------------
-- 3. Battery Reports History Table
-- Historical log of battery reports received from registered tablets.
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `tab_battery_reports` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `device_id` VARCHAR(64) NOT NULL,
    `battery_level` SMALLINT NOT NULL,
    `is_charging` TINYINT(1) NOT NULL DEFAULT 0,
    `reported_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `ip_address` VARCHAR(45) DEFAULT NULL,
    INDEX `idx_tab_reports_device_time` (`device_id`, `reported_at`),
    CONSTRAINT `fk_tab_reports_device` FOREIGN KEY (`device_id`)
        REFERENCES `tab_devices` (`device_id`)
        ON DELETE CASCADE
        ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -------------------------------------------------------------
-- 4. Teachers Table
-- Stores authenticated teachers for web dashboard access.
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `tab_teachers` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `username` VARCHAR(50) NOT NULL UNIQUE,
    `password_hash` VARCHAR(255) NOT NULL,
    `name` VARCHAR(100) NOT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Default teacher account (username: teacher, password: teacher123)
INSERT INTO `tab_teachers` (`username`, `password_hash`, `name`)
VALUES ('teacher', '$2y$12$3xqhX31UyQYKaBlw293g0usSAntTYxr5l3b/SfNKJNen52F7t7aV2', 'Primary Teacher')
ON DUPLICATE KEY UPDATE `name` = VALUES(`name`);

SET FOREIGN_KEY_CHECKS = 1;
