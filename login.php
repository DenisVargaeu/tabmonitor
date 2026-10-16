<?php
declare(strict_types=1);

/**
 * TabMonitor - Teacher Login (Phase 2)
 *
 * Implements secure authentication using password_verify(),
 * secure session parameters, session fixation protection,
 * and CSRF token verification.
 */

require_once __DIR__ . '/db.php';
$config = require __DIR__ . '/config.php';

start_secure_session($config);

// If already authenticated, redirect to dashboard
if (is_teacher_authenticated()) {
    header('Location: index.php');
    exit;
}

$errorMessage = null;
$successMessage = null;

if (!empty($_GET['logged_out'])) {
    $successMessage = 'You have been successfully logged out.';
} elseif (!empty($_GET['expired']) || !empty($_SESSION['session_expired'])) {
    $errorMessage = 'Your session has expired due to inactivity. Please log in again.';
    unset($_SESSION['session_expired']);
}

// Ensure database and teachers table are available
try {
    $pdo = get_db($config);
    ensure_teachers_table($pdo);
} catch (Throwable $e) {
    $errorMessage = 'Database connection error. Please verify server configuration.';
}

// Handle login submission
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $submittedToken = $_POST['csrf_token'] ?? null;
    $username       = trim((string)($_POST['username'] ?? ''));
    $password       = (string)($_POST['password'] ?? '');

    if (!validate_csrf_token($submittedToken)) {
        $errorMessage = 'Invalid or expired security token. Please refresh and try again.';
    } elseif ($username === '' || $password === '') {
        $errorMessage = 'Please enter both your username and password.';
    } elseif (!isset($pdo)) {
        $errorMessage = 'Database is currently unavailable.';
    } else {
        $tabPrefix = get_table_prefix($config);
        $stmt = $pdo->prepare("SELECT id, username, password_hash, name FROM `{$tabPrefix}teachers` WHERE username = :u LIMIT 1");
        $stmt->execute([':u' => $username]);
        $teacher = $stmt->fetch();

        if ($teacher && password_verify($password, (string)$teacher['password_hash'])) {
            // Prevent session fixation attack
            session_regenerate_id(true);

            $_SESSION['teacher_logged_in'] = true;
            $_SESSION['teacher_id']        = (int)$teacher['id'];
            $_SESSION['teacher_username']  = (string)$teacher['username'];
            $_SESSION['teacher_name']      = (string)$teacher['name'];
            $_SESSION['last_activity']     = time();
            $_SESSION['csrf_token']        = bin2hex(random_bytes(32));

            $redirect = 'index.php';
            if (!empty($_POST['redirect'])) {
                $target = trim((string)$_POST['redirect']);
                // Prevent open redirect attacks (allow only relative paths)
                if (str_starts_with($target, '/') || !str_contains($target, '://')) {
                    $cleanTarget = basename($target);
                    if (in_array($cleanTarget, ['index.php', 'settings.php'], true)) {
                        $redirect = $cleanTarget;
                    }
                }
            }

            header("Location: {$redirect}");
            exit;
        } else {
            $errorMessage = 'Invalid username or password.';
        }
    }
}

$csrfToken = get_csrf_token();
$redirectTarget = htmlspecialchars($_GET['redirect'] ?? '', ENT_QUOTES, 'UTF-8');
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Teacher Login - TabMonitor</title>
  <link rel="stylesheet" href="style.css">
</head>
<body class="login-body">

  <div class="login-card">
    <div class="login-header">
      <div class="brand" style="justify-content: center; font-size: 1.6rem;">
        <span class="brand-icon">📱</span> TabMonitor
      </div>
      <h1 class="login-title">Teacher Portal</h1>
      <p class="login-subtitle">Sign in to monitor tablet battery levels & status</p>
    </div>

    <?php if ($successMessage): ?>
      <div class="alert alert-success">
        <?= htmlspecialchars($successMessage, ENT_QUOTES, 'UTF-8') ?>
      </div>
    <?php endif; ?>

    <?php if ($errorMessage): ?>
      <div class="alert alert-danger">
        <?= htmlspecialchars($errorMessage, ENT_QUOTES, 'UTF-8') ?>
      </div>
    <?php endif; ?>

    <form method="POST" action="login.php">
      <input type="hidden" name="csrf_token" value="<?= htmlspecialchars($csrfToken, ENT_QUOTES, 'UTF-8') ?>">
      <input type="hidden" name="redirect" value="<?= $redirectTarget ?>">

      <div class="form-group">
        <label class="form-label" for="username">Username</label>
        <input 
          type="text" 
          id="username" 
          name="username" 
          class="form-input" 
          required 
          autofocus 
          value="<?= htmlspecialchars($_POST['username'] ?? '', ENT_QUOTES, 'UTF-8') ?>"
          placeholder="e.g. teacher"
        >
      </div>

      <div class="form-group">
        <label class="form-label" for="password">Password</label>
        <input 
          type="password" 
          id="password" 
          name="password" 
          class="form-input" 
          required 
          placeholder="••••••••"
        >
      </div>

      <button type="submit" class="btn-primary">Sign In</button>
    </form>

    <div class="login-hint">
      <strong>Initial Setup:</strong> Default login is <code>teacher</code> / <code>teacher123</code>. You can change your password anytime under Settings.
    </div>
  </div>

</body>
</html>
