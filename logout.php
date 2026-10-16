<?php
declare(strict_types=1);

/**
 * TabMonitor - Logout (Phase 2)
 *
 * Securely destroys session data, unsets session cookies,
 * and redirects to the login screen.
 */

require_once __DIR__ . '/db.php';
$config = require __DIR__ . '/config.php';

start_secure_session($config);

// Clear all session variables
$_SESSION = [];

// Delete the session cookie if present
if (ini_get('session.use_cookies')) {
    $params = session_get_cookie_params();
    setcookie(
        session_name(),
        '',
        time() - 42000,
        $params['path'],
        $params['domain'],
        $params['secure'],
        $params['httponly']
    );
}

// Destroy session on server
session_destroy();

// Redirect with confirmation
header('Location: login.php?logged_out=1');
exit;
