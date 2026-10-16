import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'api_service.dart';
import 'battery_service.dart';
import 'storage_service.dart';

/// Periodic task unique identifier.
const String kBackgroundReportTask = 'com.tabmonitor.app.periodic_report';

/// Top-level callback dispatcher required by WorkManager.
/// Must be annotated with `@pragma('vm:entry-point')` so Flutter's AOT compiler doesn't tree-shake it.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    debugPrint('[WorkManager] Background task triggered: $taskName');

    try {
      final storage = StorageService();
      final config = await storage.loadConfig();

      if (config == null || !config.isValid) {
        debugPrint('[WorkManager] Skipping report: Device is not configured.');
        return Future.value(true);
      }

      final battery = BatteryService();
      final level = await battery.getBatteryLevel();
      final isCharging = await battery.isCharging();

      debugPrint('[WorkManager] Sending periodic report: ${config.deviceId}, $level%, charging: $isCharging');

      final api = ApiService();
      final result = await api.sendBatteryReport(
        config: config,
        batteryLevel: level,
        isCharging: isCharging,
      );

      await storage.recordReportResult(
        batteryLevel: level,
        isCharging: isCharging,
        success: result.isSuccess,
        message: result.message,
        timestamp: DateTime.now(),
      );

      debugPrint('[WorkManager] Report finished: success=${result.isSuccess}, msg=${result.message}');
      return Future.value(true);
    } catch (e, stack) {
      debugPrint('[WorkManager] Unhandled exception in background report: $e\n$stack');
      return Future.value(false); // Signal failure to trigger system backoff retry
    }
  });
}

/// Service managing periodic background task scheduling via Android WorkManager.
class BackgroundService {
  static final BackgroundService _instance = BackgroundService._internal();
  factory BackgroundService() => _instance;
  BackgroundService._internal();

  /// Initialize WorkManager. Call this once during app startup in main().
  Future<void> initialize() async {
    try {
      await Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: kDebugMode,
      );
      debugPrint('[BackgroundService] WorkManager initialized.');
    } catch (e) {
      debugPrint('[BackgroundService] Failed to initialize WorkManager: $e');
    }
  }

  /// Register periodic background reporting.
  /// Note on Android 15 / Lenovo Tab K11:
  /// Android enforces a hard minimum periodic interval of 15 minutes.
  /// While the screen is off and on battery (Doze mode), tasks may be grouped into
  /// maintenance windows. When the app is in the foreground, TabMonitor also runs
  /// a live 5-minute timer.
  Future<void> schedulePeriodicReports() async {
    try {
      await Workmanager().registerPeriodicTask(
        kBackgroundReportTask,
        kBackgroundReportTask,
        frequency: const Duration(minutes: 15), // Android minimum
        initialDelay: const Duration(seconds: 30),
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
        existingWorkPolicy: ExistingWorkPolicy.keep,
      );
      debugPrint('[BackgroundService] Periodic reporting scheduled (15 min interval).');
    } catch (e) {
      debugPrint('[BackgroundService] Error scheduling periodic reports: $e');
    }
  }

  /// Cancel any scheduled periodic reports (e.g., when resetting).
  Future<void> cancelAll() async {
    try {
      await Workmanager().cancelAll();
      debugPrint('[BackgroundService] All scheduled tasks cancelled.');
    } catch (e) {
      debugPrint('[BackgroundService] Error cancelling tasks: $e');
    }
  }
}
