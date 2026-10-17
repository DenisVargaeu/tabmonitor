import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device_config.dart';
import '../models/sync_log_entry.dart';

/// Storage service providing secure persistence for credentials, settings, and telemetry logs.
class StorageService {
  static const _keyServerUrl = 'tm_server_url';
  static const _keyApiKey = 'tm_api_key';
  static const _keyDeviceId = 'tm_device_id';
  static const _keyLastReportTime = 'tm_last_report_time';
  static const _keyLastReportBattery = 'tm_last_report_battery';
  static const _keyLastReportCharging = 'tm_last_report_charging';
  static const _keyLastReportSuccess = 'tm_last_report_success';
  static const _keyLastReportMessage = 'tm_last_report_message';
  static const _keySyncLogs = 'tm_sync_logs';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      resetOnError: true,
    ),
  );

  /// Load device configuration from secure storage, falling back to SharedPreferences if needed.
  Future<DeviceConfig?> loadConfig() async {
    try {
      final url = await _secureStorage.read(key: _keyServerUrl);
      final key = await _secureStorage.read(key: _keyApiKey);
      final id = await _secureStorage.read(key: _keyDeviceId);

      if (url != null && key != null && id != null && url.isNotEmpty) {
        return DeviceConfig(
          serverUrl: url,
          apiKey: key,
          deviceId: id,
        );
      }
    } catch (e) {
      debugPrint('SecureStorage read failed, checking SharedPreferences: $e');
    }

    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_keyServerUrl);
    final key = prefs.getString(_keyApiKey);
    final id = prefs.getString(_keyDeviceId);

    if (url != null && key != null && id != null && url.isNotEmpty) {
      return DeviceConfig(
        serverUrl: url,
        apiKey: key,
        deviceId: id,
      );
    }
    return null;
  }

  /// Save device configuration securely.
  Future<void> saveConfig(DeviceConfig config) async {
    try {
      await _secureStorage.write(key: _keyServerUrl, value: config.serverUrl.trim());
      await _secureStorage.write(key: _keyApiKey, value: config.apiKey.trim());
      await _secureStorage.write(key: _keyDeviceId, value: config.deviceId.trim());
    } catch (e) {
      debugPrint('SecureStorage write error: $e');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyServerUrl, config.serverUrl.trim());
    await prefs.setString(_keyApiKey, config.apiKey.trim());
    await prefs.setString(_keyDeviceId, config.deviceId.trim());
  }

  /// Clear stored credentials (e.g. on complete reset).
  Future<void> clearConfig() async {
    try {
      await _secureStorage.delete(key: _keyServerUrl);
      await _secureStorage.delete(key: _keyApiKey);
      await _secureStorage.delete(key: _keyDeviceId);
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyServerUrl);
    await prefs.remove(_keyApiKey);
    await prefs.remove(_keyDeviceId);
  }

  /// Record metadata about the most recent battery report.
  Future<void> recordReportResult({
    required int batteryLevel,
    required bool isCharging,
    required bool success,
    required String message,
    DateTime? timestamp,
    int? statusCode,
    int? latencyMs,
  }) async {
    final now = timestamp ?? DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    final time = now.toIso8601String();
    await prefs.setString(_keyLastReportTime, time);
    await prefs.setInt(_keyLastReportBattery, batteryLevel);
    await prefs.setBool(_keyLastReportCharging, isCharging);
    await prefs.setBool(_keyLastReportSuccess, success);
    await prefs.setString(_keyLastReportMessage, message);

    await addSyncLog(SyncLogEntry(
      id: '${now.millisecondsSinceEpoch}',
      timestamp: now,
      batteryLevel: batteryLevel,
      isCharging: isCharging,
      isSuccess: success,
      message: message,
      statusCode: statusCode,
      latencyMs: latencyMs,
    ));
  }

  /// Retrieve last report metadata.
  Future<Map<String, dynamic>> getLastReportInfo() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'timestamp': prefs.getString(_keyLastReportTime),
      'battery': prefs.getInt(_keyLastReportBattery),
      'charging': prefs.getBool(_keyLastReportCharging),
      'success': prefs.getBool(_keyLastReportSuccess),
      'message': prefs.getString(_keyLastReportMessage),
    };
  }

  /// Add a log entry to recent sync history (keeps up to 50 most recent).
  Future<void> addSyncLog(SyncLogEntry entry) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(_keySyncLogs) ?? [];
      rawList.insert(0, entry.toJson());
      if (rawList.length > 50) {
        rawList.removeRange(50, rawList.length);
      }
      await prefs.setStringList(_keySyncLogs, rawList);
    } catch (e) {
      debugPrint('Error storing sync log: $e');
    }
  }

  /// Get the list of recent sync logs.
  Future<List<SyncLogEntry>> getSyncLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(_keySyncLogs) ?? [];
      return rawList.map((str) => SyncLogEntry.fromJson(str)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Clear all stored sync logs.
  Future<void> clearSyncLogs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keySyncLogs);
  }
}
