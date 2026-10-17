import 'package:flutter/services.dart';

/// Service interfacing with native Android platform methods for checking
/// and configuring system permissions, battery optimizations, notifications, and device details.
class SystemSettingsService {
  static const MethodChannel _channel = MethodChannel('com.tabmonitor.app/settings');

  /// Check whether the app is whitelisted from battery optimizations.
  Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      final res = await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Open Android intent to request battery optimization exemption.
  Future<void> requestIgnoreBatteryOptimizations() async {
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (_) {}
  }

  /// Check whether notifications are enabled for this app.
  Future<bool> areNotificationsEnabled() async {
    try {
      final res = await _channel.invokeMethod<bool>('areNotificationsEnabled');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Open the app's notification settings screen.
  Future<void> openNotificationSettings() async {
    try {
      await _channel.invokeMethod('openNotificationSettings');
    } catch (_) {}
  }

  /// Open Android App Details (Settings > Apps > TabMonitor).
  Future<void> openAppDetailsSettings() async {
    try {
      await _channel.invokeMethod('openAppDetailsSettings');
    } catch (_) {}
  }

  /// Open Android Wi-Fi / Network settings.
  Future<void> openWifiSettings() async {
    try {
      await _channel.invokeMethod('openWifiSettings');
    } catch (_) {}
  }

  /// Check if tablet currently has an active Internet connection.
  Future<bool> isNetworkConnected() async {
    try {
      final res = await _channel.invokeMethod<bool>('isNetworkConnected');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Show or update the ongoing status notification with connection state and countdown.
  Future<void> showStatusNotification({
    required String deviceId,
    required int batteryLevel,
    required bool isCharging,
    required bool isOnline,
    required String statusMessage,
    required int nextReportSeconds,
  }) async {
    try {
      await _channel.invokeMethod('showStatusNotification', {
        'deviceId': deviceId,
        'batteryLevel': batteryLevel,
        'isCharging': isCharging,
        'isOnline': isOnline,
        'statusMessage': statusMessage,
        'nextReportSeconds': nextReportSeconds,
      });
    } catch (_) {}
  }

  /// Cancel the ongoing status notification.
  Future<void> cancelStatusNotification() async {
    try {
      await _channel.invokeMethod('cancelStatusNotification');
    } catch (_) {}
  }

  /// Get real Android device info (Model, Manufacturer, Brand, Android Release, SDK).
  Future<Map<String, dynamic>> getDeviceInfo() async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('getDeviceInfo');
      return res ?? {};
    } catch (_) {
      return {};
    }
  }
}
