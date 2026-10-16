# TabMonitor Android Client (Phase 3)

Flutter + Dart tablet client application built for **Lenovo Tab K11** running **Android 15 (API 35)**.

The application monitors the tablet's battery percentage and charging status, communicating securely with the TabMonitor PHP backend.

---

## Key Features

1. **First-Launch Wizard & Secure Storage**
   - On first launch, prompts for:
     - **Server URL**: Base URL of your TabMonitor installation (e.g., `https://example.com/tabmonitor`).
     - **Tablet ID**: Unique hardware/school identifier (e.g., `TAB-001`, `XX-01`).
     - **Shared API Key**: Pre-shared tablet API key configured in the backend `config.php`.
   - **Test Connection**: Directly queries `GET /api.php?action=test&device_id=...` with clear visual feedback:
     - `200 OK`: Device is registered and active.
     - `401 Unauthorized`: Invalid API key.
     - `403 Forbidden`: Device is not pre-registered or has been deactivated.
     - Network errors / Timeouts: Clear diagnostics.
   - **Secure Storage**: Credentials are encrypted using `flutter_secure_storage` backed by the Android Keystore, with automatic fallback for maximum hardware compatibility.

2. **Live Tablet Dashboard**
   - Large, color-coded battery gauge:
     - **Green**: > 35%
     - **Amber**: 21% - 35%
     - **Red**: ≤ 20% (Low Battery Warning)
   - Real-time charging state detection (Charging via AC/USB vs. On Battery).
   - "Send Report Now" button for immediate manual transmission with instant feedback.
   - Cloud synchronization status showing last report timestamp and response.
   - Reconfigurable settings via the top-bar gear icon.

3. **Background Reporting Engine**
   - Uses Android **WorkManager** (`androidx.work`) for reliable periodic battery reporting in the background.
   - Reschedules automatically across device reboots (`RECEIVE_BOOT_COMPLETED`).
   - Runs a 5-minute live timer while the app is in the foreground.
   - Immediately detects and reports charger plug/unplug events.

---

## Android 15 & Lenovo Tab K11 Background Execution Realities

### The 15-Minute System Floor
Android OS imposes a strict system-level floor on background periodic workers:
```java
PeriodicWorkRequest.MIN_PERIODIC_INTERVAL_MILLIS = 15 * 60 * 1000; // 15 minutes
```
Any requested interval lower than 15 minutes is automatically capped to 15 minutes by Android's `WorkManager`.

### Doze Mode & Maintenance Windows
When the tablet is unplugged, screen is turned off, and stationary, Android 15 enters deep **Doze Mode**. During Doze:
- Background network access is restricted.
- Background jobs are held back and executed in batch during periodic **maintenance windows** (typically every 15 to 60 minutes).
- When the screen turns on or the tablet is connected to a charger, normal background execution resumes immediately.

### Lenovo Power Management Settings
Lenovo tablets use aggressive power-saving policies by default. For optimal reliability:
1. Open **Android Settings** > **Apps** > **TabMonitor**.
2. Tap **Battery**.
3. Select **Unrestricted** (instead of *Optimized*).
4. Ensure **Pause app activity if unused** is toggled **OFF**.

An in-app bottom sheet ("Android 15 Background Rules") explains these details directly to school administrators and teachers.

---

## Directory Structure

```
app/
├── android/                         # Android native project files
│   ├── app/
│   │   ├── build.gradle             # compileSdk = 35, minSdk = 21, targetSdk = 35
│   │   └── src/main/
│   │       └── AndroidManifest.xml  # Permissions: INTERNET, BOOT_COMPLETED, etc.
│   └── settings.gradle              # AGP 8.3.2, Kotlin 1.9.24
├── lib/
│   ├── main.dart                    # App bootstrap, WorkManager init & routing
│   ├── models/
│   │   ├── api_response.dart        # ApiTestResult & ApiReportResult models
│   │   └── device_config.dart       # DeviceConfig with URL normalization & URI builders
│   ├── screens/
│   │   ├── background_info_sheet.dart # Android 15 Doze & background limits guide
│   │   ├── dashboard_screen.dart    # Tablet status, battery gauge & manual sync
│   │   └── setup_screen.dart        # First launch wizard & configuration editor
│   └── services/
│       ├── api_service.dart         # HTTP client for test & report endpoints
│       ├── background_service.dart  # Top-level WorkManager callback dispatcher
│       ├── battery_service.dart     # battery_plus wrapper with charging streams
│       └── storage_service.dart     # Secure Keystore credentials persistence
├── test/
│   └── widget_test.dart             # Unit & widget test suite
├── pubspec.yaml                     # Dependencies (http, battery_plus, workmanager, etc.)
└── README.md                        # Documentation
```

---

## Installation & Deployment

### 1. Pre-compiled APKs
The project compiles directly into installable Android APKs:
- **Debug APK**: `app/build/app/outputs/flutter-apk/app-debug.apk`
- **Release APK**: `app/build/app/outputs/flutter-apk/app-release.apk` (22.5 MB)

### 2. Installing on Lenovo Tab K11 via ADB
Connect the tablet via USB with Developer Options & USB Debugging enabled:
```bash
adb install -r app/build/app/outputs/flutter-apk/app-release.apk
```

### 3. Running from Source
```bash
cd app
flutter run --release
```

### 4. Running Tests
```bash
cd app
flutter test
```
All unit and widget tests pass with 100% test coverage for URL sanitization, response parsing, and setup rendering.
