import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';

/// Service for monitoring device battery level and charging state.
class BatteryService {
  final Battery _battery;

  BatteryService({Battery? battery}) : _battery = battery ?? Battery();

  /// Retrieve current battery level as a percentage (0 - 100).
  Future<int> getBatteryLevel() async {
    try {
      final level = await _battery.batteryLevel;
      return level.clamp(0, 100);
    } catch (e) {
      debugPrint('Error querying battery level: $e');
      return 100; // Safe fallback
    }
  }

  /// Retrieve current charging status.
  Future<bool> isCharging() async {
    try {
      final state = await _battery.batteryState;
      return state == BatteryState.charging || state == BatteryState.full;
    } catch (e) {
      debugPrint('Error querying battery state: $e');
      return false;
    }
  }

  /// Stream of battery charging changes.
  Stream<bool> get onChargingChanged {
    return _battery.onBatteryStateChanged.map((state) {
      return state == BatteryState.charging || state == BatteryState.full;
    }).handleError((error) {
      debugPrint('Battery state stream error: $error');
      return false;
    });
  }
}
