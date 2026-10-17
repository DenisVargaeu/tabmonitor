import 'dart:convert';

/// Represents an individual synchronization log entry for telemetry and diagnostics.
class SyncLogEntry {
  final String id;
  final DateTime timestamp;
  final int batteryLevel;
  final bool isCharging;
  final bool isSuccess;
  final String message;
  final int? statusCode;
  final int? latencyMs;

  const SyncLogEntry({
    required this.id,
    required this.timestamp,
    required this.batteryLevel,
    required this.isCharging,
    required this.isSuccess,
    required this.message,
    this.statusCode,
    this.latencyMs,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'batteryLevel': batteryLevel,
      'isCharging': isCharging,
      'isSuccess': isSuccess,
      'message': message,
      'statusCode': statusCode,
      'latencyMs': latencyMs,
    };
  }

  factory SyncLogEntry.fromMap(Map<String, dynamic> map) {
    return SyncLogEntry(
      id: map['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      timestamp: DateTime.tryParse(map['timestamp']?.toString() ?? '') ?? DateTime.now(),
      batteryLevel: (map['batteryLevel'] as num?)?.toInt() ?? 100,
      isCharging: map['isCharging'] as bool? ?? false,
      isSuccess: map['isSuccess'] as bool? ?? false,
      message: map['message']?.toString() ?? '',
      statusCode: (map['statusCode'] as num?)?.toInt(),
      latencyMs: (map['latencyMs'] as num?)?.toInt(),
    );
  }

  String toJson() => jsonEncode(toMap());

  factory SyncLogEntry.fromJson(String source) =>
      SyncLogEntry.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
