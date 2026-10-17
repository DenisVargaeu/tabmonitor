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
    ];

    $devices[] = $deviceItem;

    if ($isLowBattery) {
        $lowBatteryDevices[] = $deviceItem;
    }
}

$totalRegistered = count($devices);
$totalLowBattery = count($lowBatteryDevices);
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
          <div class="metric-value"><?= $totalRegistered ?></div>
        </div>
        <div class="metric-icon">📱</div>
      </div>

      <div class="metric-card">
        <div class="metric-info">
          <h3>Online</h3>
          <div class="metric-value" style="color: var(--success);"><?= $totalOnline ?></div>
        </div>
        <div class="metric-icon">🟢</div>
      </div>

      <div class="metric-card">
        <div class="metric-info">
          <h3>Offline</h3>
          <div class="metric-value" style="color: var(--text-muted);"><?= $totalOffline ?></div>
        </div>
        <div class="metric-icon">⚪</div>
      </div>

      <div class="metric-card <?= ($totalLowBattery > 0) ? 'alert-card' : '' ?>">
        <div class="metric-info">
          <h3>Low Battery Alerts</h3>
          <div class="metric-value" style="<?= ($totalLowBattery > 0) ? 'color: var(--danger);' : '' ?>">
            <?= $totalLowBattery ?>
          </div>
        </div>
        <div class="metric-icon"><?= ($totalLowBattery > 0) ? '⚠️' : '🔋' ?></div>
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
        <button type="button" class="btn-primary" onclick="toggleAddDeviceForm()" id="btnAddDeviceBtn" style="width: auto; padding: 0.5rem 1.1rem; font-size: 0.9rem;">
          ➕ Add Tablet ID
        </button>
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
          <button type="button" class="btn-refresh" onclick="window.location.reload();" title="Refresh list now">
            🔄 Refresh
          </button>
          <label class="auto-refresh-label" title="Automatically reload every 30 seconds">
            <input type="checkbox" id="autoRefreshCheckbox"> Auto-refresh (30s)
          </label>
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
  </script>

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
