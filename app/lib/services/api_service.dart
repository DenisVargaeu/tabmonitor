import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/api_response.dart';
import '../models/device_config.dart';

/// Service responsible for communicating with the Phase 1 PHP backend.
class ApiService {
  final http.Client _client;
  static const Duration timeoutDuration = Duration(seconds: 15);

  ApiService({http.Client? client}) : _client = client ?? http.Client();

  /// Headers to send with tablet requests.
  /// Sends both X-API-Key and Authorization Bearer header to ensure
  /// compatibility across various web server configurations (Apache, Nginx, LiteSpeed, Shared Hosting).
  Map<String, String> _buildHeaders(String apiKey, {bool isJson = false}) {
    final headers = <String, String>{
      'X-API-Key': apiKey,
      'Authorization': 'Bearer $apiKey',
      'Accept': 'application/json',
      'User-Agent': 'TabMonitor-Client/2.1.0 (Android; Tablet)',
      'X-Client-Version': '2.1.0',
    };
    if (isJson) {
      headers['Content-Type'] = 'application/json; charset=utf-8';
    }
    return headers;
  }

  /// Test connection and registration status for a tablet ID.
  Future<ApiTestResult> testConnection(DeviceConfig config) async {
    if (!config.isValid) {
      return ApiTestResult.failure(
        message: 'Configuration is incomplete. Server URL, API Key, and Tablet ID are required.',
      );
    }

    try {
      final uri = config.testConnectionUri;
      final headers = _buildHeaders(config.apiKey);

      final response = await _client.get(uri, headers: headers).timeout(timeoutDuration);

      Map<String, dynamic>? data;
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>?;
      } catch (_) {
        // Not JSON
      }

      final serverMessage = data != null && data['message'] != null
          ? data['message'].toString()
          : null;
      final serverVersion = data?['version']?.toString() ?? response.headers['x-tabmonitor-version'];
      final reportInterval = (data?['report_interval_minutes'] as num?)?.toInt();

      if (response.statusCode == 200 && data != null && data['status'] == 'ok') {
        final device = data['device'] as Map<String, dynamic>?;
        final name = device?['name']?.toString() ?? config.deviceId;
        final isActive = device?['is_active'] == true || device?['is_active'] == 1;

        return ApiTestResult.success(
          message: serverMessage ?? 'Tablet verified successfully.',
          statusCode: response.statusCode,
          deviceName: name,
          isActive: isActive,
          serverVersion: serverVersion,
          reportIntervalMinutes: reportInterval,
        );
      } else if (response.statusCode == 401) {
        return ApiTestResult.failure(
          message: serverMessage ?? 'Authentication failed: Invalid shared API key.',
          statusCode: 401,
          serverVersion: serverVersion,
        );
      } else if (response.statusCode == 403) {
        return ApiTestResult.failure(
          message: serverMessage ??
              'Tablet ID "${config.deviceId}" is not pre-registered or is inactive on the server. Please add it to the teacher dashboard first.',
          statusCode: 403,
          serverVersion: serverVersion,
        );
      } else if (response.statusCode == 404) {
        return ApiTestResult.failure(
          message: 'Endpoint not found (HTTP 404). Check if server URL points to the correct folder (e.g. /tabmonitor or root).',
          statusCode: 404,
        );
      } else {
        final msg = serverMessage ?? 'Server returned status ${response.statusCode}: ${response.reasonPhrase}';
        return ApiTestResult.failure(
          message: msg,
          statusCode: response.statusCode,
        );
      }
    } on TimeoutException {
      return ApiTestResult.failure(
        message: 'Connection timed out after ${timeoutDuration.inSeconds} seconds. Check server URL and network connection.',
      );
    } on SocketException catch (e) {
      return ApiTestResult.failure(
        message: 'Network unreachable (${e.osError?.message ?? e.message}). Ensure Wi-Fi/Internet is connected.',
      );
    } on HandshakeException catch (e) {
      return ApiTestResult.failure(
        message: 'SSL/TLS Handshake failed: ${e.message}. If using self-signed certificates or HTTP, verify server certificate.',
      );
    } catch (e) {
      return ApiTestResult.failure(
        message: 'Unexpected connection error: $e',
      );
    }
  }

  /// Send battery report to the Phase 1 backend.
  Future<ApiReportResult> sendBatteryReport({
    required DeviceConfig config,
    required int batteryLevel,
    required bool isCharging,
  }) async {
    if (!config.isValid) {
      return ApiReportResult.failure(
        message: 'Device is not configured yet.',
      );
    }

    try {
      final uri = config.reportUri;
      final headers = _buildHeaders(config.apiKey, isJson: true);
      final body = jsonEncode({
        'device_id': config.deviceId.trim(),
        'battery_level': batteryLevel.clamp(0, 100),
        'is_charging': isCharging,
      });

      final response = await _client.post(uri, headers: headers, body: body).timeout(timeoutDuration);

      Map<String, dynamic>? data;
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>?;
      } catch (_) {
        // Not JSON
      }

      final serverMessage = data != null && data['message'] != null
          ? data['message'].toString()
          : null;
      final serverVersion = data?['version']?.toString() ?? response.headers['x-tabmonitor-version'];
      final reportInterval = (data?['report_interval_minutes'] as num?)?.toInt();

      if (response.statusCode == 200 && data != null && data['status'] == 'ok') {
        final isLow = data['is_low_battery'] == true;
        final threshold = data['threshold'] as int?;

        return ApiReportResult.success(
          message: serverMessage ?? 'Battery report received successfully.',
          statusCode: 200,
          isLowBattery: isLow,
          threshold: threshold,
          serverVersion: serverVersion,
          reportIntervalMinutes: reportInterval,
        );
      } else if (response.statusCode == 401) {
        return ApiReportResult.failure(
          message: serverMessage ?? 'Invalid API key.',
          statusCode: 401,
          serverVersion: serverVersion,
        );
      } else if (response.statusCode == 403) {
        return ApiReportResult.failure(
          message: serverMessage ?? 'Tablet is not registered or is disabled on server.',
          statusCode: 403,
          serverVersion: serverVersion,
        );
      } else {
        return ApiReportResult.failure(
          message: serverMessage ?? 'Server HTTP error ${response.statusCode}',
          statusCode: response.statusCode,
          serverVersion: serverVersion,
        );
      }
    } on TimeoutException {
      return ApiReportResult.failure(
        message: 'Report timeout: Server did not respond within ${timeoutDuration.inSeconds}s.',
      );
    } on SocketException catch (e) {
      return ApiReportResult.failure(
        message: 'Offline / Network error: ${e.message}',
      );
    } catch (e) {
      return ApiReportResult.failure(
        message: 'Error sending report: $e',
      );
    }
  }

  void dispose() {
    _client.close();
  }
}
