<?php
declare(strict_types=1);

/**
 * TabMonitor Database Connection & Helpers (Phase 1 & Phase 2)
 *
 * Provides a secure, shared PDO connection using prepared statements
 * without leaking database credentials in exception messages.
 * Supports configurable table prefix ('tab_' by default).
 */

/**
 * Returns the PDO database connection singleton.
 *
 * @param array|null $config Optional config array (loads config.php if not passed)
 * @return PDO
 * @throws RuntimeException If connection fails
 */
function get_db(?array $config = null): PDO
{
    static $pdo = null;

    if ($pdo instanceof PDO) {
        return $pdo;
    }

    if ($config === null) {
        $configPath = __DIR__ . '/config.php';
        if (!file_exists($configPath)) {
            throw new RuntimeException('Configuration file config.php not found.');
        }
        $config = require $configPath;
    }

    $dbConfig = $config['db'] ?? [];
    $host     = (string)($dbConfig['host'] ?? '127.0.0.1');
    $port     = (int)($dbConfig['port'] ?? 3306);
    $socket   = !empty($dbConfig['unix_socket']) ? (string)$dbConfig['unix_socket'] : null;
    $dbName   = (string)($dbConfig['name'] ?? 'tabmonitor');
    $user     = (string)($dbConfig['user'] ?? 'tabmonitor_user');
    $pass     = (string)($dbConfig['pass'] ?? '');
    $charset  = (string)($dbConfig['charset'] ?? 'utf8mb4');
    $debug    = (bool)($config['app']['debug'] ?? false);

    if ($socket !== null) {
        $dsn = sprintf('mysql:unix_socket=%s;dbname=%s;charset=%s', $socket, $dbName, $charset);
    } else {
        $dsn = sprintf('mysql:host=%s;port=%d;dbname=%s;charset=%s', $host, $port, $dbName, $charset);
    }

    $options = [
        PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES   => false, // Always use native prepared statements
        PDO::ATTR_TIMEOUT            => 5,
    ];

    if (defined('Pdo\Mysql::ATTR_INIT_COMMAND')) {
        $options[\Pdo\Mysql::ATTR_INIT_COMMAND] = "SET NAMES {$charset} COLLATE utf8mb4_unicode_ci";
    } elseif (defined('PDO::MYSQL_ATTR_INIT_COMMAND')) {
        $options[PDO::MYSQL_ATTR_INIT_COMMAND] = "SET NAMES {$charset} COLLATE utf8mb4_unicode_ci";
    }

    try {
        $pdo = new PDO($dsn, $user, $pass, $options);
        return $pdo;
    } catch (PDOException $e) {
        error_log('Database connection error: ' . $e->getMessage());

        if ($debug) {
            throw new RuntimeException('Database connection failed: ' . $e->getMessage(), (int)$e->getCode(), $e);
        }

        // Never leak credentials or internal host names in production
        throw new RuntimeException('Database connection failed. Please check server configuration.');
    }
}

/**
 * Returns the configured database table prefix (defaults to 'tab_').
 *
 * @param array|null $config
 * @return string
 */
function get_table_prefix(?array $config = null): string
{
    static $prefix = null;
    if ($prefix !== null) {
        return $prefix;
    }

    if ($config === null) {
        $configPath = __DIR__ . '/config.php';
        $config = file_exists($configPath) ? (require $configPath) : [];
    }

    $prefix = (string)($config['db']['prefix'] ?? 'tab_');
    return $prefix;
}

/**
 * Retrieves a setting from the settings table with fallback to default.
 *
 * @param PDO $pdo
 * @param string $key
 * @param mixed $default
 * @return mixed
 */
function get_db_setting(PDO $pdo, string $key, mixed $default = null): mixed
{
    $table = get_table_prefix() . 'settings';
    try {
        $stmt = $pdo->prepare("SELECT setting_value FROM `{$table}` WHERE setting_key = :key LIMIT 1");
        $stmt->execute([':key' => $key]);
        $row = $stmt->fetch();

        if ($row !== false && isset($row['setting_value'])) {
            return $row['setting_value'];
        }
    } catch (PDOException $e) {
        error_log('Failed to fetch setting ' . $key . ': ' . $e->getMessage());
    }

    return $default;
}

/**
 * Stores or updates a setting in the settings table.
 *
 * @param PDO $pdo
 * @param string $key
 * @param string $value
 * @param string|null $description
 * @return void
 */
function set_db_setting(PDO $pdo, string $key, string $value, ?string $description = null): void
{
    $table = get_table_prefix() . 'settings';
    $stmt = $pdo->prepare(
        "INSERT INTO `{$table}` (setting_key, setting_value, description)
         VALUES (:key, :val, :desc)
         ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value), updated_at = NOW()"
    );

    $stmt->execute([
        ':key'  => $key,
        ':val'  => $value,
        ':desc' => $description,
    ]);
}

/**
 * Ensures the teachers table exists and contains at least the default teacher.
 *
 * @param PDO $pdo
 * @return void
 */
function ensure_teachers_table(PDO $pdo): void
{
    $table = get_table_prefix() . 'teachers';
    try {
        $pdo->exec(
            "CREATE TABLE IF NOT EXISTS `{$table}` (
                `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                `username` VARCHAR(50) NOT NULL UNIQUE,
                `password_hash` VARCHAR(255) NOT NULL,
                `name` VARCHAR(100) NOT NULL,
                `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;"
        );

        $count = (int)$pdo->query("SELECT COUNT(*) FROM `{$table}`")->fetchColumn();
        if ($count === 0) {
            $stmt = $pdo->prepare("INSERT INTO `{$table}` (`username`, `password_hash`, `name`) VALUES (:u, :p, :n)");
            $stmt->execute([
                ':u' => 'teacher',
                ':p' => '$2y$12$3xqhX31UyQYKaBlw293g0usSAntTYxr5l3b/SfNKJNen52F7t7aV2',
                ':n' => 'Primary Teacher',
            ]);
        }
    } catch (PDOException $e) {
        error_log('ensure_teachers_table error: ' . $e->getMessage());
    }
}

/**
 * Starts a secure PHP session for web dashboard.
 *
 * @param array|null $config
 * @return void
 */
function start_secure_session(?array $config = null): void
{
    if (session_status() === PHP_SESSION_ACTIVE) {
        return;
    }

    if ($config === null) {
        $configPath = __DIR__ . '/config.php';
        $config = file_exists($configPath) ? (require $configPath) : [];
    }

    $isHttps = (!empty($_SERVER['HTTPS']) && strtolower($_SERVER['HTTPS']) !== 'off')
        || (isset($_SERVER['SERVER_PORT']) && (int)$_SERVER['SERVER_PORT'] === 443)
        || (!empty($_SERVER['HTTP_X_FORWARDED_PROTO']) && strtolower($_SERVER['HTTP_X_FORWARDED_PROTO']) === 'https')
        || (!empty($config['security']['enforce_https']));

    session_set_cookie_params([
        'lifetime' => 0,
        'path'     => '/',
        'domain'   => '',
        'secure'   => $isHttps,
        'httponly' => true,
        'samesite' => 'Lax',
    ]);

    session_name('TABMONITOR_SESS');
    session_start();

    // Inactivity timeout: 2 hours (7200s)
    $maxLifetime = 7200;
    if (!empty($_SESSION['last_activity']) && (time() - (int)$_SESSION['last_activity'] > $maxLifetime)) {
        session_unset();
        session_destroy();
        session_start();
        $_SESSION['session_expired'] = true;
    }
    $_SESSION['last_activity'] = time();
}

/**
 * Checks if a teacher is authenticated.
 *
 * @return bool
 */
function is_teacher_authenticated(): bool
{
    return !empty($_SESSION['teacher_logged_in']) && $_SESSION['teacher_logged_in'] === true;
}

/**
 * Enforces teacher authorization; redirects to login.php if not authenticated.
 *
 * @return void
 */
function require_teacher_auth(): void
{
    start_secure_session();

    if (!is_teacher_authenticated()) {
        $target = $_SERVER['REQUEST_URI'] ?? 'index.php';
        $redirect = urlencode($target);
        header("Location: login.php?redirect={$redirect}");
        exit;
    }
}

/**
 * Retrieves or initializes the CSRF token for the active session.
 *
 * @return string
 */
function get_csrf_token(): string
{
    start_secure_session();

    if (empty($_SESSION['csrf_token'])) {
        $_SESSION['csrf_token'] = bin2hex(random_bytes(32));
    }

    return (string)$_SESSION['csrf_token'];
}

/**
 * Validates a submitted CSRF token using timing-safe comparison.
 *
 * @param string|null $token
 * @return bool
 */
function validate_csrf_token(?string $token): bool
{
    start_secure_session();

    if (empty($token) || empty($_SESSION['csrf_token'])) {
        return false;
    }

    return hash_equals((string)$_SESSION['csrf_token'], (string)$token);
}

/**
 * Formats a datetime string into a human-readable relative time string.
 *
 * @param string|null $datetime
 * @return string
 */
function format_relative_time(?string $datetime): string
{
    if (empty($datetime)) {
        return 'Never';
    }

    $timestamp = strtotime($datetime);
    if ($timestamp === false) {
        return 'Unknown';
    }

    $diff = time() - $timestamp;

    if ($diff < 0) {
        return 'Just now';
    }
    if ($diff < 60) {
        return $diff . 's ago';
    }
    if ($diff < 3600) {
        $mins = (int)floor($diff / 60);
        return $mins . ' min' . ($mins > 1 ? 's' : '') . ' ago';
    }
    if ($diff < 86400) {
        $hours = (int)floor($diff / 3600);
        return $hours . ' hr' . ($hours > 1 ? 's' : '') . ' ago';
    }

    $days = (int)floor($diff / 86400);
    return $days . ' day' . ($days > 1 ? 's' : '') . ' ago';
}
