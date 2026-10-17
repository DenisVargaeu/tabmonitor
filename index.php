<?php
declare(strict_types=1);

/**
 * TabMonitor - Teacher Web Dashboard (Phase 2)
 *
 * Lightweight, responsive classroom dashboard showing tablet battery levels,
 * charging statuses, offline indicators, and a dedicated low-battery list.
 */

require_once __DIR__ . '/db.php';
$config = require __DIR__ . '/config.php';

// Enforce teacher authorization
require_teacher_auth();

$pdo = get_db($config);
ensure_teachers_table($pdo);

$tabPrefix = get_table_prefix($config);
$successMessage = null;
$errorMessage   = null;

// Handle AJAX Requests (Force sync broadcast & live device status)
$ajaxAction = $_GET['ajax'] ?? $_POST['ajax'] ?? null;
if ($ajaxAction !== null) {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

    if ($ajaxAction === 'force_sync') {
        $nowTs = time();
        set_db_setting(
            $pdo,
            'force_sync_requested_at',
            (string)$nowTs,
            'Timestamp of last teacher force sync command broadcast to tablet fleet'
        );

        $stmt = $pdo->query("SELECT COUNT(*) FROM `{$tabPrefix}devices` WHERE is_active = 1");
        $activeCount = (int)$stmt->fetchColumn();

        echo json_encode([
            'status'               => 'ok',
            'success'              => true,
            'message'              => 'Force sync command broadcast to all active tablets.',
            'force_sync_timestamp' => $nowTs,
            'force_sync_at'        => date('Y-m-d H:i:s', $nowTs),
            'active_devices_count' => $activeCount,
        ]);
        exit;
    }

    if ($ajaxAction === 'get_devices') {
        $lowBatteryThreshold = (int)get_db_setting(
            $pdo,
            'low_battery_threshold',
            $config['app']['default_low_battery_threshold'] ?? 20
        );
        $offlineThresholdMinutes = (int)($config['app']['offline_threshold_minutes'] ?? 30);
        $currentTime = time();

        $stmt = $pdo->query(
            "SELECT id, device_id, name, assigned_room, is_active,
                    last_battery_level, last_is_charging, last_reported_at, last_ip, updated_at
             FROM `{$tabPrefix}devices`
             ORDER BY name ASC"
        );
        $rows = $stmt->fetchAll();

        $deviceList = [];
        $totalOnline = 0;
        $totalOffline = 0;
        $totalCharging = 0;
        $totalLowBattery = 0;

        foreach ($rows as $row) {
            $isActive = (bool)$row['is_active'];
            $hasReported = !empty($row['last_reported_at']);
            $minutesSinceReport = null;
            $isOnline = false;
            $reportTs = 0;

            if ($hasReported) {
                $ts = strtotime($row['last_reported_at']);
                if ($ts !== false) {
                    $reportTs = $ts;
                    $minutesSinceReport = max(0, (int)round(($currentTime - $ts) / 60));
                    $isOnline = ($minutesSinceReport <= $offlineThresholdMinutes) && $isActive;
                }
            }

            if ($isOnline) {
                $totalOnline++;
            } else {
                $totalOffline++;
            }

            $batteryLevel = ($row['last_battery_level'] !== null) ? (int)$row['last_battery_level'] : null;
            $isCharging = ($row['last_is_charging'] !== null) ? (bool)$row['last_is_charging'] : false;

            if ($isCharging) {
                $totalCharging++;
            }

            $isLowBattery = ($batteryLevel !== null && $batteryLevel <= $lowBatteryThreshold);
            if ($isLowBattery) {
                $totalLowBattery++;
            }

            $deviceList[] = [
                'id'                      => (int)$row['id'],
                'device_id'               => (string)$row['device_id'],
                'name'                    => (string)$row['name'],
                'assigned_room'           => !empty($row['assigned_room']) ? (string)$row['assigned_room'] : 'Unassigned',
                'is_active'               => $isActive,
                'battery_level'           => $batteryLevel,
                'is_charging'             => $isCharging,
                'is_online'               => $isOnline,
                'is_low_battery'          => $isLowBattery,
                'last_reported_at'        => $row['last_reported_at'],
                'last_reported_timestamp' => $reportTs,
                'relative_time'           => format_relative_time($row['last_reported_at']),
                'last_ip'                 => $row['last_ip'],
            ];
        }

        echo json_encode([
            'status'            => 'ok',
            'success'           => true,
            'server_time'       => date('c'),
            'total_registered'  => count($rows),
            'total_online'      => $totalOnline,
            'total_offline'     => $totalOffline,
            'total_charging'    => $totalCharging,
            'total_low_battery' => $totalLowBattery,
            'battery_threshold' => $lowBatteryThreshold,
            'devices'           => $deviceList,
        ]);
        exit;
    }
}

// Handle Device Management Actions
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $submittedToken = $_POST['csrf_token'] ?? null;
    $formAction     = $_POST['form_action'] ?? '';

    if (!validate_csrf_token($submittedToken)) {
        $errorMessage = 'Security token invalid or expired. Please refresh the page.';
    } elseif ($formAction === 'add_device') {
        $newDeviceId = strtoupper(trim((string)($_POST['device_id'] ?? '')));
        $newName     = trim((string)($_POST['name'] ?? ''));
        $newRoom     = trim((string)($_POST['assigned_room'] ?? ''));
        $isActive    = isset($_POST['is_active']) ? 1 : 0;

        if ($newDeviceId === '' || !preg_match('/^[A-Za-z0-9_\-\.]{2,50}$/', $newDeviceId)) {
            $errorMessage = 'Invalid Tablet ID. Must be 2-50 alphanumeric characters (e.g. TAB-006, XX-01).';
        } else {
            $checkStmt = $pdo->prepare("SELECT id FROM `{$tabPrefix}devices` WHERE device_id = :id LIMIT 1");
            $checkStmt->execute([':id' => $newDeviceId]);
            if ($checkStmt->fetch()) {
                $errorMessage = "Tablet ID '{$newDeviceId}' is already registered in the system.";
            } else {
                if ($newName === '') {
                    $newName = 'Tablet ' . $newDeviceId;
                }
                $insertStmt = $pdo->prepare(
                    "INSERT INTO `{$tabPrefix}devices` (device_id, name, assigned_room, is_active, created_at, updated_at)
                     VALUES (:device_id, :name, :room, :is_active, NOW(), NOW())"
                );
                $insertStmt->execute([
                    ':device_id' => $newDeviceId,
                    ':name'      => $newName,
                    ':room'      => ($newRoom !== '') ? $newRoom : null,
                    ':is_active' => $isActive,
                ]);
                $successMessage = "Tablet ID '{$newDeviceId}' registered successfully! You can now configure the tablet app with this ID.";
            }
        }
    } elseif ($formAction === 'toggle_active') {
        $toggleId = trim((string)($_POST['device_id'] ?? ''));
        if ($toggleId !== '') {
            $toggleStmt = $pdo->prepare(
                "UPDATE `{$tabPrefix}devices` SET is_active = IF(is_active = 1, 0, 1), updated_at = NOW() WHERE device_id = :id LIMIT 1"
            );
            $toggleStmt->execute([':id' => $toggleId]);
            $successMessage = "Status updated for tablet '{$toggleId}'.";
        }
    } elseif ($formAction === 'delete_device') {
        $delId = trim((string)($_POST['device_id'] ?? ''));
        if ($delId !== '') {
            $pdo->prepare("DELETE FROM `{$tabPrefix}battery_reports` WHERE device_id = :id")->execute([':id' => $delId]);
            $delStmt = $pdo->prepare("DELETE FROM `{$tabPrefix}devices` WHERE device_id = :id LIMIT 1");
            $delStmt->execute([':id' => $delId]);
            $successMessage = "Tablet '{$delId}' has been deleted.";
        }
    }
}

// Resolve low battery threshold
$lowBatteryThreshold = (int)get_db_setting(
    $pdo,
    'low_battery_threshold',
    $config['app']['default_low_battery_threshold'] ?? 20
);

$offlineThresholdMinutes = (int)($config['app']['offline_threshold_minutes'] ?? 30);
$currentTime = time();

// Fetch all registered tablets
$stmt = $pdo->query(
    "SELECT id, device_id, name, assigned_room, is_active,
            last_battery_level, last_is_charging, last_reported_at, last_ip, updated_at
     FROM `{$tabPrefix}devices`
     ORDER BY name ASC"
);
$rows = $stmt->fetchAll();

// Compute base URL and tablet key for bulk setup codes (syntax: server-key-id)
$isHttps = (!empty($_SERVER['HTTPS']) && strtolower($_SERVER['HTTPS']) !== 'off')
    || (isset($_SERVER['SERVER_PORT']) && (int)$_SERVER['SERVER_PORT'] === 443)
    || (!empty($_SERVER['HTTP_X_FORWARDED_PROTO']) && strtolower($_SERVER['HTTP_X_FORWARDED_PROTO']) === 'https');
$protocol = $isHttps ? 'https://' : 'http://';
$host = $_SERVER['HTTP_HOST'] ?? 'localhost';
$baseDir = rtrim(dirname($_SERVER['SCRIPT_NAME']), '/\\');
$serverBaseUrl = $protocol . $host . $baseDir;
$tabletApiKey = (string)($config['security']['tablet_api_key'] ?? '');

$devices = [];
$lowBatteryDevices = [];
$totalOnline = 0;
$totalOffline = 0;
$totalCharging = 0;

foreach ($rows as $row) {
    $isActive = (bool)$row['is_active'];
    $hasReported = !empty($row['last_reported_at']);
    $minutesSinceReport = null;
    $isOnline = false;

    if ($hasReported) {
        $ts = strtotime($row['last_reported_at']);
        if ($ts !== false) {
            $minutesSinceReport = max(0, (int)round(($currentTime - $ts) / 60));
            $isOnline = ($minutesSinceReport <= $offlineThresholdMinutes) && $isActive;
        }
    }

    if ($isOnline) {
        $totalOnline++;
    } else {
        $totalOffline++;
    }

    $batteryLevel = ($row['last_battery_level'] !== null) ? (int)$row['last_battery_level'] : null;
    $isCharging = ($row['last_is_charging'] !== null) ? (bool)$row['last_is_charging'] : false;

    if ($isCharging) {
        $totalCharging++;
    }

    $isLowBattery = ($batteryLevel !== null && $batteryLevel <= $lowBatteryThreshold);
    $bulkCode = $serverBaseUrl . '-' . $tabletApiKey . '-' . (string)$row['device_id'];

    $deviceItem = [
        'id'                   => (int)$row['id'],
        'device_id'            => (string)$row['device_id'],
        'name'                 => (string)$row['name'],
        'assigned_room'        => !empty($row['assigned_room']) ? (string)$row['assigned_room'] : 'Unassigned',
        'is_active'            => $isActive,
        'battery_level'        => $batteryLevel,
        'is_charging'          => $isCharging,
        'is_online'            => $isOnline,
        'is_low_battery'       => $isLowBattery,
        'last_reported_at'     => $row['last_reported_at'],
        'minutes_since_report' => $minutesSinceReport,
        'relative_time'        => format_relative_time($row['last_reported_at']),
        'last_ip'              => $row['last_ip'],
        'bulk_setup_code'      => $bulkCode,
    ];

    $devices[] = $deviceItem;

    if ($isLowBattery) {
        $lowBatteryDevices[] = $deviceItem;
    }
}

$totalRegistered = count($devices);
$totalLowBattery = count($lowBatteryDevices);
$allBulkCodes = implode("\n", array_map(fn($d) => $d['bulk_setup_code'], $devices));
$csrfToken = get_csrf_token();
$teacherUsername = htmlspecialchars($_SESSION['teacher_username'] ?? 'Teacher', ENT_QUOTES, 'UTF-8');
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>TabMonitor - Teacher Dashboard</title>
  <link rel="icon" type="image/png" href="favicon.png">
  <link rel="stylesheet" href="style.css">
</head>
<body>

  <!-- Navigation Bar -->
  <header class="navbar">
    <div class="nav-container">
      <a href="index.php" class="brand">
        <span class="brand-icon">📱</span> TabMonitor <span class="version-badge">v<?= TABMONITOR_VERSION ?></span>
      </a>

      <nav>
        <ul class="nav-links">
          <li><a href="index.php" class="nav-link active">Dashboard</a></li>
          <li><a href="settings.php" class="nav-link">Settings</a></li>
        </ul>
      </nav>

      <div class="user-controls">
        <a href="settings.php" class="threshold-badge" title="Click to adjust threshold in Settings">
          ⚡ Alert: <strong><?= $lowBatteryThreshold ?>%</strong>
        </a>
        <span class="user-name">👤 <?= $teacherUsername ?></span>
        <a href="logout.php" class="btn-logout" title="Sign out">Log Out</a>
      </div>
    </div>
  </header>

  <!-- Main Container -->
  <main class="main-container">

    <?php if ($successMessage): ?>
      <div class="alert alert-success">
        <span>✓ <?= htmlspecialchars($successMessage, ENT_QUOTES, 'UTF-8') ?></span>
        <button type="button" class="alert-close" onclick="this.parentElement.remove()">✕</button>
      </div>
    <?php endif; ?>

    <?php if ($errorMessage): ?>
      <div class="alert alert-danger">
        <span>⚠️ <?= htmlspecialchars($errorMessage, ENT_QUOTES, 'UTF-8') ?></span>
        <button type="button" class="alert-close" onclick="this.parentElement.remove()">✕</button>
      </div>
    <?php endif; ?>

    <!-- 1. Statistics Cards -->
    <section class="metrics-grid">
      <div class="metric-card">
        <div class="metric-info">
          <h3>Total Tablets</h3>
          <div class="metric-value" id="metricTotalTablets"><?= $totalRegistered ?></div>
        </div>
        <div class="metric-icon">📱</div>
      </div>

      <div class="metric-card">
        <div class="metric-info">
          <h3>Online</h3>
          <div class="metric-value" id="metricTotalOnline" style="color: var(--success);"><?= $totalOnline ?></div>
        </div>
        <div class="metric-icon">🟢</div>
      </div>

      <div class="metric-card">
        <div class="metric-info">
          <h3>Offline</h3>
          <div class="metric-value" id="metricTotalOffline" style="color: var(--text-muted);"><?= $totalOffline ?></div>
        </div>
        <div class="metric-icon">⚪</div>
      </div>

      <div class="metric-card <?= ($totalLowBattery > 0) ? 'alert-card' : '' ?>" id="metricLowBatteryCard">
        <div class="metric-info">
          <h3>Low Battery Alerts</h3>
          <div class="metric-value" id="metricTotalLowBattery" style="<?= ($totalLowBattery > 0) ? 'color: var(--danger);' : '' ?>">
            <?= $totalLowBattery ?>
          </div>
        </div>
        <div class="metric-icon" id="metricLowBatteryIcon"><?= ($totalLowBattery > 0) ? '⚠️' : '🔋' ?></div>
      </div>
    </section>

    <!-- 2. Separate List of Tablets At or Below Server Threshold -->
    <section class="section-low-battery">
      <div class="section-header">
        <h2 class="section-title">
          <span>⚠️ Tablets at or below <?= $lowBatteryThreshold ?>% Battery</span>
          <?php if ($totalLowBattery > 0): ?>
            <span class="badge-count"><?= $totalLowBattery ?> Needs Charging</span>
          <?php endif; ?>
        </h2>
      </div>

      <?php if ($totalLowBattery === 0): ?>
        <p style="color: var(--success); font-weight: 500; font-size: 0.95rem;">
          ✓ All registered tablets currently have healthy battery levels above the <?= $lowBatteryThreshold ?>% threshold.
        </p>
      <?php else: ?>
        <div class="low-battery-grid">
          <?php foreach ($lowBatteryDevices as $dev): ?>
            <div class="low-battery-card">
              <div class="low-card-header">
                <div>
                  <div class="low-card-title"><?= htmlspecialchars($dev['name'], ENT_QUOTES, 'UTF-8') ?></div>
                  <div class="low-card-room"><?= htmlspecialchars($dev['assigned_room'], ENT_QUOTES, 'UTF-8') ?></div>
                </div>
                <span class="device-id-badge"><?= htmlspecialchars($dev['device_id'], ENT_QUOTES, 'UTF-8') ?></span>
              </div>

              <div class="battery-container">
                <div class="battery-bar-bg">
                  <div class="battery-bar-fill fill-danger" style="width: <?= max(5, $dev['battery_level'] ?? 0) ?>%;"></div>
                </div>
                <span class="battery-text text-danger"><?= $dev['battery_level'] ?>%</span>
              </div>

              <div style="display: flex; justify-content: space-between; align-items: center; font-size: 0.85rem; margin-top: 0.25rem;">
                <?php if ($dev['is_charging']): ?>
                  <span class="badge-charging">⚡ Charging</span>
                <?php else: ?>
                  <span class="badge-discharging">🔋 Discharging</span>
                <?php endif; ?>

                <span class="time-contact" title="<?= htmlspecialchars($dev['last_reported_at'] ?? '', ENT_QUOTES, 'UTF-8') ?>">
                  Contact: <?= htmlspecialchars($dev['relative_time'], ENT_QUOTES, 'UTF-8') ?>
                </span>
              </div>
            </div>
          <?php endforeach; ?>
        </div>
      <?php endif; ?>
    </section>

    <!-- 3. All Registered Tablets Table & Controls -->
    <section class="section-devices">
      <div class="section-header" style="display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 0.75rem;">
        <h2 class="section-title">📋 All Registered Tablets</h2>
        <div style="display: flex; gap: 0.5rem; align-items: center; flex-wrap: wrap;">
          <button type="button" class="btn-secondary" onclick="toggleBulkModal(true)" style="width: auto; padding: 0.5rem 1.1rem; font-size: 0.9rem;">
            ⚡ Bulk Setup Kódy
          </button>
          <button type="button" class="btn-primary" onclick="toggleAddDeviceForm()" id="btnAddDeviceBtn" style="width: auto; padding: 0.5rem 1.1rem; font-size: 0.9rem;">
            ➕ Add Tablet ID
          </button>
        </div>
      </div>

      <!-- Add New Tablet Form Card -->
      <div id="addDeviceCard" class="add-device-card" style="display: <?= ($errorMessage && ($_POST['form_action'] ?? '') === 'add_device') ? 'block' : 'none' ?>;">
        <div class="add-device-header">
          <div>
            <h3 style="font-size: 1.1rem; font-weight: 700; color: var(--text-main);">➕ Register New Tablet ID</h3>
            <p style="font-size: 0.85rem; color: var(--text-muted); margin-top: 0.2rem;">
              Enter the unique Tablet ID that you will type into the tablet app.
            </p>
          </div>
          <button type="button" class="btn-close" onclick="toggleAddDeviceForm(false)" title="Close">✕</button>
        </div>

        <form method="POST" action="index.php" class="add-device-form">
          <input type="hidden" name="csrf_token" value="<?= htmlspecialchars($csrfToken, ENT_QUOTES, 'UTF-8') ?>">
          <input type="hidden" name="form_action" value="add_device">

          <div class="form-grid">
            <div class="form-group">
              <label class="form-label" for="new_device_id">Tablet ID <span class="required" style="color:var(--danger)">*</span></label>
              <input 
                type="text" 
                id="new_device_id" 
                name="device_id" 
                class="form-input" 
                placeholder="e.g. TAB-006, XX-01" 
                required 
                pattern="[A-Za-z0-9_\-\.]{2,50}"
                autocomplete="off"
                style="text-transform: uppercase;"
                value="<?= htmlspecialchars($_POST['device_id'] ?? '', ENT_QUOTES, 'UTF-8') ?>"
              >
              <small class="form-hint">Unique hardware ID entered on the tablet (e.g. TAB-006, XX-01).</small>
            </div>

            <div class="form-group">
              <label class="form-label" for="new_device_name">Tablet Display Name</label>
              <input 
                type="text" 
                id="new_device_name" 
                name="name" 
                class="form-input" 
                placeholder="e.g. Tablet 06, Cart 1 - #06"
                value="<?= htmlspecialchars($_POST['name'] ?? '', ENT_QUOTES, 'UTF-8') ?>"
              >
              <small class="form-hint">Friendly label displayed on the dashboard (optional).</small>
            </div>

            <div class="form-group">
              <label class="form-label" for="new_assigned_room">Assigned Room / Cart</label>
              <input 
                type="text" 
                id="new_assigned_room" 
                name="assigned_room" 
                class="form-input" 
                placeholder="e.g. Classroom 101, Science Lab"
                value="<?= htmlspecialchars($_POST['assigned_room'] ?? '', ENT_QUOTES, 'UTF-8') ?>"
              >
              <small class="form-hint">Classroom, cart, or cabinet location (optional).</small>
            </div>

            <div class="form-group" style="display: flex; align-items: center; margin-top: 1.5rem;">
              <label style="display: flex; align-items: center; gap: 0.5rem; cursor: pointer; font-size: 0.9rem; font-weight: 500;">
                <input type="checkbox" name="is_active" value="1" checked style="width: 1.1rem; height: 1.1rem;">
                <span>Active (Accept battery reports)</span>
              </label>
            </div>
          </div>

          <div style="display: flex; gap: 0.75rem; margin-top: 1.25rem;">
            <button type="submit" class="btn-primary" style="width: auto; padding: 0.65rem 1.5rem;">
              Register Tablet
            </button>
            <button type="button" class="btn-secondary" onclick="toggleAddDeviceForm(false)">
              Cancel
            </button>
          </div>
        </form>
      </div>

      <!-- Search & Filter Toolbar -->
      <div class="toolbar">
        <div class="search-box">
          <span class="search-icon">🔍</span>
          <input 
            type="text" 
            id="deviceSearch" 
            class="search-input" 
            placeholder="Search by Device ID, Name, or Room..."
            autocomplete="off"
          >
        </div>

        <div class="filter-buttons">
          <button type="button" class="btn-filter active" data-filter="all">All (<?= $totalRegistered ?>)</button>
          <button type="button" class="btn-filter" data-filter="low">Low Battery (<?= $totalLowBattery ?>)</button>
          <button type="button" class="btn-filter" data-filter="offline">Offline (<?= $totalOffline ?>)</button>
          <button type="button" class="btn-filter" data-filter="charging">Charging (<?= $totalCharging ?>)</button>
        </div>

        <div class="refresh-control">
          <button type="button" class="btn-force-reload" id="btnForceReload" onclick="triggerForceFleetReload();" title="Vynútiť okamžité odoslanie telemetrie zo všetkých tabletov">
            ⚡ Vynútiť načítanie zo zariadení
          </button>
          <button type="button" class="btn-refresh" onclick="window.location.reload();" title="Refresh list now">
            🔄 Refresh
          </button>
          <label class="auto-refresh-label" title="Automatically reload every 30 seconds">
            <input type="checkbox" id="autoRefreshCheckbox"> Auto-refresh (30s)
          </label>
        </div>
      </div>

      <!-- Force Sync Live Status Banner -->
      <div id="forceSyncBanner" class="force-sync-banner" style="display: none;">
        <div style="display: flex; align-items: center; gap: 0.65rem;">
          <span id="forceSyncIcon" style="font-size: 1.25rem;">📡</span>
          <div>
            <strong id="forceSyncTitle" style="color: inherit;">Vynucovanie načítania zo zariadení:</strong>
            <span id="forceSyncDesc" style="margin-left: 4px;">Odoslaná požiadavka. Čakám na odpovede tabletov v reálnom čase...</span>
          </div>
        </div>
        <div style="display: flex; align-items: center; gap: 0.85rem;">
          <div id="forceSyncProgress" style="font-weight: 700; font-family: monospace; font-size: 0.95rem;">
            0 / <?= $totalRegistered ?> odpovedalo
          </div>
          <button type="button" onclick="document.getElementById('forceSyncBanner').style.display='none'" style="background:none; border:none; cursor:pointer; font-size:1.1rem; color:inherit; padding: 2px 6px;" title="Zatvoriť">✕</button>
        </div>
      </div>

      <!-- Responsive Device Table -->
      <div class="table-responsive">
        <table class="devices-table" id="devicesTable">
          <thead>
            <tr>
              <th>Device ID</th>
              <th>Name &amp; Room</th>
              <th>Battery Level</th>
              <th>Charging</th>
              <th>Last Contact</th>
              <th>Status</th>
              <th style="text-align: right;">Actions</th>
            </tr>
          </thead>
          <tbody>
            <?php if (empty($devices)): ?>
              <tr>
                <td colspan="7" class="empty-state">
                  <div class="empty-state-icon">📱</div>
                  <p>No tablets have been registered yet.</p>
                </td>
              </tr>
            <?php else: ?>
              <?php foreach ($devices as $d): ?>
                <?php
                  $battery = $d['battery_level'];
                  if ($battery === null) {
                      $fillClass = 'fill-warn';
                      $textClass = 'text-warn';
                      $batteryDisplay = 'N/A';
                      $batteryWidth = 0;
                  } elseif ($d['is_low_battery']) {
                      $fillClass = 'fill-danger';
                      $textClass = 'text-danger';
                      $batteryDisplay = $battery . '%';
                      $batteryWidth = max(5, $battery);
                  } elseif ($battery <= 40) {
                      $fillClass = 'fill-warn';
                      $textClass = 'text-warn';
                      $batteryDisplay = $battery . '%';
                      $batteryWidth = $battery;
                  } else {
                      $fillClass = 'fill-good';
                      $textClass = 'text-good';
                      $batteryDisplay = $battery . '%';
                      $batteryWidth = $battery;
                  }
                ?>
                <tr 
                  class="device-row <?= $d['is_low_battery'] ? 'row-low-battery' : '' ?>"
                  data-device-id="<?= htmlspecialchars(strtolower($d['device_id']), ENT_QUOTES, 'UTF-8') ?>"
                  data-name="<?= htmlspecialchars(strtolower($d['name']), ENT_QUOTES, 'UTF-8') ?>"
                  data-room="<?= htmlspecialchars(strtolower($d['assigned_room']), ENT_QUOTES, 'UTF-8') ?>"
                  data-low="<?= $d['is_low_battery'] ? '1' : '0' ?>"
                  data-online="<?= $d['is_online'] ? '1' : '0' ?>"
                  data-charging="<?= $d['is_charging'] ? '1' : '0' ?>"
                >
                  <td>
                    <span class="device-id-badge"><?= htmlspecialchars($d['device_id'], ENT_QUOTES, 'UTF-8') ?></span>
                  </td>
                  <td>
                    <div class="device-name"><?= htmlspecialchars($d['name'], ENT_QUOTES, 'UTF-8') ?></div>
                    <div class="device-room"><?= htmlspecialchars($d['assigned_room'], ENT_QUOTES, 'UTF-8') ?></div>
                  </td>
                  <td>
                    <div class="battery-container">
                      <div class="battery-bar-bg">
                        <div class="battery-bar-fill <?= $fillClass ?>" style="width: <?= $batteryWidth ?>%;"></div>
                      </div>
                      <span class="battery-text <?= $textClass ?>"><?= $batteryDisplay ?></span>
                    </div>
                  </td>
                  <td>
                    <?php if ($d['is_charging']): ?>
                      <span class="badge-charging">⚡ Charging</span>
                    <?php else: ?>
                      <span class="badge-discharging">🔋 On Battery</span>
                    <?php endif; ?>
                  </td>
                  <td>
                    <div class="time-contact"><?= htmlspecialchars($d['relative_time'], ENT_QUOTES, 'UTF-8') ?></div>
                    <?php if (!empty($d['last_reported_at'])): ?>
                      <div class="time-exact"><?= htmlspecialchars($d['last_reported_at'], ENT_QUOTES, 'UTF-8') ?></div>
                    <?php endif; ?>
                  </td>
                  <td>
                    <?php if ($d['is_online']): ?>
                      <span class="status-pill online"><span class="status-dot"></span> Online</span>
                    <?php else: ?>
                      <span class="status-pill offline"><span class="status-dot"></span> Offline</span>
                    <?php endif; ?>
                  </td>
                  <td style="text-align: right;">
                    <div class="action-buttons" style="justify-content: flex-end;">
                      <button type="button" class="btn-action btn-bulk-copy" title="Copy Bulk Setup Code: <?= htmlspecialchars($d['bulk_setup_code'], ENT_QUOTES, 'UTF-8') ?>" onclick="copyBulkCode('<?= htmlspecialchars($d['bulk_setup_code'], ENT_QUOTES, 'UTF-8') ?>', '<?= htmlspecialchars($d['device_id'], ENT_QUOTES, 'UTF-8') ?>')">
                        ⚡ Kód
                      </button>

                      <form method="POST" action="index.php" style="display:inline;" onsubmit="return confirm('Toggle active status for <?= htmlspecialchars($d['device_id'], ENT_QUOTES, 'UTF-8') ?>?');">
                        <input type="hidden" name="csrf_token" value="<?= htmlspecialchars($csrfToken, ENT_QUOTES, 'UTF-8') ?>">
                        <input type="hidden" name="form_action" value="toggle_active">
                        <input type="hidden" name="device_id" value="<?= htmlspecialchars($d['device_id'], ENT_QUOTES, 'UTF-8') ?>">
                        <button type="submit" class="btn-action <?= $d['is_active'] ? 'btn-active' : 'btn-inactive' ?>" title="Click to <?= $d['is_active'] ? 'Deactivate' : 'Activate' ?>">
                          <?= $d['is_active'] ? 'Active' : 'Disabled' ?>
                        </button>
                      </form>

                      <form method="POST" action="index.php" style="display:inline;" onsubmit="return confirm('Are you sure you want to delete tablet <?= htmlspecialchars($d['device_id'], ENT_QUOTES, 'UTF-8') ?>? All reports for this tablet will also be removed.');">
                        <input type="hidden" name="csrf_token" value="<?= htmlspecialchars($csrfToken, ENT_QUOTES, 'UTF-8') ?>">
                        <input type="hidden" name="form_action" value="delete_device">
                        <input type="hidden" name="device_id" value="<?= htmlspecialchars($d['device_id'], ENT_QUOTES, 'UTF-8') ?>">
                        <button type="submit" class="btn-action btn-delete" title="Delete Tablet">
                          🗑️
                        </button>
                      </form>
                    </div>
                  </td>
                </tr>
              <?php endforeach; ?>
            <?php endif; ?>
          </tbody>
        </table>
      </div>

      <div id="noMatchMessage" class="empty-state" style="display: none;">
        <div class="empty-state-icon">🔍</div>
        <p>No tablets found matching your search or filter.</p>
      </div>
    </section>

  </main>

  <!-- Footer -->
  <footer class="footer">
    TabMonitor &bull; Teacher Portal &bull; Low Battery Threshold: <?= $lowBatteryThreshold ?>%
  </footer>

  <!-- Minimal JavaScript: Search Filter & Auto-refresh -->
  <script>
    (function() {
      const searchInput = document.getElementById('deviceSearch');
      const filterButtons = document.querySelectorAll('.btn-filter');
      const rows = document.querySelectorAll('.device-row');
      const noMatchMsg = document.getElementById('noMatchMessage');
      const autoRefreshCheckbox = document.getElementById('autoRefreshCheckbox');

      let currentFilter = 'all';

      function applyFilters() {
        const query = (searchInput.value || '').trim().toLowerCase();
        let visibleCount = 0;

        rows.forEach(function(row) {
          const deviceId = row.getAttribute('data-device-id') || '';
          const name = row.getAttribute('data-name') || '';
          const room = row.getAttribute('data-room') || '';
          const isLow = row.getAttribute('data-low') === '1';
          const isOnline = row.getAttribute('data-online') === '1';
          const isCharging = row.getAttribute('data-charging') === '1';

          // Search match
          const matchesSearch = query === '' || 
            deviceId.includes(query) || 
            name.includes(query) || 
            room.includes(query);

          // Category filter match
          let matchesFilter = true;
          if (currentFilter === 'low') {
            matchesFilter = isLow;
          } else if (currentFilter === 'offline') {
            matchesFilter = !isOnline;
          } else if (currentFilter === 'charging') {
            matchesFilter = isCharging;
          }

          if (matchesSearch && matchesFilter) {
            row.style.display = '';
            visibleCount++;
          } else {
            row.style.display = 'none';
          }
        });

        if (noMatchMsg) {
          noMatchMsg.style.display = (visibleCount === 0 && rows.length > 0) ? 'block' : 'none';
        }
      }

      // Search input listener
      if (searchInput) {
        searchInput.addEventListener('input', applyFilters);
      }

      // Filter button listeners
      filterButtons.forEach(function(btn) {
        btn.addEventListener('click', function() {
          filterButtons.forEach(b => b.classList.remove('active'));
          btn.classList.add('active');
          currentFilter = btn.getAttribute('data-filter') || 'all';
          applyFilters();
        });
      });

      // Auto-refresh logic (persisted in localStorage)
      let refreshTimer = null;
      if (autoRefreshCheckbox) {
        const savedPref = localStorage.getItem('tabmonitor_autorefresh');
        if (savedPref === 'true') {
          autoRefreshCheckbox.checked = true;
          startRefreshTimer();
        }

        autoRefreshCheckbox.addEventListener('change', function() {
          localStorage.setItem('tabmonitor_autorefresh', this.checked ? 'true' : 'false');
          if (this.checked) {
            startRefreshTimer();
          } else {
            clearInterval(refreshTimer);
          }
        });
      }

      function startRefreshTimer() {
        clearInterval(refreshTimer);
        refreshTimer = setInterval(function() {
          window.location.reload();
        }, 30000);
      }
    })();

    let isFleetSyncing = false;
    let syncStartTime = 0;
    let fleetSyncInterval = null;

    async function triggerForceFleetReload() {
      if (isFleetSyncing) return;
      isFleetSyncing = true;
      syncStartTime = Math.floor(Date.now() / 1000);

      const btn = document.getElementById('btnForceReload');
      const banner = document.getElementById('forceSyncBanner');
      const title = document.getElementById('forceSyncTitle');
      const desc = document.getElementById('forceSyncDesc');
      const progress = document.getElementById('forceSyncProgress');
      const icon = document.getElementById('forceSyncIcon');

      if (btn) {
        btn.disabled = true;
        btn.innerHTML = '<span class="spinner-inline"></span> Vynucujem načítanie...';
      }

      if (banner) {
        banner.className = 'force-sync-banner syncing';
        banner.style.display = 'flex';
        if (icon) icon.textContent = '📡';
        if (title) title.textContent = 'Vynucovanie načítania zo zariadení:';
        if (desc) desc.textContent = 'Odoslaná požiadavka na všetky tablety. Čakám na odpovede tabletov v reálnom čase...';
        if (progress) progress.textContent = '0 odpovedí...';
      }

      showToast('⚡ Vynútené obnovenie spustené: Odoslaná požiadavka do celej flotily.');

      let totalActive = 0;
      try {
        const res = await fetch('index.php?ajax=force_sync', {
          method: 'POST',
          headers: { 'X-Requested-With': 'XMLHttpRequest' }
        });
        const data = await res.json();
        if (data.force_sync_timestamp) {
          syncStartTime = data.force_sync_timestamp;
        }
        totalActive = data.active_devices_count || 0;
      } catch (e) {
        console.error('Error broadcasting force sync:', e);
      }

      let attempts = 0;
      const maxAttempts = 15;
      const respondedDeviceIds = new Set();

      fleetSyncInterval = setInterval(async function() {
        attempts++;
        try {
          const res = await fetch('index.php?ajax=get_devices', {
            headers: { 'X-Requested-With': 'XMLHttpRequest' }
          });
          const data = await res.json();
          if (data && data.devices) {
            totalActive = data.devices.filter(d => d.is_active).length;

            // Update Metric Cards
            const metricTotal = document.getElementById('metricTotalTablets');
            const metricOnline = document.getElementById('metricTotalOnline');
            const metricOffline = document.getElementById('metricTotalOffline');
            const metricLow = document.getElementById('metricTotalLowBattery');
            const lowCard = document.getElementById('metricLowBatteryCard');
            const lowIcon = document.getElementById('metricLowBatteryIcon');

            if (metricTotal) metricTotal.textContent = data.total_registered;
            if (metricOnline) metricOnline.textContent = data.total_online;
            if (metricOffline) metricOffline.textContent = data.total_offline;
            if (metricLow) {
              metricLow.textContent = data.total_low_battery;
              metricLow.style.color = data.total_low_battery > 0 ? 'var(--danger)' : '';
            }
            if (lowCard) {
              if (data.total_low_battery > 0) lowCard.classList.add('alert-card');
              else lowCard.classList.remove('alert-card');
            }
            if (lowIcon) {
              lowIcon.textContent = data.total_low_battery > 0 ? '⚠️' : '🔋';
            }

            // Update Filter Buttons Text
            const fAll = document.querySelector('.btn-filter[data-filter="all"]');
            const fLow = document.querySelector('.btn-filter[data-filter="low"]');
            const fOff = document.querySelector('.btn-filter[data-filter="offline"]');
            const fChg = document.querySelector('.btn-filter[data-filter="charging"]');
            if (fAll) fAll.textContent = `All (${data.total_registered})`;
            if (fLow) fLow.textContent = `Low Battery (${data.total_low_battery})`;
            if (fOff) fOff.textContent = `Offline (${data.total_offline})`;
            if (fChg) fChg.textContent = `Charging (${data.total_charging})`;

            // Update Table Rows
            data.devices.forEach(function(dev) {
              const row = document.querySelector(`tr[data-device-id="${dev.device_id.toLowerCase()}"]`);
              if (row) {
                row.setAttribute('data-low', dev.is_low_battery ? '1' : '0');
                row.setAttribute('data-online', dev.is_online ? '1' : '0');
                row.setAttribute('data-charging', dev.is_charging ? '1' : '0');

                if (dev.is_low_battery) {
                  row.classList.add('row-low-battery');
                } else {
                  row.classList.remove('row-low-battery');
                }

                const barFill = row.querySelector('.battery-bar-fill');
                const barText = row.querySelector('.battery-text');
                if (barFill && barText) {
                  barFill.className = 'battery-bar-fill ' + (dev.is_low_battery ? 'fill-danger' : (dev.battery_level <= 40 ? 'fill-warn' : 'fill-good'));
                  barFill.style.width = (dev.battery_level !== null ? Math.max(5, dev.battery_level) : 0) + '%';
                  barText.className = 'battery-text ' + (dev.is_low_battery ? 'text-danger' : (dev.battery_level <= 40 ? 'text-warn' : 'text-good'));
                  barText.textContent = dev.battery_level !== null ? (dev.battery_level + '%') : 'N/A';
                }

                const chargingCell = row.cells[3];
                if (chargingCell) {
                  chargingCell.innerHTML = dev.is_charging
                    ? '<span class="badge-charging">⚡ Charging</span>'
                    : '<span class="badge-discharging">🔋 On Battery</span>';
                }

                const contactDiv = row.querySelector('.time-contact');
                const exactDiv = row.querySelector('.time-exact');
                if (contactDiv) contactDiv.textContent = dev.relative_time;
                if (exactDiv && dev.last_reported_at) exactDiv.textContent = dev.last_reported_at;

                const statusCell = row.cells[5];
                if (statusCell) {
                  statusCell.innerHTML = dev.is_online
                    ? '<span class="status-pill online"><span class="status-dot"></span> Online</span>'
                    : '<span class="status-pill offline"><span class="status-dot"></span> Offline</span>';
                }

                if (dev.last_reported_timestamp >= syncStartTime) {
                  if (!respondedDeviceIds.has(dev.device_id)) {
                    respondedDeviceIds.add(dev.device_id);
                    row.classList.remove('row-just-updated');
                    void row.offsetWidth; // trigger CSS animation restart
                    row.classList.add('row-just-updated');
                  }
                }
              }
            });

            if (progress) {
              progress.textContent = `${respondedDeviceIds.size} / ${totalActive} odpovedalo`;
            }

            if (totalActive > 0 && respondedDeviceIds.size >= totalActive) {
              endFleetSync(true, respondedDeviceIds.size, totalActive);
              return;
            }
          }
        } catch (err) {
          console.error('Error polling devices during force sync:', err);
        }

        if (attempts >= maxAttempts) {
          endFleetSync(false, respondedDeviceIds.size, totalActive);
        }
      }, 1000);
    }

    function endFleetSync(allResponded, count, total) {
      clearInterval(fleetSyncInterval);
      isFleetSyncing = false;

      const btn = document.getElementById('btnForceReload');
      const banner = document.getElementById('forceSyncBanner');
      const title = document.getElementById('forceSyncTitle');
      const desc = document.getElementById('forceSyncDesc');
      const progress = document.getElementById('forceSyncProgress');
      const icon = document.getElementById('forceSyncIcon');

      if (btn) {
        btn.disabled = false;
        btn.innerHTML = '⚡ Vynútiť načítanie zo zariadení';
      }

      if (banner) {
        banner.className = 'force-sync-banner';
        if (icon) icon.textContent = '✓';
        if (title) title.textContent = 'Aktualizácia dokončená:';
        if (desc) desc.textContent = count > 0 
          ? `Úspešne prijaté čerstvé dáta z ${count} zariadení v reálnom čase!` 
          : 'Žiadne zariadenie v tejto chvíli neodpovedalo (uistite sa, že aplikácia TabMonitor na tabletoch beží).';
        if (progress) progress.textContent = `${count} / ${total} zariadení`;
      }

      showToast(`✓ Vynútené načítanie dokončené (${count} tabletov odpovedalo).`);
    }

    function toggleAddDeviceForm(show) {
      const card = document.getElementById('addDeviceCard');
      if (!card) return;
      const isCurrentlyHidden = card.style.display === 'none' || card.style.display === '';
      const willShow = (show !== undefined) ? show : isCurrentlyHidden;
      card.style.display = willShow ? 'block' : 'none';
      if (willShow) {
        document.getElementById('new_device_id')?.focus();
      }
    }

    function toggleBulkModal(show) {
      const modal = document.getElementById('bulkSetupModal');
      if (!modal) return;
      modal.style.display = show ? 'flex' : 'none';
    }

    function copyBulkCode(code, deviceId) {
      navigator.clipboard.writeText(code).then(function() {
        showToast('Kód pre tablet ' + deviceId + ' bol skopírovaný!');
      }).catch(function() {
        prompt('Skopírujte si Bulk Setup kód:', code);
      });
    }

    function copyAllBulkCodes() {
      const textarea = document.getElementById('allBulkCodesTextarea');
      if (textarea) {
        textarea.select();
        navigator.clipboard.writeText(textarea.value).then(function() {
          showToast('Všetky Bulk Setup kódy boli skopírované!');
        }).catch(function() {
          showToast('Kódy boli označené, stlačte Ctrl+C.');
        });
      }
    }

    function showToast(message) {
      const toast = document.createElement('div');
      toast.innerText = message;
      toast.style.position = 'fixed';
      toast.style.bottom = '24px';
      toast.style.right = '24px';
      toast.style.background = '#0f172a';
      toast.style.color = '#ffffff';
      toast.style.padding = '12px 20px';
      toast.style.borderRadius = '10px';
      toast.style.boxShadow = '0 6px 20px rgba(0,0,0,0.2)';
      toast.style.zIndex = '9999';
      toast.style.fontSize = '0.9rem';
      toast.style.fontWeight = '500';
      toast.style.transition = 'opacity 0.3s ease, transform 0.3s ease';
      document.body.appendChild(toast);
      setTimeout(function() {
        toast.style.opacity = '0';
        toast.style.transform = 'translateY(10px)';
        setTimeout(function() { toast.remove(); }, 300);
      }, 3000);
    }
  </script>

  <!-- Bulk Setup Modal -->
  <div id="bulkSetupModal" class="modal-backdrop" style="display: none;" onclick="if(event.target===this) toggleBulkModal(false);">
    <div class="modal-card">
      <div class="modal-header">
        <div>
          <h3 style="font-size: 1.15rem; font-weight: 700; color: var(--text-main); display: flex; align-items: center; gap: 8px;">
            ⚡ Hromadné nastavenie tabletov (Bulk Setup)
          </h3>
          <p style="font-size: 0.85rem; color: var(--text-muted); margin-top: 0.25rem;">
            Syntax kódu pre tablety: <code style="background: var(--bg-surface, #f1f5f9); padding: 2px 6px; border-radius: 4px; font-weight: bold;">adresaserveru-tabletkey-tabid</code>
          </p>
        </div>
        <button type="button" class="btn-close" onclick="toggleBulkModal(false)" title="Close">✕</button>
      </div>

      <div class="modal-body" style="padding: 1.25rem 0; overflow-y: auto;">
        <p style="font-size: 0.9rem; margin-bottom: 1rem; color: var(--text-main);">
          Tento kód stačí skopírovať a zadať v aplikácii na tablete v <strong>1. kroku sprievodcu</strong> cez tlačidlo <em>„Zadať kód“</em> alebo ikonu ⚡. Aplikácia sa automaticky otestuje a nastaví na 1 klik!
        </p>

        <div style="margin-bottom: 1.25rem;">
          <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.4rem;">
            <label style="font-size: 0.8rem; font-weight: bold; color: var(--text-muted); text-transform: uppercase;">Všetky kódy (1 tablet na riadok):</label>
            <button type="button" class="btn-action btn-bulk-copy" style="font-size: 0.8rem; padding: 4px 10px;" onclick="copyAllBulkCodes()">
              📋 Kopírovať všetko
            </button>
          </div>
          <textarea id="allBulkCodesTextarea" readonly class="form-input" style="height: 110px; font-family: monospace; font-size: 0.8rem; line-height: 1.4; resize: vertical;"><?= htmlspecialchars($allBulkCodes, ENT_QUOTES, 'UTF-8') ?></textarea>
        </div>

        <h4 style="font-size: 0.9rem; font-weight: 600; margin-bottom: 0.5rem; color: var(--text-main);">Kódy pre jednotlivé tablety:</h4>
        <div style="max-height: 220px; overflow-y: auto; border: 1px solid var(--border-color); border-radius: 8px;">
          <table style="width: 100%; border-collapse: collapse; font-size: 0.85rem;">
            <tbody>
              <?php foreach ($devices as $d): ?>
                <tr style="border-bottom: 1px solid var(--border-color);">
                  <td style="padding: 8px 12px; font-weight: bold; width: 100px;">
                    <?= htmlspecialchars($d['device_id'], ENT_QUOTES, 'UTF-8') ?>
                  </td>
                  <td style="padding: 8px 12px; font-family: monospace; font-size: 0.78rem; word-break: break-all;">
                    <?= htmlspecialchars($d['bulk_setup_code'], ENT_QUOTES, 'UTF-8') ?>
                  </td>
                  <td style="padding: 8px 12px; text-align: right; width: 85px;">
                    <button type="button" class="btn-action btn-bulk-copy" style="padding: 4px 8px; font-size: 0.75rem;" onclick="copyBulkCode('<?= htmlspecialchars($d['bulk_setup_code'], ENT_QUOTES, 'UTF-8') ?>', '<?= htmlspecialchars($d['device_id'], ENT_QUOTES, 'UTF-8') ?>')">
                      📋 Copy
                    </button>
                  </td>
                </tr>
              <?php endforeach; ?>
            </tbody>
          </table>
        </div>
      </div>

      <div class="modal-footer" style="display: flex; justify-content: flex-end; padding-top: 1rem; border-top: 1px solid var(--border-color);">
        <button type="button" class="btn-primary" onclick="toggleBulkModal(false)" style="width: auto; padding: 0.5rem 1.25rem;">
          Zatvoriť
        </button>
      </div>
    </div>
  </div>

  <!-- Web Admin Footer -->
  <footer class="app-footer">
    <div class="footer-content">
      <span>TabMonitor Web Admin <strong>v<?= TABMONITOR_VERSION ?></strong></span>
      <span class="footer-dot">•</span>
      <span>Tablet Agent <strong>v<?= TABMONITOR_VERSION ?></strong></span>
      <span class="footer-dot">•</span>
      <span>PHP <?= PHP_MAJOR_VERSION . '.' . PHP_MINOR_VERSION ?></span>
    </div>
  </footer>

</body>
</html>
