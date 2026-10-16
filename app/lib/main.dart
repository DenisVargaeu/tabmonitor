import 'package:flutter/material.dart';
import 'models/device_config.dart';
import 'screens/dashboard_screen.dart';
import 'screens/setup_screen.dart';
import 'services/background_service.dart';
import 'services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Android WorkManager for periodic background tasks
  await BackgroundService().initialize();

  // Check if device credentials are already configured
  final storage = StorageService();
  final config = await storage.loadConfig();

  // If already configured, schedule background worker on startup
  if (config != null && config.isValid) {
    await BackgroundService().schedulePeriodicReports();
  }

  runApp(TabMonitorApp(initialConfig: config));
}

class TabMonitorApp extends StatelessWidget {
  final DeviceConfig? initialConfig;

  const TabMonitorApp({super.key, this.initialConfig});

  @override
  Widget build(BuildContext context) {
    final isConfigured = initialConfig != null && initialConfig!.isValid;

    return MaterialApp(
      title: 'TabMonitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E88E5), // Blue 600
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E88E5),
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      home: isConfigured ? const DashboardScreen() : const SetupScreen(),
    );
  }
}
