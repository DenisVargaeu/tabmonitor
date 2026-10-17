import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app/models/device_config.dart';
import 'package:app/models/api_response.dart';
import 'package:app/services/storage_service.dart';
import 'package:app/services/system_settings_service.dart';
import 'package:app/widgets/m3_shape_morph_loader.dart';
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

    test('parseBulkSetupCode correctly parses syntax: adresaserveru-tabletkey-tabid', () {
      // 1. Standard 3-part syntax
      final res1 = DeviceConfig.parseBulkSetupCode('https://school.sk/tabmonitor-secretkey123-TAB01');
      expect(res1, isNotNull);
      expect(res1!.serverUrl, equals('https://school.sk/tabmonitor'));
      expect(res1.apiKey, equals('secretkey123'));
      expect(res1.deviceId, equals('TAB01'));
      expect(res1.bulkSetupCode, equals('https://school.sk/tabmonitor-secretkey123-TAB01'));

      // 2. Syntax with port and hyphen in device ID (TAB-01)
      final res2 = DeviceConfig.parseBulkSetupCode('http://192.168.1.10:8080-secretkey123-TAB-01');
      expect(res2, isNotNull);
      expect(res2!.serverUrl, equals('http://192.168.1.10:8080'));
      expect(res2.apiKey, equals('secretkey123'));
      expect(res2.deviceId, equals('TAB-01'));

      // 3. Syntax with hyphen in server domain and hyphen in device ID (XX-01)
      final res3 = DeviceConfig.parseBulkSetupCode('https://my-school.sk/tabmonitor-5sadd24c4sdf4sd2v12fb42dfg45f2fdg4fdg24fg45f-XX-01');
      expect(res3, isNotNull);
      expect(res3!.serverUrl, equals('https://my-school.sk/tabmonitor'));
      expect(res3.apiKey, equals('5sadd24c4sdf4sd2v12fb42dfg45f2fdg4fdg24fg45f'));
      expect(res3.deviceId, equals('XX-01'));

      // 4. Invalid strings
      expect(DeviceConfig.parseBulkSetupCode(''), isNull);
      expect(DeviceConfig.parseBulkSetupCode('invalid-string'), isNull);
    });
  });

  group('ApiResponse Tests', () {
    test('ApiTestResult factory constructors work as expected', () {
      final success = ApiTestResult.success(
        message: 'Tablet verified',
        deviceName: 'Test Tablet 01',
        isActive: true,
        statusCode: 200,
        serverVersion: '2.1.0',
        reportIntervalMinutes: 10,
      );
      expect(success.isSuccess, isTrue);
      expect(success.deviceName, equals('Test Tablet 01'));
      expect(success.statusCode, equals(200));
      expect(success.serverVersion, equals('2.1.0'));
      expect(success.reportIntervalMinutes, equals(10));

      final failure = ApiTestResult.failure(
        message: 'Unauthorized',
        statusCode: 401,
        serverVersion: '2.1.0',
      );
      expect(failure.isSuccess, isFalse);
      expect(failure.statusCode, equals(401));
      expect(failure.serverVersion, equals('2.1.0'));
      expect(failure.reportIntervalMinutes, isNull);
    });

    test('ApiReportResult factory constructors work as expected', () {
      final report = ApiReportResult.success(
        message: 'Report received',
        isLowBattery: false,
        threshold: 20,
        statusCode: 200,
        serverVersion: '2.1.0',
        reportIntervalMinutes: 15,
      );
      expect(report.isSuccess, isTrue);
      expect(report.isLowBattery, isFalse);
      expect(report.threshold, equals(20));
      expect(report.serverVersion, equals('2.1.0'));
      expect(report.reportIntervalMinutes, equals(15));
    });
  });

  group('StorageService Interval Tests', () {
    test('loadReportInterval returns default 15 if unset or invalid, and clamps minimum to 5', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();

      expect(await storage.loadReportInterval(), equals(15));

      await storage.saveReportInterval(5);
      expect(await storage.loadReportInterval(), equals(5));

      await storage.saveReportInterval(30);
      expect(await storage.loadReportInterval(), equals(30));

      // Cannot go below 5
      await storage.saveReportInterval(2);
      expect(await storage.loadReportInterval(), equals(5));
    });
  });

  testWidgets('App renders SetupScreen when unconfigured', (WidgetTester tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.tabmonitor.app/settings'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getDeviceInfo') {
          return {
            'manufacturer': 'Google',
            'model': 'Pixel Tablet',
            'release': '15',
            'sdkInt': 35,
          };
        }
        return false;
      },
    );

    await tester.pumpWidget(const TabMonitorApp(initialConfig: null));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('TabMonitor Sprievodca'), findsOneWidget);
    expect(find.text('v2.1.0'), findsOneWidget);
    expect(find.text('Server URL'), findsOneWidget);
    expect(find.text('Zdieľaný API kľúč'), findsOneWidget);
    expect(find.text('Otestovať spojenie'), findsOneWidget);
    expect(find.text('Ďalej'), findsOneWidget);
  });

  testWidgets('M3ShapeMorphLoader renders and animates', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: M3ShapeMorphLoader(size: 64, label: 'Test Loader'),
          ),
        ),
      ),
    );

    expect(find.text('Test Loader'), findsOneWidget);
    expect(find.byType(M3ShapeMorphLoader), findsOneWidget);

    // Pump frames to verify morph animation runs smoothly
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 1000));
  });

  group('SystemSettingsService Tests', () {
    test('showStatusNotification, cancelStatusNotification, and getDeviceInfo invoke channel correctly', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final List<MethodCall> calls = [];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.tabmonitor.app/settings'),
        (MethodCall call) async {
          calls.add(call);
          if (call.method == 'getDeviceInfo') {
            return {
              'manufacturer': 'Google',
              'model': 'Pixel Tablet',
              'release': '15',
              'sdkInt': 35,
            };
          }
          return true;
        },
      );

      final settings = SystemSettingsService();

      await settings.showStatusNotification(
        deviceId: 'XX-01',
        batteryLevel: 85,
        isCharging: true,
        isOnline: true,
        statusMessage: 'Sync OK',
        nextReportSeconds: 300,
      );

      expect(calls.length, equals(1));
      expect(calls.first.method, equals('showStatusNotification'));
      expect(calls.first.arguments, equals({
        'deviceId': 'XX-01',
        'batteryLevel': 85,
        'isCharging': true,
        'isOnline': true,
        'statusMessage': 'Sync OK',
        'nextReportSeconds': 300,
      }));

      await settings.cancelStatusNotification();
      expect(calls.length, equals(2));
      expect(calls.last.method, equals('cancelStatusNotification'));

      final info = await settings.getDeviceInfo();
      expect(info['model'], equals('Pixel Tablet'));
      expect(calls.length, equals(3));
    });
  });
}
