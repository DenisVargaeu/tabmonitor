/// Configuration model for TabMonitor client.
class DeviceConfig {
  final String serverUrl;
  final String apiKey;
  final String deviceId;

  const DeviceConfig({
    required this.serverUrl,
    required this.apiKey,
    required this.deviceId,
  });

  /// Normalize URL by stripping trailing slashes and ensuring a valid scheme.
  String get normalizedUrl {
    var trimmed = serverUrl.trim();
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      trimmed = 'https://$trimmed';
    }
    return trimmed;
  }

  /// URL for the Phase 1 test connection endpoint.
  Uri get testConnectionUri {
    final base = normalizedUrl;
    final cleanId = Uri.encodeComponent(deviceId.trim());
    final cleanKey = Uri.encodeComponent(apiKey.trim());
    return Uri.parse('$base/api.php?action=test&device_id=$cleanId&api_key=$cleanKey');
  }

  /// URL for the Phase 1 battery report endpoint.
  Uri get reportUri {
    final base = normalizedUrl;
    final cleanKey = Uri.encodeComponent(apiKey.trim());
    return Uri.parse('$base/api.php?action=report&api_key=$cleanKey');
  }

  /// Validate if configuration has minimum valid fields.
  bool get isValid {
    return serverUrl.trim().isNotEmpty &&
        apiKey.trim().isNotEmpty &&
        deviceId.trim().isNotEmpty;
  }

  Map<String, String> toMap() {
    return {
      'server_url': serverUrl.trim(),
      'api_key': apiKey.trim(),
      'device_id': deviceId.trim(),
    };
  }

  factory DeviceConfig.fromMap(Map<String, String?> map) {
    return DeviceConfig(
      serverUrl: (map['server_url'] ?? '').trim(),
      apiKey: (map['api_key'] ?? '').trim(),
      deviceId: (map['device_id'] ?? '').trim(),
    );
  }

  DeviceConfig copyWith({
    String? serverUrl,
    String? apiKey,
    String? deviceId,
  }) {
    return DeviceConfig(
      serverUrl: serverUrl ?? this.serverUrl,
      apiKey: apiKey ?? this.apiKey,
      deviceId: deviceId ?? this.deviceId,
    );
  }
}
