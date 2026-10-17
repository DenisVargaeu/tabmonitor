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
  /// Default interval is 15 minutes, with option to go down to 5 minutes.
  /// Android WorkManager enforces a 15-minute floor for background workers,
  /// while foreground and persistent notification timers trigger at the exact configured interval.
  Future<void> schedulePeriodicReports({int? intervalMinutes}) async {
    try {
      final storage = StorageService();
      final minutes = intervalMinutes ?? await storage.loadReportInterval();
      final effectiveMinutes = minutes.clamp(5, 120);
      final workManagerMinutes = effectiveMinutes < 15 ? 15 : effectiveMinutes;

      await Workmanager().registerPeriodicTask(
        kBackgroundReportTask,
        kBackgroundReportTask,
        frequency: Duration(minutes: workManagerMinutes),
        initialDelay: const Duration(seconds: 30),
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );
      debugPrint('[BackgroundService] Periodic reporting scheduled ($effectiveMinutes min configured, WorkManager: $workManagerMinutes min).');
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
