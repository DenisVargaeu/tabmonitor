# 🚀 TabMonitor v2.1.0 — Release Notes

> **Version:** `v2.1.0` (Web Admin & REST API) / `2.1.0+2` (Android Client App)  
> **Release Date:** October 17, 2026  
> **Target Platforms:** Android 15 (API 35) & PHP 8.1+ / Webglobe shared hosting  

---

## 🌟 Key Highlights of this Release

### 🎨 1. Material 3 Expressive UI & Brand Identity
* **Official Application Icon:** Both the Android mobile client and Web Admin received a complete brand overhaul. High-resolution mipmap densities (`mipmap-mdpi` through `xxxhdpi`) were generated from the master 1024×1024 px icon, along with a crisp browser `favicon.png`.
* **Canonical 7-Shape Morphing Loader:** Custom mathematical Bezier curve animation (`M3ShapeMorphLoader`) cycling smoothly across the 7 canonical Material 3 shapes:  
  *Circle $\to$ 4-Point Star $\to$ Rounded Rectangle $\to$ Oval $\to$ Pill $\to$ Cut Squircle $\to$ Clover*.
* **Flagship README.md:** Comprehensive technical documentation featuring an official banner, system architecture Mermaid diagrams, API references, and deployment guides.

---

### 📱 2. Android 15 Client App (`v2.1.0+2`)

* **1-Click Bulk Setup (`adresaserveru-tabletkey-tabid`):** New express configuration feature. In Step 1 or via the ⚡ AppBar button, technicians can enter or paste a single setup code (`server-key-tabid`). The app instantly parses and validates the fields, executes a live connection test with `M3ShapeMorphLoader`, and configures the tablet in 1 click!
* **Configurable Telemetry Reporting Interval:**
  * Configurable from **5 to 60 minutes** (default: 15 minutes).
  * Quick-select choice chips (`5 min`, `10 min`, `15 min [Predvolené]`, `30 min`, `60 min`) plus an interactive slider in the tablet Settings tab.
  * Dynamic live countdown timer on the Dashboard and native persistent Android notification update immediately to match the configured cadence.
  * WorkManager periodic background scheduler dynamically reschedules with Android battery-saving compliance.
  * Bidirectional sync: tablet synchronizes with server-side fleet interval pushed via API responses.
* **4-Step Interactive Setup Wizard (`SetupWizardScreen`):**
  1. **Connection Setup:** Server URL and shared API key configuration with real-time ping and authentication verification.
  2. **Permissions Checklist:** Interactive checklist with one-tap deep links directly into native Android 15 system settings (battery optimization whitelist, notifications permission, network state).
  3. **Device ID Registration:** Unique tablet identifier assignment (`TAB-001`, `XX-01`) with server whitelist validation.
  4. **Summary & First Report:** Configuration review and instant submission of the initial telemetry test ping.
* **Native Persistent Notification (`TabMonitorNotificationManager.kt`):**
  * Foreground notification displaying real-time battery percentage, charging state, and an active **countdown timer** to the next scheduled telemetry sync (`TabMonitor v2.1 • TAB-001 | 🔋 85% • Next sync in: 04:32`).
* **Multi-Functional Dashboard (`DashboardScreen`):**
  * Live battery gauge with dynamic color coding (green $>40\%$, amber $21-40\%$, red $\le$ threshold) and charging animations.
  * Historical sync log viewer (`SyncLogEntry`) with timestamps and HTTP status codes.
  * Manual sync trigger button with a live countdown timer.
  * **Bulk Setup Code Display:** Current tablet's bulk code is displayed with a 1-click copy button under Configuration.
  * **Copy Diagnostics:** One-click clipboard export containing complete system diagnostic details (hardware model, OS version, app version, network info, and server API version) for rapid IT troubleshooting.
  * **System & Version Info Card:** Displays local client version (`v2.1.0+2`) and dynamic server version resolved from API responses.
* **Device-Agnostic Telemetry:** Dynamic hardware queries via `device_info_plus` and `battery_plus` with zero hardcoded model strings (works seamlessly across Lenovo Tab K11, Samsung Galaxy Tab, Pixel Tablet, Xiaomi Pad, or phones).

---

### 💻 3. Teacher Web Dashboard (Phase 2)

* **Fleet Reporting Interval Control (`settings.php`):**
  * Teachers can configure the reporting frequency for the entire tablet fleet (5–60 min, default 15 min).
  * Quick-select preset buttons (`5m`, `10m`, `15m`, `30m`, `60m`) with interactive slider in web admin settings.
  * Persistent database setting (`tab_settings`) automatically transmitted to tablets on each sync.
* **Bulk Setup Code Generator & Modal (`index.php`):**
  * Added `⚡ Bulk Setup Kódy` toolbar button opening a centralized export modal with formatted setup strings (`adresaserveru-tabletkey-tabid`) for all tablets.
  * Added instant `⚡ Kód` copy buttons directly in the tablet inventory table for rapid on-site deployments.
* **Interactive Device Manager:** Register new tablet IDs (`+ Add Tablet`), toggle active/inactive status, or safely delete decommissioned devices directly through the browser without touching SQL.
* **Dedicated Low-Battery Alert Section:** Priority banner prominently displayed at the top of the dashboard highlighting tablets that have fallen below the configured threshold.
* **Dynamic Threshold Slider:** Teachers can configure the alert threshold from **0% to 100%** in `settings.php` with immediate database persistence and automatic propagation to tablets.
* **Instant Client-Side Search & Quick Filters:** Real-time search by Device ID, tablet name, or classroom, coupled with quick filter pills for Low Battery, Offline, and Charging devices.
* **Classroom Wallboard Mode:** 30-second auto-refresh toggle designed for unattended wall-mounted classroom monitors.

---

### ⚡ 4. REST API & Backend Architecture

* **Configurable Telemetry Cadence:**
  * Supported in `api.php?action=settings` via GET and POST for `report_interval_minutes` (5–120 min).
  * Included in `action=test` and `action=report` payloads (`'report_interval_minutes' => 15`) for automatic client synchronization.

* **Unified Version Protocol:** Every JSON API response contains `'version' => '2.1.0'` alongside the `X-TabMonitor-Version: 2.1.0` HTTP header.
* **Prefix Isolation (`tab_`):** 100% of tables (`tab_settings`, `tab_devices`, `tab_battery_reports`, `tab_teachers`) use the `tab_` prefix, guaranteeing zero naming collisions on shared Webglobe hosting environments.
* **Strict Role-Based Security:** Complete privilege separation between tablets (`X-API-Key`) and administrators (`X-Teacher-Key`). Tablet keys attempting to access administrative endpoints are rejected with `403 Forbidden`.
* **Automated Web Installer (`install.php`):** Browser-based setup wizard that verifies database credentials, executes migrations, creates tables, seeds initial data, and generates `config.php`.

---

## 📦 Release Artifacts & Built Packages

| Artifact | Description | Size / Status |
|---|---|---|
| `app/build/app/outputs/flutter-apk/app-release.apk` | Production release APK for Android 15 tablets | ~22.8 MB (Verified) |
| `install.php` | Web installer for Webglobe and LAMP hosting | Ready |
| `schema.sql` | Full MySQL DDL schema with `tab_` prefix isolation | Ready |
| `README.md` | Flagship technical guide and documentation | Updated |

---

## 🛠️ Installation & Upgrade Instructions

### Webglobe Shared Hosting:
1. Upload the project files to your web root (e.g., `public_html/tabmonitor`).
2. Navigate to `https://yourdomain.com/install.php` in your browser.
3. Enter your MySQL database credentials and click **Connect & Create Tables**.
4. Sign in at `login.php` using the default credentials (`teacher` / `teacher123`) and update your password immediately in Settings.
5. Delete `install.php` for production security.

### Android Tablets:
1. Install the release APK via ADB:
   ```bash
   adb install -r app/build/app/outputs/flutter-apk/app-release.apk
   ```
2. Launch **TabMonitor**, complete the 4-step wizard, and grant the **Ignore Battery Optimization** permission to ensure continuous background reporting on Android 15.
