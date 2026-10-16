# TabMonitor (Phase 1 & Phase 2)

A lightweight, secure PHP 8.x + MySQL backend and web dashboard designed specifically for **Webglobe shared hosting** (and standard LAMP / cPanel environments). TabMonitor enables schools to monitor tablet battery levels and charging statuses across classrooms without heavy frameworks, Node.js, Docker, or complex architectures.

---

## 📁 Repository Structure

TabMonitor consists strictly of straightforward, production-ready files:

```
tabmonitor/
├── install.php   # Web installer: enters DB login & creates all tab_* tables automatically
├── api.php       # Phase 1: Central REST API controller (tablets & teacher API)
├── db.php        # Phase 1: Secure PDO connection, settings & auth session helpers
├── config.php    # Phase 1: Database credentials, API secrets & app settings
├── schema.sql    # Phase 1 & 2: Database tables (tab_settings, tab_devices, tab_battery_reports, tab_teachers)
├── index.php     # Phase 2: Teacher web dashboard (tablets, battery status, search)
├── login.php     # Phase 2: Secure teacher sign-in with password_verify & CSRF
├── logout.php    # Phase 2: Secure session termination
├── settings.php  # Phase 2: Teacher settings (0-100% threshold, password change)
├── style.css     # Phase 2: Clean, responsive, zero-dependency modern styles
└── README.md     # Full documentation, setup instructions & API reference
```

---

## 🔒 Security Architecture

TabMonitor enforces strict access separation between student tablets and teachers:

| Role / Client | Authentication Method | Permitted Endpoints & Pages | Denied Endpoints |
|---------------|-----------------------|-----------------------------|------------------|
| **Tablet** | `X-API-Key: <tablet_key>` or `Authorization: Bearer <tablet_key>` | `api.php?action=test`, `api.php?action=report` | `action=devices`, `action=settings`, `action=register-device` (**403 Forbidden**) |
| **Teacher API** | `X-Teacher-Key: <teacher_key>` or `Authorization: Bearer <teacher_key>` | All `api.php` actions (`test`, `devices`, `settings`, `register-device`) | N/A |
| **Teacher Web** | PHP Session (`session_regenerate_id`, CSRF token, `password_verify`) | `index.php`, `settings.php`, `logout.php` | N/A |
| **Unauthenticated** | None or Invalid | `login.php`, `install.php` | All protected endpoints (**401 Unauthorized** / Redirect) |

### Security Guarantees
- **Strict Role Separation**: The shared tablet API key **never** grants teacher access or settings modification. Passing the tablet key to a teacher endpoint explicitly returns `403 Forbidden`.
- **PDO Prepared Statements**: 100% of SQL queries use parameterized prepared statements with native preparation (`PDO::ATTR_EMULATE_PREPARES => false`), completely preventing SQL injection.
- **Table Prefix Isolation**: All tables are isolated with the `tab_` prefix (`tab_settings`, `tab_devices`, `tab_battery_reports`, `tab_teachers`), making TabMonitor 100% safe to share a database with other applications on Webglobe.
- **Session Security & Fixation Prevention**: Sessions use `HttpOnly`, `SameSite=Lax`, HTTPS cookies in production, automatic ID regeneration upon login (`session_regenerate_id(true)`), and 2-hour inactivity timeouts.
- **Password Hashing**: Passwords are saved with standard `password_hash()` (Bcrypt/Argon2) and verified using timing-safe `password_verify()`.
- **CSRF Protection**: All state-changing forms (`login.php`, `settings.php`) generate cryptographically secure, session-bound CSRF tokens verified with `hash_equals()`.
- **HTTPS Enforcement**: In production (`'enforce_https' => true`), unencrypted plain HTTP requests are rejected with `403 Forbidden`.
- **Pre-registered Tablets**: Only pre-registered and active tablet IDs can submit reports or test connection. Unregistered devices are rejected with `403 Forbidden`.

---

## 💻 Teacher Web Dashboard (Phase 2)

The web dashboard is accessed via web browser at `index.php`:

### Features:
1. **At-a-Glance Metrics**:
   - Total registered tablets, Online count, Offline count, and Low Battery alert counter.
2. **Dedicated Low Battery Section**:
   - Prominently displays tablets at or below the server-configured threshold at the very top.
   - Shows tablet name, assigned classroom, battery percentage with red progress bar, charging status, and last contact.
3. **All Registered Tablets Table**:
   - Device ID badge (`TAB-001`, `TAB-002`, etc.)
   - Device Name & Assigned Room
   - Graphical battery level bar (green $> 40\%$, amber $21-40\%$, red $\le$ threshold)
   - Real-time charging status (⚡ Charging / 🔋 On Battery)
   - Last contact relative time ("2 mins ago") and exact timestamp
   - Online / Offline status pill (based on 30-minute offline timeout)
4. **Real-Time Client-Side Search**:
   - Instant search filter by Device ID, Name, or Room as you type.
5. **Quick Filters & Auto-Refresh**:
   - Filter by All, Low Battery, Offline, or Charging with one click.
   - Optional 30-second auto-refresh toggle for persistent classroom wall monitors.
6. **Teacher Settings (`settings.php`)**:
   - Configurable battery alert threshold from **0% to 100%** with live slider and number input.
   - Password change form with current password verification.
   - System and database information panel.

---

## 🚀 Setup & Deployment on Webglobe Shared Hosting

### Method A: Fast Setup via Web Installer (`install.php`) — Recommended!

1. Create a MySQL database in your Webglobe panel (or use an existing one).
2. Upload the TabMonitor files to your hosting directory (e.g. `public_html/tabmonitor`).
3. Open `https://yourdomain.com/tabmonitor/install.php` in your browser.
4. Enter your MySQL database login details (Host, Database Name, User, Password).
5. Click **Connect & Create Tables (tab_*)**.
6. `install.php` automatically:
   - Tests the database connection.
   - Creates all tables with the prefix `tab_`:
     - `tab_settings`
     - `tab_devices`
     - `tab_battery_reports`
     - `tab_teachers`
   - Seeds default tablets (`TAB-001` through `TAB-005`), default threshold (`20%`), and teacher account.
   - Writes the verified credentials safely to `config.php`.
7. Log in immediately via `login.php` with username `teacher` and your configured password.
8. Delete `install.php` after installation for production security.

---

### Method B: Manual Setup via phpMyAdmin & config.php

1. Create a database in your Webglobe administration panel.
2. Open **phpMyAdmin**, import `schema.sql`. (All tables will be created with `tab_` prefix).
3. Open `config.php` and fill in your DB credentials:
```php
'db' => [
    'host'        => 'localhost',             // Webglobe MySQL host
    'port'        => 3306,
    'unix_socket' => null,
    'name'        => 'your_webglobe_dbname',
    'user'        => 'your_webglobe_dbuser',
    'pass'        => 'your_strong_db_password',
    'prefix'      => 'tab_',                  // Table prefix
    'charset'     => 'utf8mb4',
],
```
4. Log in at `https://yourdomain.com/login.php` using `teacher` / `teacher123`.

---

## 📡 API Reference (Phase 1)

All requests and responses use `application/json; charset=utf-8`.

Routing works identically with query parameters (`api.php?action=report`) or PATH_INFO (`api.php/report`).

---

### 1. Test Connection
Tablets or teachers verify connectivity and credentials.

- **Method**: `GET` or `POST`
- **URL**: `/api.php?action=test`
- **Headers**: `X-API-Key: <tablet_key>`

#### Example Request:
```bash
curl -X GET "https://yourdomain.com/api.php?action=test&device_id=TAB-001" \
  -H "X-API-Key: secret-tablet-key-change-in-production"
```

#### Example Response (200 OK):
```json
{
  "status": "ok",
  "message": "TabMonitor API connection successful.",
  "authenticated_as": "tablet",
  "server_time": "2026-10-16T17:45:00+02:00",
  "battery_threshold": 20,
  "device": {
    "device_id": "TAB-001",
    "name": "Tablet 01",
    "assigned_room": "Classroom 101",
    "is_active": true
  }
}
```

---

### 2. Submit Battery Report
Tablets send periodic battery reports. Validates pre-registration, records report, updates snapshot, and evaluates against threshold.

- **Method**: `POST`
- **URL**: `/api.php?action=report`
- **Headers**:
  - `Content-Type: application/json`
  - `X-API-Key: <tablet_key>`
- **Request Body**:
```json
{
  "device_id": "TAB-001",
  "battery_level": 15,
  "is_charging": false
}
```

#### Example Request:
```bash
curl -X POST "https://yourdomain.com/api.php?action=report" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: secret-tablet-key-change-in-production" \
  -d '{"device_id": "TAB-001", "battery_level": 15, "is_charging": false}'
```

#### Example Response (200 OK):
```json
{
  "status": "ok",
  "message": "Battery report received successfully.",
  "device_id": "TAB-001",
  "battery_level": 15,
  "is_charging": false,
  "is_low_battery": true,
  "threshold": 20,
  "reported_at": "2026-10-16 17:45:10"
}
```

---

### 3. Retrieve Device Status (Teacher API)
Teachers retrieve status across all tablets programmatically.

- **Method**: `GET`
- **URL**: `/api.php?action=devices`
- **Headers**: `X-Teacher-Key: <teacher_key>`
- **Security Check**: Tablet key returns `403 Forbidden`.

#### Example Request:
```bash
curl -X GET "https://yourdomain.com/api.php?action=devices" \
  -H "X-Teacher-Key: secret-teacher-key-change-in-production"
```

---

### 4. Manage Settings via API (Teacher Only)
- **View Settings**: `GET /api.php?action=settings` (`X-Teacher-Key`)
- **Update Threshold**: `POST /api.php?action=settings` with `{"low_battery_threshold": 25}`
- **Security Check**: Tablet key returns `403 Forbidden`.

---

### 5. Pre-register Tablet via API (Teacher Only)
- **Register/Update**: `POST /api.php?action=register-device` (`X-Teacher-Key`) with:
```json
{
  "device_id": "TAB-006",
  "name": "Tablet 06",
  "assigned_room": "Art Studio",
  "is_active": true
}
```

---

## 🧪 Testing Both Phases Locally

Run PHP's built-in web server:
```bash
php -S 127.0.0.1:8000
```

1. **Teacher Web Dashboard**:
   - Open `http://127.0.0.1:8000/index.php` in your browser (redirects to `login.php`).
   - Sign in with `teacher` / `teacher123`.
   - View devices, test the real-time search filter, and adjust the threshold in `settings.php`.
2. **Tablet API**:
   - Send reports using curl:
   ```bash
   curl -X POST "http://127.0.0.1:8000/api.php?action=report" \
     -H "Content-Type: application/json" \
     -H "X-API-Key: secret-tablet-key-change-in-production" \
     -d '{"device_id":"TAB-001","battery_level":12,"is_charging":false}'
   ```
   - Refresh the dashboard: `TAB-001` immediately appears in the **Low Battery Tablets** alert section at the top!
