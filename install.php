<?php
declare(strict_types=1);

/**
 * TabMonitor - Web Installer (install.php)
 *
 * Web setup wizard for Webglobe shared hosting:
 * 1. Collects MySQL database credentials and creates all tables.
 * 2. Enforces the 'tab_' table prefix on all created tables:
 *    - tab_settings
 *    - tab_devices
 *    - tab_battery_reports
 *    - tab_teachers
 * 3. Seeds initial data and default teacher account.
 * 4. Automatically writes the verified credentials into config.php.
 */

error_reporting(E_ALL);
ini_set('display_errors', '1');

$configPath = __DIR__ . '/config.php';
$existingConfig = file_exists($configPath) ? (require $configPath) : [];

$isInstalled = false;
$existingTables = [];

// Check if already installed
if (!empty($existingConfig['db']['name']) && !empty($existingConfig['db']['user']) && ($existingConfig['db']['pass'] ?? '') !== 'change_this_password') {
    try {
        $prefix = (string)($existingConfig['db']['prefix'] ?? 'tab_');
        $dsn = !empty($existingConfig['db']['unix_socket'])
            ? sprintf('mysql:unix_socket=%s;dbname=%s;charset=utf8mb4', $existingConfig['db']['unix_socket'], $existingConfig['db']['name'])
            : sprintf('mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4', $existingConfig['db']['host'], $existingConfig['db']['port'] ?? 3306, $existingConfig['db']['name']);

        $testPdo = new PDO($dsn, (string)$existingConfig['db']['user'], (string)$existingConfig['db']['pass'], [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_TIMEOUT => 2,
        ]);

        $tablesStmt = $testPdo->query("SHOW TABLES LIKE '{$prefix}%'");
        $existingTables = $tablesStmt->fetchAll(PDO::FETCH_COLUMN);
        if (count($existingTables) >= 3) {
            $isInstalled = true;
        }
    } catch (Throwable $e) {
        // Not installed or credentials changed
        $isInstalled = false;
    }
}

$errorMessage = null;
$successData  = null;

// Handle Installation Form Submission
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $dbHost     = trim((string)($_POST['db_host'] ?? 'localhost'));
    $dbPort     = (int)($_POST['db_port'] ?? 3306);
    $dbSocket   = trim((string)($_POST['db_socket'] ?? ''));
    $dbName     = trim((string)($_POST['db_name'] ?? ''));
    $dbUser     = trim((string)($_POST['db_user'] ?? ''));
    $dbPass     = (string)($_POST['db_pass'] ?? '');
    
    // Enforce 'tab_' prefix requirement
    $tablePrefix = trim((string)($_POST['table_prefix'] ?? 'tab_'));
    if ($tablePrefix === '') {
        $tablePrefix = 'tab_';
    }
    $tablePrefix = preg_replace('/[^a-zA-Z0-9_]/', '', $tablePrefix);
    if (!str_ends_with($tablePrefix, '_')) {
        $tablePrefix .= '_';
    }

    $teacherUsername = trim((string)($_POST['teacher_username'] ?? 'teacher'));
    $teacherPassword = (string)($_POST['teacher_password'] ?? 'teacher123');
    $tabletApiKey    = trim((string)($_POST['tablet_api_key'] ?? ''));
    $teacherApiKey   = trim((string)($_POST['teacher_api_key'] ?? ''));

    if ($tabletApiKey === '') {
        $tabletApiKey = bin2hex(random_bytes(16));
    }
    if ($teacherApiKey === '') {
        $teacherApiKey = bin2hex(random_bytes(16));
    }

    if ($dbName === '' || $dbUser === '') {
        $errorMessage = 'Database Name and Database User are required.';
    } elseif ($teacherUsername === '' || mb_strlen($teacherPassword) < 6) {
        $errorMessage = 'Teacher username is required and password must be at least 6 characters.';
    } else {
        // 1. Attempt Database Connection
        try {
            $options = [
                PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                PDO::ATTR_TIMEOUT            => 5,
            ];

            $socketParam = ($dbSocket !== '') ? $dbSocket : null;

            if ($socketParam !== null) {
                $dsn = "mysql:unix_socket={$socketParam};dbname={$dbName};charset=utf8mb4";
            } else {
                $dsn = "mysql:host={$dbHost};port={$dbPort};dbname={$dbName};charset=utf8mb4";
            }

            try {
                $pdo = new PDO($dsn, $dbUser, $dbPass, $options);
            } catch (PDOException $pdoEx) {
                // If database doesn't exist yet, attempt connecting without dbname and create it
                if ($pdoEx->getCode() == 1049 || str_contains($pdoEx->getMessage(), 'Unknown database')) {
                    $serverDsn = ($socketParam !== null)
                        ? "mysql:unix_socket={$socketParam};charset=utf8mb4"
                        : "mysql:host={$dbHost};port={$dbPort};charset=utf8mb4";
                    
                    $serverPdo = new PDO($serverDsn, $dbUser, $dbPass, $options);
                    $serverPdo->exec("CREATE DATABASE IF NOT EXISTS `{$dbName}` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci");
                    $pdo = new PDO($dsn, $dbUser, $dbPass, $options);
                } else {
                    throw $pdoEx;
                }
            }

            // 2. Create tables with 'tab_' prefix
            $pdo->exec("SET NAMES utf8mb4");
            $pdo->exec("SET FOREIGN_KEY_CHECKS = 0");

            // Table 1: Settings
            $pdo->exec("CREATE TABLE IF NOT EXISTS `{$tablePrefix}settings` (
                `setting_key` VARCHAR(50) NOT NULL,
                `setting_value` VARCHAR(255) NOT NULL,
                `description` VARCHAR(255) DEFAULT NULL,
                `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (`setting_key`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

            // Seed default settings
            $stmt = $pdo->prepare("INSERT INTO `{$tablePrefix}settings` (`setting_key`, `setting_value`, `description`)
                VALUES ('low_battery_threshold', '20', 'Threshold percentage below which a device is flagged as low battery')
                ON DUPLICATE KEY UPDATE `description` = VALUES(`description`)");
            $stmt->execute();

            // Table 2: Pre-registered Devices
            $pdo->exec("CREATE TABLE IF NOT EXISTS `{$tablePrefix}devices` (
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
                INDEX `idx_devices_active` (`is_active`),
                INDEX `idx_devices_reported` (`last_reported_at`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

            // Seed initial pre-registered tablets
            $seedDevices = [
                ['TAB-001', 'Tablet 01', 'Classroom 101'],
                ['TAB-002', 'Tablet 02', 'Classroom 101'],
                ['TAB-003', 'Tablet 03', 'Classroom 102'],
                ['TAB-004', 'Tablet 04', 'Classroom 102'],
                ['TAB-005', 'Tablet 05', 'IT Lab'],
            ];

            $devInsert = $pdo->prepare("INSERT INTO `{$tablePrefix}devices` (`device_id`, `name`, `assigned_room`, `is_active`)
                VALUES (?, ?, ?, 1)
                ON DUPLICATE KEY UPDATE `name` = VALUES(`name`)");
            foreach ($seedDevices as $dev) {
                $devInsert->execute($dev);
            }

            // Table 3: Battery Reports History
            $pdo->exec("CREATE TABLE IF NOT EXISTS `{$tablePrefix}battery_reports` (
                `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                `device_id` VARCHAR(64) NOT NULL,
                `battery_level` SMALLINT NOT NULL,
                `is_charging` TINYINT(1) NOT NULL DEFAULT 0,
                `reported_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `ip_address` VARCHAR(45) DEFAULT NULL,
                INDEX `idx_reports_device_time` (`device_id`, `reported_at`),
                CONSTRAINT `fk_{$tablePrefix}reports_device` FOREIGN KEY (`device_id`)
                    REFERENCES `{$tablePrefix}devices` (`device_id`)
                    ON DELETE CASCADE
                    ON UPDATE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

            // Table 4: Teachers
            $pdo->exec("CREATE TABLE IF NOT EXISTS `{$tablePrefix}teachers` (
                `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                `username` VARCHAR(50) NOT NULL UNIQUE,
                `password_hash` VARCHAR(255) NOT NULL,
                `name` VARCHAR(100) NOT NULL,
                `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

            // Seed teacher account
            $teacherHash = password_hash($teacherPassword, PASSWORD_DEFAULT);
            $teacherStmt = $pdo->prepare("INSERT INTO `{$tablePrefix}teachers` (`username`, `password_hash`, `name`)
                VALUES (:u, :p, 'Primary Teacher')
                ON DUPLICATE KEY UPDATE `password_hash` = VALUES(`password_hash`)");
            $teacherStmt->execute([':u' => $teacherUsername, ':p' => $teacherHash]);

            $pdo->exec("SET FOREIGN_KEY_CHECKS = 1");

            // 3. Write Configuration File (config.php)
            $socketExport = $socketParam !== null ? var_export($socketParam, true) : 'null';
            $newConfigContent = "<?php\ndeclare(strict_types=1);\n\n"
                . "/**\n * TabMonitor Configuration\n * Auto-generated by install.php\n */\n\n"
                . "return [\n"
                . "    'db' => [\n"
                . "        'host'        => " . var_export($dbHost, true) . ",\n"
                . "        'port'        => " . $dbPort . ",\n"
                . "        'unix_socket' => " . $socketExport . ",\n"
                . "        'name'        => " . var_export($dbName, true) . ",\n"
                . "        'user'        => " . var_export($dbUser, true) . ",\n"
                . "        'pass'        => " . var_export($dbPass, true) . ",\n"
                . "        'prefix'      => " . var_export($tablePrefix, true) . ",\n"
                . "        'charset'     => 'utf8mb4',\n"
                . "    ],\n"
                . "    'security' => [\n"
                . "        'tablet_api_key'  => " . var_export($tabletApiKey, true) . ",\n"
                . "        'teacher_api_key' => " . var_export($teacherApiKey, true) . ",\n"
                . "        'enforce_https'   => " . (!empty($_POST['enforce_https']) ? 'true' : 'false') . ",\n"
                . "    ],\n"
                . "    'app' => [\n"
                . "        'default_low_battery_threshold' => 20,\n"
                . "        'offline_threshold_minutes'     => 30,\n"
                . "        'timezone'                      => 'Europe/Bratislava',\n"
                . "        'debug'                         => false,\n"
                . "    ],\n"
                . "];\n";

            if (file_put_contents($configPath, $newConfigContent) === false) {
                throw new RuntimeException("Could not write to {$configPath}. Please check file permissions.");
            }

            $successData = [
                'db_name'          => $dbName,
                'prefix'           => $tablePrefix,
                'tables'           => [
                    "{$tablePrefix}settings",
                    "{$tablePrefix}devices",
                    "{$tablePrefix}battery_reports",
                    "{$tablePrefix}teachers",
                ],
                'teacher_username' => $teacherUsername,
                'tablet_api_key'   => $tabletApiKey,
                'teacher_api_key'  => $teacherApiKey,
            ];

        } catch (Throwable $e) {
            $errorMessage = 'Database Error: ' . $e->getMessage();
        }
    }
}

// Default form field values
$defaultHost    = $_POST['db_host'] ?? ($existingConfig['db']['host'] ?? 'localhost');
$defaultPort    = $_POST['db_port'] ?? ($existingConfig['db']['port'] ?? 3306);
$defaultSocket  = $_POST['db_socket'] ?? ($existingConfig['db']['unix_socket'] ?? '');
$defaultDbName  = $_POST['db_name'] ?? ($existingConfig['db']['name'] ?? 'tabmonitor');
$defaultUser    = $_POST['db_user'] ?? ($existingConfig['db']['user'] ?? 'tabmonitor_user');
$defaultPrefix  = $_POST['table_prefix'] ?? ($existingConfig['db']['prefix'] ?? 'tab_');
$defaultTabletKey  = $_POST['tablet_api_key'] ?? ($existingConfig['security']['tablet_api_key'] ?? bin2hex(random_bytes(16)));
$defaultTeacherKey = $_POST['teacher_api_key'] ?? ($existingConfig['security']['teacher_api_key'] ?? bin2hex(random_bytes(16)));
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>TabMonitor - Web Installer</title>
  <link rel="icon" type="image/png" href="favicon.png">
  <link rel="stylesheet" href="style.css">
</head>
<body class="login-body" style="padding: 2.5rem 1rem;">

  <div class="login-card" style="max-width: 620px;">
    <div class="login-header">
      <div class="brand" style="justify-content: center; font-size: 1.6rem;">
        <span class="brand-icon">📱</span> TabMonitor Installer <span class="version-badge">v2.1.0</span>
      </div>
      <p class="login-subtitle">Database configuration &amp; automatic table initialization</p>
    </div>

    <?php if ($successData !== null): ?>
      <!-- SUCCESS SCREEN -->
      <div class="alert alert-success" style="flex-direction: column; align-items: flex-start;">
        <div style="font-size: 1.15rem; font-weight: 700; margin-bottom: 0.5rem;">
          🎉 TabMonitor Installed Successfully!
        </div>
        <p style="margin-bottom: 0.5rem;">
          Database <strong><?= htmlspecialchars($successData['db_name'], ENT_QUOTES, 'UTF-8') ?></strong> is configured. All tables with prefix <strong><code><?= htmlspecialchars($successData['prefix'], ENT_QUOTES, 'UTF-8') ?></code></strong> were successfully created:
        </p>
        <ul style="margin-left: 1.5rem; margin-bottom: 0.75rem;">
          <?php foreach ($successData['tables'] as $tbl): ?>
            <li><code><?= htmlspecialchars($tbl, ENT_QUOTES, 'UTF-8') ?></code></li>
          <?php endforeach; ?>
        </ul>
      </div>

      <div class="settings-card" style="margin-bottom: 1.5rem;">
        <h3 style="font-size: 1rem; margin-bottom: 0.75rem;">📋 Your Access Credentials:</h3>
        <ul class="info-list">
          <li class="info-item">
            <span class="info-label">Teacher Web Login</span>
            <span class="info-val">Username: <strong><?= htmlspecialchars($successData['teacher_username'], ENT_QUOTES, 'UTF-8') ?></strong></span>
          </li>
          <li class="info-item">
            <span class="info-label">Tablet API Key</span>
            <span class="info-val"><code style="word-break: break-all;"><?= htmlspecialchars($successData['tablet_api_key'], ENT_QUOTES, 'UTF-8') ?></code></span>
          </li>
          <li class="info-item">
            <span class="info-label">Teacher API Key</span>
            <span class="info-val"><code style="word-break: break-all;"><?= htmlspecialchars($successData['teacher_api_key'], ENT_QUOTES, 'UTF-8') ?></code></span>
          </li>
        </ul>
      </div>

      <div class="alert alert-warning" style="font-size: 0.85rem;">
        ⚠️ <strong>Security Recommendation:</strong> For production security on Webglobe, delete or rename <code>install.php</code> now that installation is complete.
      </div>

      <a href="login.php" class="btn-primary" style="display: block; text-align: center; text-decoration: none; padding: 0.85rem;">
        Go to Teacher Login &rarr;
      </a>

    <?php else: ?>
      <!-- INSTALLATION FORM -->

      <?php if ($isInstalled): ?>
        <div class="alert alert-warning">
          <div>
            <strong>Already Installed:</strong> TabMonitor tables (prefix <code><?= htmlspecialchars($existingConfig['db']['prefix'] ?? 'tab_', ENT_QUOTES, 'UTF-8') ?></code>) were detected. Re-submitting will update credentials and refresh tables.
          </div>
        </div>
      <?php endif; ?>

      <?php if ($errorMessage): ?>
        <div class="alert alert-danger">
          <span>⚠️ <?= htmlspecialchars($errorMessage, ENT_QUOTES, 'UTF-8') ?></span>
        </div>
      <?php endif; ?>

      <form method="POST" action="install.php">
        <h2 style="font-size: 1.1rem; font-weight: 700; margin-bottom: 1rem; border-bottom: 2px solid var(--border-color); padding-bottom: 0.4rem;">
          1. MySQL Database Connection
        </h2>

        <div style="display: grid; grid-template-columns: 2fr 1fr; gap: 0.75rem;">
          <div class="form-group">
            <label class="form-label" for="db_host">Database Host</label>
            <input type="text" id="db_host" name="db_host" class="form-input" required value="<?= htmlspecialchars((string)$defaultHost, ENT_QUOTES, 'UTF-8') ?>" placeholder="localhost or 127.0.0.1">
          </div>
          <div class="form-group">
            <label class="form-label" for="db_port">Port</label>
            <input type="number" id="db_port" name="db_port" class="form-input" required value="<?= htmlspecialchars((string)$defaultPort, ENT_QUOTES, 'UTF-8') ?>">
          </div>
        </div>

        <div class="form-group">
          <label class="form-label" for="db_socket">Unix Socket <span style="font-weight: 400; color: var(--text-muted);">(Optional, leave empty for TCP)</span></label>
          <input type="text" id="db_socket" name="db_socket" class="form-input" value="<?= htmlspecialchars((string)$defaultSocket, ENT_QUOTES, 'UTF-8') ?>" placeholder="/tmp/mysql.sock">
        </div>

        <div class="form-group">
          <label class="form-label" for="db_name">Database Name</label>
          <input type="text" id="db_name" name="db_name" class="form-input" required value="<?= htmlspecialchars((string)$defaultDbName, ENT_QUOTES, 'UTF-8') ?>" placeholder="e.g. webglobe_tabmonitor">
        </div>

        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 0.75rem;">
          <div class="form-group">
            <label class="form-label" for="db_user">Database User</label>
            <input type="text" id="db_user" name="db_user" class="form-input" required value="<?= htmlspecialchars((string)$defaultUser, ENT_QUOTES, 'UTF-8') ?>" placeholder="e.g. db_user">
          </div>
          <div class="form-group">
            <label class="form-label" for="db_pass">Database Password</label>
            <input type="password" id="db_pass" name="db_pass" class="form-input" placeholder="••••••••">
          </div>
        </div>

        <div class="form-group">
          <label class="form-label" for="table_prefix">Table Prefix</label>
          <input type="text" id="table_prefix" name="table_prefix" class="form-input" required value="<?= htmlspecialchars((string)$defaultPrefix, ENT_QUOTES, 'UTF-8') ?>" style="font-family: var(--font-mono);">
          <small style="color: var(--text-muted); font-size: 0.8rem;">All TabMonitor tables will be prefixed with this string (e.g. <code>tab_devices</code>, <code>tab_settings</code>).</small>
        </div>

        <h2 style="font-size: 1.1rem; font-weight: 700; margin-top: 1.5rem; margin-bottom: 1rem; border-bottom: 2px solid var(--border-color); padding-bottom: 0.4rem;">
          2. Teacher Dashboard Administrator
        </h2>

        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 0.75rem;">
          <div class="form-group">
            <label class="form-label" for="teacher_username">Teacher Username</label>
            <input type="text" id="teacher_username" name="teacher_username" class="form-input" required value="teacher">
          </div>
          <div class="form-group">
            <label class="form-label" for="teacher_password">Password (min. 6 chars)</label>
            <input type="text" id="teacher_password" name="teacher_password" class="form-input" required value="teacher123">
          </div>
        </div>

        <h2 style="font-size: 1.1rem; font-weight: 700; margin-top: 1.5rem; margin-bottom: 1rem; border-bottom: 2px solid var(--border-color); padding-bottom: 0.4rem;">
          3. API Access Keys
        </h2>

        <div class="form-group">
          <label class="form-label" for="tablet_api_key">Shared Tablet API Key <span style="font-weight: 400; color: var(--text-muted);">(Used by student tablets)</span></label>
          <input type="text" id="tablet_api_key" name="tablet_api_key" class="form-input" required value="<?= htmlspecialchars((string)$defaultTabletKey, ENT_QUOTES, 'UTF-8') ?>" style="font-family: var(--font-mono); font-size: 0.85rem;">
        </div>

        <div class="form-group">
          <label class="form-label" for="teacher_api_key">Teacher API Key <span style="font-weight: 400; color: var(--text-muted);">(Used by teachers for API access)</span></label>
          <input type="text" id="teacher_api_key" name="teacher_api_key" class="form-input" required value="<?= htmlspecialchars((string)$defaultTeacherKey, ENT_QUOTES, 'UTF-8') ?>" style="font-family: var(--font-mono); font-size: 0.85rem;">
        </div>

        <div class="form-group">
          <label style="display: flex; align-items: center; gap: 0.5rem; font-size: 0.9rem; cursor: pointer;">
            <input type="checkbox" name="enforce_https" value="1">
            Enforce HTTPS in production (recommended on Webglobe with SSL enabled)
          </label>
        </div>

        <button type="submit" class="btn-primary" style="margin-top: 1rem; font-size: 1.05rem; padding: 0.85rem;">
          Connect &amp; Create Tables (tab_*)
        </button>
      </form>
    <?php endif; ?>
  </div>

</body>
</html>
