<?php
declare(strict_types=1);

/**
 * TabMonitor API - Phase 1
 *
 * Lightweight REST API for tablet battery monitoring in schools.
 * Built for Webglobe shared hosting (PHP 8.x + MySQL).
 *
 * Security:
 * - Prepared PDO statements for all SQL operations.
 * - Enforces HTTPS in production when configured.
 * - Distinct Tablet API Key (for reporting & test connection).
 * - Distinct Teacher API Key (for status viewing & settings).
 * - Shared tablet key NEVER grants teacher access or settings modifications.
 */

// Set execution constraints and error reporting
error_reporting(E_ALL);
ini_set('display_errors', '0');

// Load dependencies
$configPath = __DIR__ . '/config.php';
$dbPath     = __DIR__ . '/db.php';

if (!file_exists($configPath) || !file_exists($dbPath)) {
    http_response_code(500);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode([
        'status'  => 'error',
        'code'    => 500,
        'message' => 'Backend configuration or database files missing.',
    ]);
    exit;
}

$config = require $configPath;
require_once $dbPath;

// Set server timezone
if (!empty($config['app']['timezone'])) {
    date_default_timezone_set($config['app']['timezone']);
}

// -----------------------------------------------------------------------------
// Helper Functions
// -----------------------------------------------------------------------------

/**
 * Sends a structured JSON response and terminates script execution.
 *
 * @param int $statusCode HTTP status code
 * @param array $data Response payload
 * @return void
 */
function send_json_response(int $statusCode, array $data): void
{
    http_response_code($statusCode);
    header('Content-Type: application/json; charset=utf-8');
    header('X-Content-Type-Options: nosniff');
    header('X-Frame-Options: DENY');
    header('Referrer-Policy: no-referrer');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

    echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

/**
 * Extracts client IP address safely.
 *
 * @return string|null
 */
function get_client_ip(): ?string
{
    $candidates = [
        $_SERVER['HTTP_CF_CONNECTING_IP'] ?? null,
        $_SERVER['HTTP_X_FORWARDED_FOR'] ?? null,
        $_SERVER['REMOTE_ADDR'] ?? null,
    ];

    foreach ($candidates as $ip) {
        if (!empty($ip)) {
            // If comma-separated (proxies), pick the first valid IP
            $parts = explode(',', (string)$ip);
            foreach ($parts as $part) {
                $trimmed = trim($part);
                if (filter_var($trimmed, FILTER_VALIDATE_IP)) {
                    return $trimmed;
                }
            }
        }
    }

    return null;
}

/**
 * Retrieves the request authentication token from HTTP headers or query string.
 *
 * @param string $headerName
 * @param string|null $queryParam
 * @return string|null
 */
function get_auth_token(string $headerName, ?string $queryParam = null): ?string
{
    // 1. Check $_SERVER header (e.g. HTTP_X_API_KEY)
    $serverKey = 'HTTP_' . strtoupper(str_replace('-', '_', $headerName));
    if (!empty($_SERVER[$serverKey])) {
        return trim((string)$_SERVER[$serverKey]);
    }

    // 2. Check getallheaders() or apache_request_headers() if available
    if (function_exists('getallheaders')) {
        $headers = getallheaders();
        foreach ($headers as $k => $v) {
            if (strcasecmp($k, $headerName) === 0 && !empty($v)) {
                return trim((string)$v);
            }
        }
    }

    // 3. Check Authorization header for Bearer token
    $authHeader = $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? null;
    if (!empty($authHeader) && preg_match('/^Bearer\s+(.+)$/i', trim($authHeader), $matches)) {
        return trim($matches[1]);
    }

    // 4. Query param fallback
    if ($queryParam !== null && !empty($_GET[$queryParam])) {
        return trim((string)$_GET[$queryParam]);
    }

    return null;
}

// -----------------------------------------------------------------------------
// HTTPS Enforcement
// -----------------------------------------------------------------------------
if (!empty($config['security']['enforce_https'])) {
    $isHttps = (!empty($_SERVER['HTTPS']) && strtolower($_SERVER['HTTPS']) !== 'off')
        || (isset($_SERVER['SERVER_PORT']) && (int)$_SERVER['SERVER_PORT'] === 443)
        || (!empty($_SERVER['HTTP_X_FORWARDED_PROTO']) && strtolower($_SERVER['HTTP_X_FORWARDED_PROTO']) === 'https');

    if (!$isHttps) {
        send_json_response(403, [
            'status'  => 'error',
            'code'    => 403,
            'message' => 'Forbidden: HTTPS is required in production.',
        ]);
    }
}

// -----------------------------------------------------------------------------
// Authentication Resolution
// -----------------------------------------------------------------------------
define('AUTH_ROLE_NONE', 0);
define('AUTH_ROLE_TABLET', 1);
define('AUTH_ROLE_TEACHER', 2);

$expectedTabletKey  = (string)($config['security']['tablet_api_key'] ?? '');
$expectedTeacherKey = (string)($config['security']['teacher_api_key'] ?? '');

// Extract tokens from headers or parameters
$clientTeacherToken = get_auth_token('X-Teacher-Key', 'teacher_key');
$clientApiToken     = get_auth_token('X-API-Key', 'api_key');

$userRole = AUTH_ROLE_NONE;

// Check teacher authentication first
if (!empty($clientTeacherToken) && !empty($expectedTeacherKey) && hash_equals($expectedTeacherKey, $clientTeacherToken)) {
    $userRole = AUTH_ROLE_TEACHER;
} elseif (!empty($clientApiToken)) {
    // If client supplied token in X-API-Key or Bearer header:
    if (!empty($expectedTeacherKey) && hash_equals($expectedTeacherKey, $clientApiToken)) {
        $userRole = AUTH_ROLE_TEACHER;
    } elseif (!empty($expectedTabletKey) && hash_equals($expectedTabletKey, $clientApiToken)) {
        $userRole = AUTH_ROLE_TABLET;
    }
}

// -----------------------------------------------------------------------------
// Route & Request Method Resolution
// -----------------------------------------------------------------------------
$httpMethod = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');

// Determine action from query parameter, PATH_INFO, or JSON body
$action = null;

if (!empty($_GET['action'])) {
    $action = strtolower(trim((string)$_GET['action']));
} elseif (!empty($_GET['endpoint'])) {
    $action = strtolower(trim((string)$_GET['endpoint']));
} elseif (!empty($_SERVER['PATH_INFO'])) {
    $action = strtolower(trim($_SERVER['PATH_INFO'], '/'));
}

// Parse JSON body for POST/PUT requests
$requestData = [];
$rawInput = file_get_contents('php://input');
if (!empty($rawInput)) {
    $decoded = json_decode($rawInput, true);
    if (json_last_error() === JSON_ERROR_NONE && is_array($decoded)) {
        $requestData = $decoded;
    } elseif (in_array($httpMethod, ['POST', 'PUT', 'PATCH'], true)) {
        send_json_response(400, [
            'status'  => 'error',
            'code'    => 400,
            'message' => 'Malformed JSON payload: ' . json_last_error_msg(),
        ]);
    }
}

// If action was not provided in URL, check JSON payload
if ($action === null && !empty($requestData['action'])) {
    $action = strtolower(trim((string)$requestData['action']));
}

// Default action if nothing specified
if (empty($action)) {
    $action = 'test';
}

// Connect to Database
try {
    $pdo = get_db($config);
    $tabPrefix = get_table_prefix($config);
} catch (Throwable $e) {
    send_json_response(500, [
        'status'  => 'error',
        'code'    => 500,
        'message' => ($config['app']['debug'] ?? false)
            ? 'Database error: ' . $e->getMessage()
            : 'Internal server error: unable to establish database connection.',
    ]);
}

// Resolve current battery threshold (DB overrides config default if present)
$thresholdSetting = get_db_setting($pdo, 'low_battery_threshold');
$lowBatteryThreshold = ($thresholdSetting !== null && is_numeric($thresholdSetting))
    ? (int)$thresholdSetting
    : (int)($config['app']['default_low_battery_threshold'] ?? 20);

// Validate threshold range
if ($lowBatteryThreshold < 0 || $lowBatteryThreshold > 100) {
    $lowBatteryThreshold = 20;
}

// -----------------------------------------------------------------------------
// Endpoint Handlers
// -----------------------------------------------------------------------------

try {
    switch ($action) {
        // =====================================================================
        // 1. Test Connection Endpoint
        // Tablets (or teachers) verify API availability and valid credentials.
        // Can optionally verify pre-registration of a specific device_id.
        // =====================================================================
        case 'test':
        case 'test-connection':
        case 'ping':
            if ($userRole === AUTH_ROLE_NONE) {
                send_json_response(401, [
                    'status'  => 'error',
                    'code'    => 401,
                    'message' => 'Unauthorized: Valid API key required for connection test.',
                ]);
            }

            $deviceId = $_GET['device_id'] ?? $requestData['device_id'] ?? null;
            $deviceInfo = null;

            if (!empty($deviceId)) {
                $deviceId = trim((string)$deviceId);
                $stmt = $pdo->prepare("SELECT device_id, name, assigned_room, is_active FROM `{$tabPrefix}devices` WHERE device_id = :id LIMIT 1");
                $stmt->execute([':id' => $deviceId]);
                $row = $stmt->fetch();

                if (!$row) {
                    send_json_response(403, [
                        'status'            => 'error',
                        'code'              => 403,
                        'message'           => 'Device ID is not pre-registered.',
                        'device_id'         => $deviceId,
                        'device_registered' => false,
                    ]);
                }

                if ((int)$row['is_active'] !== 1) {
                    send_json_response(403, [
                        'status'            => 'error',
                        'code'              => 403,
                        'message'           => 'Device has been deactivated by administrator.',
                        'device_id'         => $deviceId,
                        'device_registered' => true,
                        'is_active'         => false,
                    ]);
                }

                $deviceInfo = [
                    'device_id'     => $row['device_id'],
                    'name'          => $row['name'],
                    'assigned_room' => $row['assigned_room'],
                    'is_active'     => true,
                ];
            }

            send_json_response(200, [
                'status'            => 'ok',
                'message'           => 'TabMonitor API connection successful.',
                'authenticated_as'  => ($userRole === AUTH_ROLE_TEACHER) ? 'teacher' : 'tablet',
                'server_time'       => date('c'),
                'battery_threshold' => $lowBatteryThreshold,
                'device'            => $deviceInfo,
            ]);
            break;

        // =====================================================================
        // 2. Battery Report Endpoint
        // Tablets report battery level (0-100) and charging status.
        // Requires tablet role and pre-registered active device_id.
        // =====================================================================
        case 'report':
        case 'battery-report':
            if ($httpMethod !== 'POST') {
                send_json_response(405, [
                    'status'  => 'error',
                    'code'    => 405,
                    'message' => 'Method Not Allowed: Battery reports must use POST.',
                ]);
            }

            // Shared key must be provided
            if ($userRole === AUTH_ROLE_NONE) {
                send_json_response(401, [
                    'status'  => 'error',
                    'code'    => 401,
                    'message' => 'Unauthorized: Valid tablet API key required to submit battery reports.',
                ]);
            }

            // Input validation: device_id
            $deviceId = trim((string)($requestData['device_id'] ?? ''));
            if ($deviceId === '' || !preg_match('/^[A-Za-z0-9_\-]{1,64}$/', $deviceId)) {
                send_json_response(400, [
                    'status'  => 'error',
                    'code'    => 400,
                    'message' => 'Invalid device_id. Must be 1-64 alphanumeric characters, underscores, or hyphens.',
                ]);
            }

            // Input validation: battery_level
            if (!isset($requestData['battery_level']) || !is_numeric($requestData['battery_level'])) {
                send_json_response(400, [
                    'status'  => 'error',
                    'code'    => 400,
                    'message' => 'Missing or non-numeric battery_level.',
                ]);
            }

            $batteryLevel = (int)$requestData['battery_level'];
            if ($batteryLevel < 0 || $batteryLevel > 100) {
                send_json_response(400, [
                    'status'  => 'error',
                    'code'    => 400,
                    'message' => 'battery_level must be an integer between 0 and 100.',
                ]);
            }

            // Input validation: is_charging
            $isChargingRaw = $requestData['is_charging'] ?? false;
            $isCharging = filter_var($isChargingRaw, FILTER_VALIDATE_BOOLEAN);

            // Pre-registered tablet verification
            $deviceStmt = $pdo->prepare("SELECT id, device_id, name, is_active FROM `{$tabPrefix}devices` WHERE device_id = :id LIMIT 1");
            $deviceStmt->execute([':id' => $deviceId]);
            $device = $deviceStmt->fetch();

            if (!$device) {
                send_json_response(403, [
                    'status'  => 'error',
                    'code'    => 403,
                    'message' => 'Forbidden: Tablet ID is not pre-registered in system.',
                    'device_id' => $deviceId,
                ]);
            }

            if ((int)$device['is_active'] !== 1) {
                send_json_response(403, [
                    'status'  => 'error',
                    'code'    => 403,
                    'message' => 'Forbidden: Tablet has been deactivated.',
                    'device_id' => $deviceId,
                ]);
            }

            $clientIp = get_client_ip();
            $isChargingInt = $isCharging ? 1 : 0;
            $now = date('Y-m-d H:i:s');

            // Atomic update: record in history and update latest device status
            $pdo->beginTransaction();
            try {
                // 1. Insert into history table
                $insertReport = $pdo->prepare(
                    "INSERT INTO `{$tabPrefix}battery_reports` (device_id, battery_level, is_charging, reported_at, ip_address)
                     VALUES (:device_id, :battery_level, :is_charging, :reported_at, :ip)"
                );
                $insertReport->execute([
                    ':device_id'      => $deviceId,
                    ':battery_level'  => $batteryLevel,
                    ':is_charging'    => $isChargingInt,
                    ':reported_at'    => $now,
                    ':ip'             => $clientIp,
                ]);

                // 2. Update snapshot on devices table
                $updateDevice = $pdo->prepare(
                    "UPDATE `{$tabPrefix}devices`
                     SET last_battery_level = :battery_level,
                         last_is_charging   = :is_charging,
                         last_reported_at   = :reported_at,
                         last_ip            = :ip
                     WHERE device_id = :device_id"
                );
                $updateDevice->execute([
                    ':battery_level' => $batteryLevel,
                    ':is_charging'   => $isChargingInt,
                    ':reported_at'   => $now,
                    ':ip'            => $clientIp,
                    ':device_id'     => $deviceId,
                ]);

                $pdo->commit();
            } catch (Throwable $e) {
                $pdo->rollBack();
                throw $e;
            }

            $isLowBattery = ($batteryLevel <= $lowBatteryThreshold);

            send_json_response(200, [
                'status'         => 'ok',
                'message'        => 'Battery report received successfully.',
                'device_id'      => $deviceId,
                'battery_level'  => $batteryLevel,
                'is_charging'    => $isCharging,
                'is_low_battery' => $isLowBattery,
                'threshold'      => $lowBatteryThreshold,
                'reported_at'    => $now,
            ]);
            break;

        // =====================================================================
        // 3. Device Status Retrieval (Teacher Dashboard)
        // Teachers retrieve current status of all tablets.
        // SECURITY: Shared tablet key MUST NEVER grant access here!
        // =====================================================================
        case 'devices':
        case 'status':
            if ($httpMethod !== 'GET') {
                send_json_response(405, [
                    'status'  => 'error',
                    'code'    => 405,
                    'message' => 'Method Not Allowed: Device status retrieval must use GET.',
                ]);
            }

            // CRITICAL: Prevent tablet key from accessing teacher endpoint
            if ($userRole === AUTH_ROLE_TABLET) {
                send_json_response(403, [
                    'status'  => 'error',
                    'code'    => 403,
                    'message' => 'Forbidden: Shared tablet API key cannot access teacher endpoints.',
                ]);
            }

            if ($userRole !== AUTH_ROLE_TEACHER) {
                send_json_response(401, [
                    'status'  => 'error',
                    'code'    => 401,
                    'message' => 'Unauthorized: Valid teacher authentication required.',
                ]);
            }

            $offlineThresholdMinutes = (int)($config['app']['offline_threshold_minutes'] ?? 30);
            $roomFilter = !empty($_GET['room']) ? trim((string)$_GET['room']) : null;
            $lowBatteryOnly = !empty($_GET['low_battery']);

            $sql = "SELECT id, device_id, name, assigned_room, is_active,
                           last_battery_level, last_is_charging, last_reported_at, last_ip, updated_at
                    FROM `{$tabPrefix}devices`";
            $params = [];

            if ($roomFilter !== null) {
                $sql .= ' WHERE assigned_room = :room';
                $params[':room'] = $roomFilter;
            }

            $sql .= ' ORDER BY name ASC';

            $stmt = $pdo->prepare($sql);
            $stmt->execute($params);
            $rows = $stmt->fetchAll();

            $currentTime = time();
            $devices = [];
            $totalActive = 0;
            $totalOnline = 0;
            $totalLowBattery = 0;

            foreach ($rows as $row) {
                $isActive = (bool)$row['is_active'];
                if ($isActive) {
                    $totalActive++;
                }

                $hasReported = !empty($row['last_reported_at']);
                $minutesSinceReport = null;
                $isOnline = false;

                if ($hasReported) {
                    $reportTimestamp = strtotime($row['last_reported_at']);
                    if ($reportTimestamp !== false) {
                        $minutesSinceReport = max(0, (int)round(($currentTime - $reportTimestamp) / 60));
                        $isOnline = ($minutesSinceReport <= $offlineThresholdMinutes) && $isActive;
                    }
                }

                if ($isOnline) {
                    $totalOnline++;
                }

                $batteryLevel = ($row['last_battery_level'] !== null) ? (int)$row['last_battery_level'] : null;
                $isCharging = ($row['last_is_charging'] !== null) ? (bool)$row['last_is_charging'] : null;
                $isLowBattery = ($batteryLevel !== null && $batteryLevel <= $lowBatteryThreshold);

                if ($isLowBattery) {
                    $totalLowBattery++;
                }

                if ($lowBatteryOnly && !$isLowBattery) {
                    continue;
                }

                $devices[] = [
                    'device_id'            => $row['device_id'],
                    'name'                 => $row['name'],
                    'assigned_room'        => $row['assigned_room'],
                    'is_active'            => $isActive,
                    'battery_level'        => $batteryLevel,
                    'is_charging'          => $isCharging,
                    'is_low_battery'       => $isLowBattery,
                    'is_online'            => $isOnline,
                    'last_reported_at'     => $row['last_reported_at'],
                    'minutes_since_report' => $minutesSinceReport,
                    'last_ip'              => $row['last_ip'],
                ];
            }

            send_json_response(200, [
                'status'                   => 'ok',
                'battery_threshold'        => $lowBatteryThreshold,
                'offline_threshold_minutes'=> $offlineThresholdMinutes,
                'summary' => [
                    'total_registered'  => count($rows),
                    'total_active'      => $totalActive,
                    'total_online'      => $totalOnline,
                    'total_low_battery' => $totalLowBattery,
                ],
                'devices' => $devices,
            ]);
            break;

        // =====================================================================
        // 4. Settings Endpoint
        // View or update system settings (e.g., low battery threshold).
        // SECURITY: Shared tablet key MUST NEVER modify settings!
        // =====================================================================
        case 'settings':
            // CRITICAL: Prevent tablet key from accessing settings
            if ($userRole === AUTH_ROLE_TABLET) {
                send_json_response(403, [
                    'status'  => 'error',
                    'code'    => 403,
                    'message' => 'Forbidden: Shared tablet API key cannot access or modify settings.',
                ]);
            }

            if ($userRole !== AUTH_ROLE_TEACHER) {
                send_json_response(401, [
                    'status'  => 'error',
                    'code'    => 401,
                    'message' => 'Unauthorized: Teacher authentication required for settings.',
                ]);
            }

            if ($httpMethod === 'POST') {
                if (isset($requestData['low_battery_threshold'])) {
                    if (!is_numeric($requestData['low_battery_threshold'])) {
                        send_json_response(400, [
                            'status'  => 'error',
                            'code'    => 400,
                            'message' => 'low_battery_threshold must be an integer between 0 and 100.',
                        ]);
                    }

                    $newThreshold = (int)$requestData['low_battery_threshold'];
                    if ($newThreshold < 0 || $newThreshold > 100) {
                        send_json_response(400, [
                            'status'  => 'error',
                            'code'    => 400,
                            'message' => 'low_battery_threshold must be between 0 and 100.',
                        ]);
                    }

                    set_db_setting(
                        $pdo,
                        'low_battery_threshold',
                        (string)$newThreshold,
                        'Threshold percentage below which a device is flagged as low battery'
                    );

                    $lowBatteryThreshold = $newThreshold;
                }

                send_json_response(200, [
                    'status'   => 'ok',
                    'message'  => 'Settings updated successfully.',
                    'settings' => [
                        'low_battery_threshold'     => $lowBatteryThreshold,
                        'offline_threshold_minutes' => (int)($config['app']['offline_threshold_minutes'] ?? 30),
                    ],
                ]);
            }

            // GET method: Return current settings
            send_json_response(200, [
                'status'   => 'ok',
                'settings' => [
                    'low_battery_threshold'     => $lowBatteryThreshold,
                    'offline_threshold_minutes' => (int)($config['app']['offline_threshold_minutes'] ?? 30),
                ],
            ]);
            break;

        // =====================================================================
        // 5. Pre-register Tablet Endpoint (Teacher/Admin)
        // Teachers can register new tablets or update existing ones.
        // SECURITY: Shared tablet key MUST NEVER register devices!
        // =====================================================================
        case 'register-device':
            if ($httpMethod !== 'POST') {
                send_json_response(405, [
                    'status'  => 'error',
                    'code'    => 405,
                    'message' => 'Method Not Allowed: Device registration requires POST.',
                ]);
            }

            if ($userRole === AUTH_ROLE_TABLET) {
                send_json_response(403, [
                    'status'  => 'error',
                    'code'    => 403,
                    'message' => 'Forbidden: Shared tablet API key cannot pre-register devices.',
                ]);
            }

            if ($userRole !== AUTH_ROLE_TEACHER) {
                send_json_response(401, [
                    'status'  => 'error',
                    'code'    => 401,
                    'message' => 'Unauthorized: Teacher authentication required to register devices.',
                ]);
            }

            $deviceId = trim((string)($requestData['device_id'] ?? ''));
            $name     = trim((string)($requestData['name'] ?? ''));
            $room     = isset($requestData['assigned_room']) ? trim((string)$requestData['assigned_room']) : null;
            $isActive = isset($requestData['is_active']) ? (filter_var($requestData['is_active'], FILTER_VALIDATE_BOOLEAN) ? 1 : 0) : 1;

            if ($deviceId === '' || !preg_match('/^[A-Za-z0-9_\-]{1,64}$/', $deviceId)) {
                send_json_response(400, [
                    'status'  => 'error',
                    'code'    => 400,
                    'message' => 'Invalid device_id. Must be 1-64 alphanumeric characters, underscores, or hyphens.',
                ]);
            }

            if ($name === '' || mb_strlen($name) > 100) {
                send_json_response(400, [
                    'status'  => 'error',
                    'code'    => 400,
                    'message' => 'Invalid device name. Must be between 1 and 100 characters.',
                ]);
            }

            $stmt = $pdo->prepare(
                "INSERT INTO `{$tabPrefix}devices` (device_id, name, assigned_room, is_active)
                 VALUES (:device_id, :name, :room, :is_active)
                 ON DUPLICATE KEY UPDATE
                    name          = VALUES(name),
                    assigned_room = VALUES(assigned_room),
                    is_active     = VALUES(is_active),
                    updated_at    = NOW()"
            );

            $stmt->execute([
                ':device_id'  => $deviceId,
                ':name'       => $name,
                ':room'       => $room,
                ':is_active'  => $isActive,
            ]);

            send_json_response(200, [
                'status'    => 'ok',
                'message'   => 'Device pre-registered/updated successfully.',
                'device_id' => $deviceId,
            ]);
            break;

        // =====================================================================
        // Default: Unknown Action
        // =====================================================================
        default:
            send_json_response(404, [
                'status'  => 'error',
                'code'    => 404,
                'message' => "Unknown action '{$action}'. Valid actions: test, report, devices, settings, register-device.",
            ]);
            break;
    }
} catch (Throwable $e) {
    error_log('API Exception: ' . $e->getMessage() . "\n" . $e->getTraceAsString());

    send_json_response(500, [
        'status'  => 'error',
        'code'    => 500,
        'message' => ($config['app']['debug'] ?? false)
            ? 'Server error: ' . $e->getMessage()
            : 'Internal server error occurred while processing request.',
    ]);
}
