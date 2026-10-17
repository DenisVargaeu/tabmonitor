import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app/models/device_config.dart';
import 'package:app/models/api_response.dart';
import 'package:app/main.dart';

void main() {
  group('DeviceConfig Tests', () {
    test('normalizes URL without schema and trailing slash', () {
      const config = DeviceConfig(
        serverUrl: 'tabmonitor.example.com/api///',
        apiKey: 'secret123',
        deviceId: 'XX-01',
      );

      expect(config.normalizedUrl, equals('https://tabmonitor.example.com/api'));
      expect(
        config.testConnectionUri.toString(),
        equals('https://tabmonitor.example.com/api/api.php?action=test&device_id=XX-01&api_key=secret123'),
      );
      expect(
        config.reportUri.toString(),
        equals('https://tabmonitor.example.com/api/api.php?action=report&api_key=secret123'),
      );
      expect(config.isValid, isTrue);
    });

    test('retains http schema for local development servers', () {
      const config = DeviceConfig(
        serverUrl: 'http://192.168.1.50:8080/',
        apiKey: 'test-key',
        deviceId: 'TAB-99',
      );

      expect(config.normalizedUrl, equals('http://192.168.1.50:8080'));
      expect(config.isValid, isTrue);
    });

    test('detects invalid incomplete configs', () {
      const emptyConfig = DeviceConfig(
        serverUrl: '',
        apiKey: '',
        deviceId: '',
      );
      expect(emptyConfig.isValid, isFalse);
    });
  });

  group('ApiResponse Tests', () {
    test('ApiTestResult factory constructors work as expected', () {
      final success = ApiTestResult.success(
        message: 'Tablet verified',
        deviceName: 'Lenovo K11 01',
        isActive: true,
        statusCode: 200,
      );
      expect(success.isSuccess, isTrue);
      expect(success.deviceName, equals('Lenovo K11 01'));
      expect(success.statusCode, equals(200));

      final failure = ApiTestResult.failure(
        message: 'Unauthorized',
        statusCode: 401,
      );
      expect(failure.isSuccess, isFalse);
      expect(failure.statusCode, equals(401));
    });

    test('ApiReportResult factory constructors work as expected', () {
      final report = ApiReportResult.success(
        message: 'Report received',
        isLowBattery: false,
        threshold: 20,
        statusCode: 200,
      );
      expect(report.isSuccess, isTrue);
      expect(report.isLowBattery, isFalse);
      expect(report.threshold, equals(20));
    });
  });

  testWidgets('App renders SetupScreen when unconfigured', (WidgetTester tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.tabmonitor.app/settings'),
      (MethodCall methodCall) async => false,
    );

    await tester.pumpWidget(const TabMonitorApp(initialConfig: null));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('TabMonitor Setup'), findsOneWidget);
    expect(find.text('Server URL'), findsOneWidget);
    expect(find.text('Tablet ID'), findsOneWidget);
    expect(find.text('Test Connection'), findsOneWidget);
    expect(find.text('Zoznam povolení a nastavení'), findsOneWidget);
  });
}
