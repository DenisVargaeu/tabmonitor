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

  /// Formats this configuration as a single bulk setup string.
  /// Syntax: adresaserveru-tabletkey-tabid
  String get bulkSetupCode {
    return '${serverUrl.trim()}-${apiKey.trim()}-${deviceId.trim()}';
  }

  /// Parses a bulk setup string in syntax:
  /// adresaserveru-tabletkey-tabid
  ///
  /// Examples:
  /// - https://school.sk/tabmonitor-secretkey123-TAB01
  /// - http://192.168.1.10:8080-secretkey123-TAB-01
  /// - https://my-school.sk/tabmonitor-secretkey123-TAB-01
  /// - 192.168.1.50:8080-5sadd24c4sdf4sd2v12fb42dfg45f2fdg4fdg24fg45f-XX-01
  static DeviceConfig? parseBulkSetupCode(String rawCode) {
    final s = rawCode.trim();
    if (s.isEmpty) return null;

    // Optional secondary fallback delimiters
    if (s.contains('|') && s.split('|').length == 3) {
      final p = s.split('|');
      return DeviceConfig(
        serverUrl: p[0].trim(),
        apiKey: p[1].trim(),
        deviceId: p[2].trim(),
      );
    }
    if (s.contains(';') && s.split(';').length == 3) {
      final p = s.split(';');
      return DeviceConfig(
        serverUrl: p[0].trim(),
        apiKey: p[1].trim(),
        deviceId: p[2].trim(),
      );
    }

    final parts = s.split('-');
    if (parts.length < 3) return null;

    if (parts.length == 3) {
      final url = parts[0].trim();
      final key = parts[1].trim();
      final id = parts[2].trim();
      if (url.isNotEmpty && key.isNotEmpty && id.isNotEmpty) {
        return DeviceConfig(serverUrl: url, apiKey: key, deviceId: id);
      }
      return null;
    }

    // When there are more than 3 parts (due to hyphens in URL domain or tablet ID like TAB-01):
    // Evaluate candidate split points between URL, Key, and Device ID.
    int bestScore = -999;
    String bestUrl = '';
    String bestKey = '';
    String bestId = '';

    for (int i = 1; i < parts.length - 1; i++) {
      final url = parts.sublist(0, i).join('-').trim();
      final key = parts[i].trim();
      final devId = parts.sublist(i + 1).join('-').trim();

      int score = 0;
      final lowerUrl = url.toLowerCase();
      if (lowerUrl.startsWith('http://') || lowerUrl.startsWith('https://')) {
        score += 10;
      }
      if (url.contains('.') || url.contains(':') || url.contains('/')) {
        score += 5;
      }
      if (!key.contains('/') && !key.contains(':') && !key.contains(' ')) {
        score += 5;
      }
      if (key.length >= 8) {
        score += 5;
      }
      if (devId.length <= 32 && !devId.contains('/') && !devId.contains(':')) {
        score += 5;
      }
      if (devId.contains(RegExp(r'\d'))) {
        score += 3;
      }

      if (score > bestScore) {
        bestScore = score;
        bestUrl = url;
        bestKey = key;
        bestId = devId;
      }
    }

    if (bestUrl.isNotEmpty && bestKey.isNotEmpty && bestId.isNotEmpty) {
      return DeviceConfig(
        serverUrl: bestUrl,
        apiKey: bestKey,
        deviceId: bestId,
      );
    }

    return null;
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
