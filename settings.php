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
    }
}

// Fetch current threshold from DB
$currentThreshold = (int)get_db_setting(
    $pdo,
    'low_battery_threshold',
    $config['app']['default_low_battery_threshold'] ?? 20
);

$csrfToken = get_csrf_token();
$teacherUsername = htmlspecialchars($_SESSION['teacher_username'] ?? 'Teacher', ENT_QUOTES, 'UTF-8');
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Settings - TabMonitor</title>
  <link rel="stylesheet" href="style.css">
</head>
<body>

  <!-- Navigation Bar -->
  <header class="navbar">
    <div class="nav-container">
      <a href="index.php" class="brand">
        <span class="brand-icon">📱</span> TabMonitor
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

        <!-- 2. Teacher Password Update Card -->
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

  <footer class="footer">
    TabMonitor &bull; Teacher Portal &bull; Clean &amp; Lightweight PHP Backend
  </footer>

</body>
</html>
