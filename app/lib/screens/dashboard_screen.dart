import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/device_config.dart';
import '../services/api_service.dart';
import '../services/battery_service.dart';
import '../services/storage_service.dart';
import 'background_info_sheet.dart';
import 'setup_screen.dart';

/// Main status screen for the Lenovo Tab K11 tablet.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  final StorageService _storageService = StorageService();
  final BatteryService _batteryService = BatteryService();
  final ApiService _apiService = ApiService();

  DeviceConfig? _config;
  int _batteryLevel = 100;
  bool _isCharging = false;
  bool _isSyncing = false;

  DateTime? _lastReportTime;
  bool? _lastReportSuccess;
  String? _lastReportMessage;

  Timer? _foregroundTimer;
  StreamSubscription<bool>? _chargingSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeData();

    // Listen to charging state changes
    _chargingSubscription = _batteryService.onChargingChanged.listen((charging) {
      if (mounted && _isCharging != charging) {
        setState(() => _isCharging = charging);
        // Automatically report state change
        _sendBatteryReport(silent: true);
      }
    });

    // Foreground periodic report timer (every 5 minutes while app is visible)
    _foregroundTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (mounted) {
        _sendBatteryReport(silent: true);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _foregroundTimer?.cancel();
    _chargingSubscription?.cancel();
    _apiService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh status when app comes back to foreground
      _refreshBatteryState();
      _loadLastReportInfo();
    }
  }

  Future<void> _initializeData() async {
    final config = await _storageService.loadConfig();
    if (!mounted) return;

    if (config == null || !config.isValid) {
      // Redirect to setup
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const SetupScreen()),
      );
      return;
    }

    setState(() {
      _config = config;
    });

    await _refreshBatteryState();
    await _loadLastReportInfo();

    // Trigger an initial report on launch
    _sendBatteryReport(silent: true);
  }

  Future<void> _refreshBatteryState() async {
    final level = await _batteryService.getBatteryLevel();
    final charging = await _batteryService.isCharging();
    if (!mounted) return;
    setState(() {
      _batteryLevel = level;
      _isCharging = charging;
    });
  }

  Future<void> _loadLastReportInfo() async {
    final info = await _storageService.getLastReportInfo();
    if (!mounted) return;

    setState(() {
      final tsString = info['timestamp'] as String?;
      if (tsString != null) {
        _lastReportTime = DateTime.tryParse(tsString);
      }
      _lastReportSuccess = info['success'] as bool?;
      _lastReportMessage = info['message'] as String?;
    });
  }

  Future<void> _sendBatteryReport({bool silent = false}) async {
    if (_config == null || _isSyncing) return;

    setState(() {
      _isSyncing = true;
    });

    await _refreshBatteryState();

    final result = await _apiService.sendBatteryReport(
      config: _config!,
      batteryLevel: _batteryLevel,
      isCharging: _isCharging,
    );

    await _storageService.recordReportResult(
      batteryLevel: _batteryLevel,
      isCharging: _isCharging,
      success: result.isSuccess,
      message: result.message,
      timestamp: DateTime.now(),
    );

    if (!mounted) return;

    setState(() {
      _isSyncing = false;
      _lastReportTime = DateTime.now();
      _lastReportSuccess = result.isSuccess;
      _lastReportMessage = result.message;
    });

    if (!silent) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.isSuccess
                ? 'Report sent: $_batteryLevel% (${_isCharging ? "Charging" : "Battery"})'
                : 'Report failed: ${result.message}',
          ),
          backgroundColor: result.isSuccess ? Colors.green.shade700 : Colors.red.shade700,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _openSettings() async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SetupScreen(
          initialConfig: _config,
          isEditing: true,
        ),
      ),
    );

    if (updated == true) {
      await _initializeData();
    }
  }

  Color _getBatteryColor() {
    if (_batteryLevel <= 20) return Colors.red;
    if (_batteryLevel <= 35) return Colors.amber.shade700;
    return Colors.green.shade600;
  }

  IconData _getBatteryIcon() {
    if (_isCharging) return Icons.battery_charging_full;
    if (_batteryLevel >= 90) return Icons.battery_full;
    if (_batteryLevel >= 70) return Icons.battery_6_bar;
    if (_batteryLevel >= 50) return Icons.battery_4_bar;
    if (_batteryLevel >= 30) return Icons.battery_3_bar;
    if (_batteryLevel >= 15) return Icons.battery_2_bar;
    return Icons.battery_alert;
  }

  String _formatRelativeTime(DateTime? dt) {
    if (dt == null) return 'Never';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 10) return 'Just now';
    if (diff.inMinutes < 1) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('MMM d, HH:mm').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final batteryColor = _getBatteryColor();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TabMonitor',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              _config != null ? 'Tablet: ${_config!.deviceId}' : 'Monitoring',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Background Limits Info',
            onPressed: () => BackgroundInfoSheet.show(context),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _sendBatteryReport(silent: false);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Tablet ID Badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.badge, size: 16, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          _config?.deviceId ?? 'XX-01',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _lastReportSuccess == true
                          ? Colors.green.shade50
                          : (_lastReportSuccess == false ? Colors.red.shade50 : Colors.grey.shade100),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _lastReportSuccess == true
                            ? Colors.green.shade300
                            : (_lastReportSuccess == false ? Colors.red.shade300 : Colors.grey.shade300),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 4,
                          backgroundColor: _lastReportSuccess == true
                              ? Colors.green
                              : (_lastReportSuccess == false ? Colors.red : Colors.grey),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _lastReportSuccess == true
                              ? 'Connected'
                              : (_lastReportSuccess == false ? 'Offline / Error' : 'Standby'),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _lastReportSuccess == true
                                ? Colors.green.shade900
                                : (_lastReportSuccess == false ? Colors.red.shade900 : Colors.grey.shade800),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Battery Hero Card
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _getBatteryIcon(),
                            size: 48,
                            color: batteryColor,
                          ),
                          const SizedBox(width: 16),
                          Text(
                            '$_batteryLevel%',
                            style: theme.textTheme.displayMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: batteryColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isCharging ? Icons.bolt : Icons.power_off_outlined,
                            size: 18,
                            color: _isCharging ? Colors.amber.shade800 : Colors.grey.shade600,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _isCharging ? 'Charging via AC / USB' : 'Running on battery',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _isCharging ? Colors.amber.shade900 : Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // Linear Progress Indicator
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: _batteryLevel / 100.0,
                          minHeight: 14,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation<Color>(batteryColor),
                        ),
                      ),

                      if (_batteryLevel <= 20) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.warning, color: Colors.red.shade700, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Low Battery Warning (≤ 20%). Please connect to charger.',
                                  style: TextStyle(fontSize: 12, color: Colors.red.shade900),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Server Sync Status Card
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Cloud Synchronization',
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          if (_isSyncing)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                        ],
                      ),
                      const Divider(height: 20),
                      _buildInfoRow(
                        label: 'Target Server',
                        value: _config?.normalizedUrl ?? 'Not configured',
                      ),
                      const SizedBox(height: 8),
                      _buildInfoRow(
                        label: 'Last Sent',
                        value: '${_formatRelativeTime(_lastReportTime)} (${_lastReportTime != null ? DateFormat('HH:mm:ss').format(_lastReportTime!) : 'N/A'})',
                      ),
                      const SizedBox(height: 8),
                      _buildInfoRow(
                        label: 'Last Status',
                        value: _lastReportMessage ?? 'Pending first report',
                        valueColor: _lastReportSuccess == true
                            ? Colors.green.shade800
                            : (_lastReportSuccess == false ? Colors.red.shade800 : null),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Action Buttons
              FilledButton.icon(
                onPressed: _isSyncing ? null : () => _sendBatteryReport(silent: false),
                icon: _isSyncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(_isSyncing ? 'Transmitting Report...' : 'Send Report Now'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),

              OutlinedButton.icon(
                onPressed: () => BackgroundInfoSheet.show(context),
                icon: const Icon(Icons.help_outline),
                label: const Text('Android 15 Background Rules'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 20),

              // Background Execution Summary
              Card(
                elevation: 0,
                color: Colors.blueGrey.shade50,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      Icon(Icons.schedule, size: 20, color: Colors.blueGrey.shade700),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Background schedule: WorkManager (~15 min periodic task). Real-time updates active while open.',
                          style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade800),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: valueColor ?? Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}
