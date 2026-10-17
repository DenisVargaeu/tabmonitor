/// Result of testing server connection and device registration.
class ApiTestResult {
  final bool isSuccess;
  final String message;
  final int? statusCode;
  final String? deviceName;
  final bool? isActive;
  final String? serverVersion;
  final int? reportIntervalMinutes;
  final DateTime timestamp;

  ApiTestResult({
    required this.isSuccess,
    required this.message,
    this.statusCode,
    this.deviceName,
    this.isActive,
    this.serverVersion,
    this.reportIntervalMinutes,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory ApiTestResult.success({
    required String message,
    int? statusCode,
    String? deviceName,
    bool? isActive,
    String? serverVersion,
    int? reportIntervalMinutes,
  }) {
    return ApiTestResult(
      isSuccess: true,
      message: message,
      statusCode: statusCode,
      deviceName: deviceName,
      isActive: isActive,
      serverVersion: serverVersion,
      reportIntervalMinutes: reportIntervalMinutes,
    );
  }

  factory ApiTestResult.failure({
    required String message,
    int? statusCode,
    String? serverVersion,
    int? reportIntervalMinutes,
  }) {
    return ApiTestResult(
      isSuccess: false,
      message: message,
      statusCode: statusCode,
      serverVersion: serverVersion,
      reportIntervalMinutes: reportIntervalMinutes,
    );
  }
}

/// Result of sending a battery report to the server.
class ApiReportResult {
  final bool isSuccess;
  final String message;
  final int? statusCode;
  final bool? isLowBattery;
  final int? threshold;
  final String? serverVersion;
  final int? reportIntervalMinutes;
  final DateTime timestamp;

  ApiReportResult({
    required this.isSuccess,
    required this.message,
    this.statusCode,
    this.isLowBattery,
    this.threshold,
    this.serverVersion,
    this.reportIntervalMinutes,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory ApiReportResult.success({
    required String message,
    int? statusCode,
    bool? isLowBattery,
    int? threshold,
    String? serverVersion,
    int? reportIntervalMinutes,
  }) {
    return ApiReportResult(
      isSuccess: true,
      message: message,
      statusCode: statusCode,
      isLowBattery: isLowBattery,
      threshold: threshold,
      serverVersion: serverVersion,
      reportIntervalMinutes: reportIntervalMinutes,
    );
  }

  factory ApiReportResult.failure({
    required String message,
    int? statusCode,
    String? serverVersion,
    int? reportIntervalMinutes,
  }) {
    return ApiReportResult(
      isSuccess: false,
      message: message,
      statusCode: statusCode,
      serverVersion: serverVersion,
      reportIntervalMinutes: reportIntervalMinutes,
    );
  }
}
