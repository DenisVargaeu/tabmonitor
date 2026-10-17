<?php
declare(strict_types=1);

/**
 * TabMonitor - Teacher Settings (Phase 2)
 *
 * Provides teacher-only settings management:
 * - Low battery threshold configuration (0 to 100%).
 * - Optional teacher password update.
 * - CSRF verification and session authorization.
 */

require_once __DIR__ . '/db.php';
$config = require __DIR__ . '/config.php';

// Enforce teacher authorization
require_teacher_auth();

$pdo = get_db($config);
ensure_teachers_table($pdo);

$successMessage = null;
$errorMessage   = null;

// Handle Form Submissions
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $submittedToken = $_POST['csrf_token'] ?? null;
    $formAction     = $_POST['form_action'] ?? '';

    if (!validate_csrf_token($submittedToken)) {
        $errorMessage = 'Security token invalid or expired. Please refresh the page.';
    } elseif ($formAction === 'update_threshold') {
        $thresholdRaw = $_POST['low_battery_threshold'] ?? null;

        if (!isset($thresholdRaw) || !is_numeric($thresholdRaw)) {
            $errorMessage = 'Battery threshold must be a valid number.';
        } else {
            $threshold = (int)$thresholdRaw;
            if ($threshold < 0 || $threshold > 100) {
                $errorMessage = 'Battery threshold must be between 0% and 100%.';
            } else {
                set_db_setting(
                    $pdo,
                    'low_battery_threshold',
                    (string)$threshold,
                    'Threshold percentage below which a device is flagged as low battery'
                );
                $successMessage = "Low battery threshold successfully updated to {$threshold}%.";
            }
        }
    } elseif ($formAction === 'update_interval') {
        $intervalRaw = $_POST['report_interval_minutes'] ?? null;

        if (!isset($intervalRaw) || !is_numeric($intervalRaw)) {
            $errorMessage = 'Reporting interval must be a valid number.';
        } else {
            $interval = (int)$intervalRaw;
            if ($interval < 5 || $interval > 120) {
                $errorMessage = 'Reporting interval must be between 5 and 120 minutes.';
            } else {
                set_db_setting(
                    $pdo,
                    'report_interval_minutes',
                    (string)$interval,
                    'Interval in minutes between tablet battery reports (min 5, default 15)'
                );
                $successMessage = "Tablet reporting interval successfully updated to {$interval} minutes.";
            }
        }
    } elseif ($formAction === 'change_password') {
        $currentPass = (string)($_POST['current_password'] ?? '');
        $newPass     = (string)($_POST['new_password'] ?? '');
        $confirmPass = (string)($_POST['confirm_password'] ?? '');

        if ($currentPass === '' || $newPass === '' || $confirmPass === '') {
            $errorMessage = 'All password fields are required.';
        } elseif (mb_strlen($newPass) < 6) {
            $errorMessage = 'New password must be at least 6 characters long.';
        } elseif ($newPass !== $confirmPass) {
            $errorMessage = 'New password and confirmation do not match.';
        } else {
            $teacherId = (int)$_SESSION['teacher_id'];
            $tabPrefix = get_table_prefix($config);
            $stmt = $pdo->prepare("SELECT password_hash FROM `{$tabPrefix}teachers` WHERE id = :id LIMIT 1");
            $stmt->execute([':id' => $teacherId]);
            $row = $stmt->fetch();

            if ($row && password_verify($currentPass, (string)$row['password_hash'])) {
                $newHash = password_hash($newPass, PASSWORD_DEFAULT);
                $updateStmt = $pdo->prepare("UPDATE `{$tabPrefix}teachers` SET password_hash = :h, updated_at = NOW() WHERE id = :id");
                $updateStmt->execute([':h' => $newHash, ':id' => $teacherId]);
                $successMessage = 'Your password has been successfully updated.';
            } else {
                $errorMessage = 'Incorrect current password.';
            }
        }
    } elseif ($formAction === 'add_device') {
        $newDeviceId = strtoupper(trim((string)($_POST['device_id'] ?? '')));
        $newName     = trim((string)($_POST['name'] ?? ''));
        $newRoom     = trim((string)($_POST['assigned_room'] ?? ''));
        $isActive    = isset($_POST['is_active']) ? 1 : 0;
        $tabPrefix   = get_table_prefix($config);

        if ($newDeviceId === '' || !preg_match('/^[A-Za-z0-9_\-\.]{2,50}$/', $newDeviceId)) {
            $errorMessage = 'Invalid Tablet ID. Must be 2-50 alphanumeric characters (e.g. TAB-006, XX-01).';
        } else {
            $checkStmt = $pdo->prepare("SELECT id FROM `{$tabPrefix}devices` WHERE device_id = :id LIMIT 1");
            $checkStmt->execute([':id' => $newDeviceId]);
            if ($checkStmt->fetch()) {
                $errorMessage = "Tablet ID '{$newDeviceId}' is already registered.";
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
                $successMessage = "Tablet ID '{$newDeviceId}' registered successfully! You can now configure this tablet.";
            }
        }
    }
}

// Fetch current threshold from DB
$currentThreshold = (int)get_db_setting(
    $pdo,
    'low_battery_threshold',
    $config['app']['default_low_battery_threshold'] ?? 20
);

// Fetch current reporting interval from DB
$currentInterval = (int)get_db_setting(
    $pdo,
    'report_interval_minutes',
    $config['app']['default_report_interval_minutes'] ?? 15
);
if ($currentInterval < 5 || $currentInterval > 120) {
    $currentInterval = 15;
}

$tabPrefix = get_table_prefix($config);
$deviceCountStmt = $pdo->query("SELECT COUNT(*) FROM `{$tabPrefix}devices`");
$totalDevicesCount = (int)$deviceCountStmt->fetchColumn();

$csrfToken = get_csrf_token();
$teacherUsername = htmlspecialchars($_SESSION['teacher_username'] ?? 'Teacher', ENT_QUOTES, 'UTF-8');
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Settings - TabMonitor</title>
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
          <li><a href="index.php" class="nav-link">Dashboard</a></li>
          <li><a href="settings.php" class="nav-link active">Settings</a></li>
        </ul>
      </nav>

      <div class="user-controls">
        <span class="threshold-badge">
          ⚡ Alert: <strong><?= $currentThreshold ?>%</strong>
        </span>
        <span class="threshold-badge" style="background: rgba(14, 165, 233, 0.15); color: #0284c7; border: 1px solid rgba(14, 165, 233, 0.3);">
          ⏱️ Interval: <strong><?= $currentInterval ?>m</strong>
        </span>
        <span class="user-name">👤 <?= $teacherUsername ?></span>
        <a href="logout.php" class="btn-logout" title="Sign out">Log Out</a>
      </div>
    </div>
  </header>

  <!-- Main Content -->
  <main class="main-container">

    <?php if ($successMessage): ?>
      <div class="alert alert-success">
        <span>✓ <?= htmlspecialchars($successMessage, ENT_QUOTES, 'UTF-8') ?></span>
      </div>
    <?php endif; ?>

    <?php if ($errorMessage): ?>
      <div class="alert alert-danger">
        <span>⚠️ <?= htmlspecialchars($errorMessage, ENT_QUOTES, 'UTF-8') ?></span>
      </div>
    <?php endif; ?>

    <div class="settings-grid">
      <!-- Left Column: Settings Forms -->
      <div class="settings-main">

        <!-- 1. Battery Threshold Card -->
        <div class="settings-card">
          <h2 class="settings-card-title">🔋 Battery Alert Threshold</h2>
          <p class="settings-card-desc">
            Tablets with remaining battery percentage at or below this value are prominently flagged in the Low Battery alert section.
          </p>

          <form method="POST" action="settings.php">
            <input type="hidden" name="csrf_token" value="<?= htmlspecialchars($csrfToken, ENT_QUOTES, 'UTF-8') ?>">
            <input type="hidden" name="form_action" value="update_threshold">

            <div class="threshold-slider-group">
              <input 
                type="range" 
                id="thresholdRange" 
                min="0" 
                max="100" 
                value="<?= $currentThreshold ?>" 
                class="threshold-slider"
                oninput="document.getElementById('thresholdNumber').value = this.value"
              >
              <input 
                type="number" 
                id="thresholdNumber" 
                name="low_battery_threshold" 
                min="0" 
                max="100" 
                value="<?= $currentThreshold ?>" 
                class="threshold-input-number"
                required
                oninput="document.getElementById('thresholdRange').value = this.value"
              >
              <span style="font-weight: 700; color: var(--text-muted); font-size: 1.1rem;">%</span>
            </div>

            <button type="submit" class="btn-primary" style="width: auto; padding: 0.65rem 1.5rem;">
              Save Threshold
            </button>
          </form>
        </div>

        <!-- 2. Tablet Reporting Interval Card -->
        <div class="settings-card">
          <h2 class="settings-card-title">⏱️ Tablet Reporting Interval</h2>
          <p class="settings-card-desc">
            Global frequency at which connected tablets submit battery telemetry to the server. Default is 15 minutes, but can be set down to 5 minutes for rapid tracking.
          </p>

          <form method="POST" action="settings.php">
            <input type="hidden" name="csrf_token" value="<?= htmlspecialchars($csrfToken, ENT_QUOTES, 'UTF-8') ?>">
            <input type="hidden" name="form_action" value="update_interval">

            <div class="threshold-slider-group">
              <input 
                type="range" 
                id="intervalRange" 
                min="5" 
                max="60" 
                step="1"
                value="<?= $currentInterval ?>" 
                class="threshold-slider"
                oninput="document.getElementById('intervalNumber').value = this.value"
              >
              <input 
                type="number" 
                id="intervalNumber" 
                name="report_interval_minutes" 
                min="5" 
                max="120" 
                value="<?= $currentInterval ?>" 
                class="threshold-input-number"
                required
                oninput="document.getElementById('intervalRange').value = this.value"
              >
              <span style="font-weight: 700; color: var(--text-muted); font-size: 1.1rem;">min</span>
            </div>

            <div style="display: flex; gap: 0.5rem; margin-bottom: 1.25rem; flex-wrap: wrap;">
              <button type="button" class="btn-preset" onclick="setIntervalVal(5)">5m (Min)</button>
              <button type="button" class="btn-preset" onclick="setIntervalVal(10)">10m</button>
              <button type="button" class="btn-preset" onclick="setIntervalVal(15)">15m (Default)</button>
              <button type="button" class="btn-preset" onclick="setIntervalVal(30)">30m</button>
              <button type="button" class="btn-preset" onclick="setIntervalVal(60)">60m</button>
            </div>

            <button type="submit" class="btn-primary" style="width: auto; padding: 0.65rem 1.5rem;">
              Save Reporting Interval
            </button>
          </form>
        </div>

        <!-- 3. Register New Tablet ID Card -->
        <div class="settings-card">
          <h2 class="settings-card-title">📱 Register New Tablet ID</h2>
          <p class="settings-card-desc">
            Pre-register a new tablet ID before connecting the tablet app. Only pre-registered IDs are allowed to submit battery reports.
          </p>

          <form method="POST" action="settings.php">
            <input type="hidden" name="csrf_token" value="<?= htmlspecialchars($csrfToken, ENT_QUOTES, 'UTF-8') ?>">
            <input type="hidden" name="form_action" value="add_device">

            <div class="form-group">
              <label class="form-label" for="settings_device_id">Tablet ID <span class="required" style="color:var(--danger)">*</span></label>
              <input 
                type="text" 
                id="settings_device_id" 
                name="device_id" 
                class="form-input" 
                placeholder="e.g. TAB-006, XX-01" 
                required 
                pattern="[A-Za-z0-9_\-\.]{2,50}"
                autocomplete="off"
                style="text-transform: uppercase;"
              >
              <small class="form-hint">Unique identifier typed into the tablet app.</small>
            </div>

            <div class="form-group">
              <label class="form-label" for="settings_name">Tablet Display Name</label>
              <input 
                type="text" 
                id="settings_name" 
                name="name" 
                class="form-input" 
                placeholder="e.g. Tablet 06, Cart 1 - #06"
              >
              <small class="form-hint">Friendly label shown on dashboard.</small>
            </div>

            <div class="form-group">
              <label class="form-label" for="settings_assigned_room">Assigned Room / Cart</label>
              <input 
                type="text" 
                id="settings_assigned_room" 
                name="assigned_room" 
                class="form-input" 
                placeholder="e.g. Classroom 101, IT Lab"
              >
              <small class="form-hint">Physical location or cart.</small>
            </div>

            <div class="form-group" style="margin-top: 1rem;">
              <label style="display: flex; align-items: center; gap: 0.5rem; cursor: pointer; font-size: 0.9rem; font-weight: 500;">
                <input type="checkbox" name="is_active" value="1" checked style="width: 1.1rem; height: 1.1rem;">
                <span>Active (Accept battery reports)</span>
              </label>
            </div>

            <button type="submit" class="btn-primary" style="width: auto; padding: 0.65rem 1.5rem; margin-top: 0.5rem;">
              Register Tablet ID
            </button>
          </form>
        </div>

        <!-- 3. Teacher Password Update Card -->
        <div class="settings-card">
          <h2 class="settings-card-title">🔑 Change Password</h2>
          <p class="settings-card-desc">
            Update your teacher web dashboard sign-in password.
          </p>

          <form method="POST" action="settings.php">
            <input type="hidden" name="csrf_token" value="<?= htmlspecialchars($csrfToken, ENT_QUOTES, 'UTF-8') ?>">
            <input type="hidden" name="form_action" value="change_password">

            <div class="form-group">
              <label class="form-label" for="current_password">Current Password</label>
              <input type="password" id="current_password" name="current_password" class="form-input" required>
            </div>

            <div class="form-group">
              <label class="form-label" for="new_password">New Password (min. 6 characters)</label>
              <input type="password" id="new_password" name="new_password" class="form-input" minlength="6" required>
            </div>

            <div class="form-group">
              <label class="form-label" for="confirm_password">Confirm New Password</label>
              <input type="password" id="confirm_password" name="confirm_password" class="form-input" minlength="6" required>
            </div>

            <button type="submit" class="btn-primary" style="width: auto; padding: 0.65rem 1.5rem;">
              Update Password
            </button>
          </form>
        </div>

      </div>

      <!-- Right Column: System Information -->
      <div class="settings-sidebar">
        <div class="settings-card">
          <h2 class="settings-card-title">ℹ️ System Info</h2>
          <p class="settings-card-desc">Hosting & backend details</p>

          <ul class="info-list">
            <li class="info-item">
              <span class="info-label">Web Admin</span>
              <span class="info-val"><strong>v<?= TABMONITOR_VERSION ?></strong></span>
            </li>
            <li class="info-item">
              <span class="info-label">API Protocol</span>
              <span class="info-val"><strong>v<?= TABMONITOR_VERSION ?></strong></span>
            </li>
            <li class="info-item">
              <span class="info-label">Environment</span>
              <span class="info-val">Webglobe Shared</span>
            </li>
            <li class="info-item">
              <span class="info-label">PHP Version</span>
              <span class="info-val"><?= PHP_VERSION ?></span>
            </li>
            <li class="info-item">
              <span class="info-label">Database</span>
              <span class="info-val"><?= htmlspecialchars((string)($config['db']['name'] ?? 'MySQL'), ENT_QUOTES, 'UTF-8') ?></span>
            </li>
            <li class="info-item">
              <span class="info-label">Registered Tablets</span>
              <span class="info-val"><a href="index.php" style="color: var(--primary); text-decoration: none; font-weight: bold;"><?= $totalDevicesCount ?> tablets ➔</a></span>
            </li>
            <li class="info-item">
              <span class="info-label">Reporting Interval</span>
              <span class="info-val"><?= $currentInterval ?> mins</span>
            </li>
            <li class="info-item">
              <span class="info-label">Offline Timeout</span>
              <span class="info-val"><?= (int)($config['app']['offline_threshold_minutes'] ?? 30) ?> mins</span>
            </li>
            <li class="info-item">
              <span class="info-label">Timezone</span>
              <span class="info-val"><?= htmlspecialchars(date_default_timezone_get(), ENT_QUOTES, 'UTF-8') ?></span>
            </li>
            <li class="info-item">
              <span class="info-label">Server Time</span>
              <span class="info-val"><?= date('H:i:s') ?></span>
            </li>
            <li class="info-item">
              <span class="info-label">API Status</span>
              <span class="info-val" style="color: var(--success);">Online ✓</span>
            </li>
          </ul>
        </div>
      </div>
    </div>

  </main>

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

  <script>
    function setIntervalVal(minutes) {
      const range = document.getElementById('intervalRange');
      const number = document.getElementById('intervalNumber');
      if (range) range.value = minutes;
      if (number) number.value = minutes;
    }
  </script>
</body>
</html>
