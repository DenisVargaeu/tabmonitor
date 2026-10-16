/// Result of testing server connection and device registration.
class ApiTestResult {
  final bool isSuccess;
  final String message;
  final int? statusCode;
  final String? deviceName;
  final bool? isActive;
  final DateTime timestamp;

  ApiTestResult({
    required this.isSuccess,
    required this.message,
    this.statusCode,
    this.deviceName,
    this.isActive,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory ApiTestResult.success({
    required String message,
    int? statusCode,
    String? deviceName,
    bool? isActive,
  }) {
    return ApiTestResult(
      isSuccess: true,
      message: message,
      statusCode: statusCode,
      deviceName: deviceName,
      isActive: isActive,
    );
  }

  factory ApiTestResult.failure({
    required String message,
    int? statusCode,
  }) {
    return ApiTestResult(
      isSuccess: false,
      message: message,
      statusCode: statusCode,
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
  final DateTime timestamp;

  ApiReportResult({
    required this.isSuccess,
    required this.message,
    this.statusCode,
    this.isLowBattery,
    this.threshold,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory ApiReportResult.success({
    required String message,
    int? statusCode,
    bool? isLowBattery,
    int? threshold,
  }) {
    return ApiReportResult(
      isSuccess: true,
      message: message,
      statusCode: statusCode,
      isLowBattery: isLowBattery,
      threshold: threshold,
    );
  }

  factory ApiReportResult.failure({
    required String message,
    int? statusCode,
  }) {
    return ApiReportResult(
      isSuccess: false,
      message: message,
      statusCode: statusCode,
    );
  }
}
