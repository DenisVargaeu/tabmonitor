import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/device_config.dart';
import '../models/sync_log_entry.dart';
import '../services/api_service.dart';
import '../services/background_service.dart';
import '../services/battery_service.dart';
import '../services/storage_service.dart';
import '../services/system_settings_service.dart';
import '../widgets/m3_shape_morph_loader.dart';
import '../widgets/permissions_checklist.dart';
import 'background_info_sheet.dart';
import 'setup_screen.dart';

/// Multi-functional Material 3 Tablet Command Center.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  final StorageService _storageService = StorageService();
  final BatteryService _batteryService = BatteryService();
  final ApiService _apiService = ApiService();
  final SystemSettingsService _settingsService = SystemSettingsService();

  int _selectedTab = 0;

  DeviceConfig? _config;
  int _batteryLevel = 100;
  bool _isCharging = false;
  bool _isSyncing = false;
  bool _isPinging = false;
  int? _lastPingMs;

  DateTime? _lastReportTime;
  bool? _lastReportSuccess;
  String? _lastReportMessage;

  // Real native Android device details
  Map<String, dynamic> _deviceInfo = {};

  // Telemetry logs
  List<SyncLogEntry> _syncLogs = [];
  String _logFilter = 'all'; // 'all', 'success', 'error'

  // Dynamic reporting interval (default 15 minutes, configurable down to 5 minutes)
  int _reportIntervalMinutes = 15;
  int get _reportIntervalSeconds => _reportIntervalMinutes * 60;
  int _secondsUntilNextReport = 15 * 60;
  Timer? _countdownTimer;
  Timer? _foregroundReportTimer;
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

    // Start 1-second countdown timer for UI and notification sync
    _startCountdownTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _foregroundReportTimer?.cancel();
    _chargingSubscription?.cancel();
    _apiService.dispose();
    super.dispose();
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    _secondsUntilNextReport = _reportIntervalSeconds;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsUntilNextReport > 0) {
        setState(() {
          _secondsUntilNextReport--;
        });
      } else {
        // Trigger report and reset countdown
        _secondsUntilNextReport = _reportIntervalSeconds;
        _sendBatteryReport(silent: true);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshBatteryState().then((_) {
        if (_config != null && mounted) {
          _updateStatusNotification(
            isOnline: _lastReportSuccess ?? true,
            statusMessage: _lastReportMessage ?? 'TabMonitor pripravený',
            nextReportSeconds: _secondsUntilNextReport,
          );
        }
      });
      _loadLastReportInfo();
      _loadSyncLogs();
    }
  }

  Future<void> _initializeData() async {
    final config = await _storageService.loadConfig();
    if (!mounted) return;

    if (config == null || !config.isValid) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const SetupScreen()),
      );
      return;
    }

    final savedInterval = await _storageService.loadReportInterval();
    if (!mounted) return;

    setState(() {
      _config = config;
      _reportIntervalMinutes = savedInterval;
      _secondsUntilNextReport = savedInterval * 60;
    });

    await _loadNativeDeviceInfo();
    await _refreshBatteryState();
    await _loadLastReportInfo();
    await _loadSyncLogs();

    await _updateStatusNotification(
      isOnline: _lastReportSuccess ?? true,
      statusMessage: _lastReportMessage ?? 'TabMonitor pripravený',
      nextReportSeconds: _secondsUntilNextReport,
    );

    // Initial report on startup
    _sendBatteryReport(silent: true);
  }

  Future<void> _loadNativeDeviceInfo() async {
    try {
      final info = await _settingsService.getDeviceInfo();
      if (mounted) {
        setState(() => _deviceInfo = info);
      }
    } catch (_) {}
  }

  Future<void> _loadSyncLogs() async {
    final logs = await _storageService.getSyncLogs();
    if (mounted) {
      setState(() => _syncLogs = logs);
    }
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

  Future<void> _updateStatusNotification({
    required bool isOnline,
    required String statusMessage,
    int nextReportSeconds = 300,
  }) async {
    if (_config == null) return;
    await _settingsService.showStatusNotification(
      deviceId: _config!.deviceId,
      batteryLevel: _batteryLevel,
      isCharging: _isCharging,
      isOnline: isOnline,
      statusMessage: statusMessage,
      nextReportSeconds: nextReportSeconds,
    );
  }

  Future<void> _sendBatteryReport({bool silent = false}) async {
    if (_config == null || _isSyncing) return;

    setState(() => _isSyncing = true);

    await _refreshBatteryState();

    final stopwatch = Stopwatch()..start();
    final result = await _apiService.sendBatteryReport(
      config: _config!,
      batteryLevel: _batteryLevel,
      isCharging: _isCharging,
    );
    stopwatch.stop();

    final now = DateTime.now();

    await _storageService.recordReportResult(
      batteryLevel: _batteryLevel,
      isCharging: _isCharging,
      success: result.isSuccess,
      message: result.message,
      timestamp: now,
      statusCode: result.statusCode,
      latencyMs: stopwatch.elapsedMilliseconds,
    );

    // If server pushed a configured reporting interval, synchronize it
    if (result.reportIntervalMinutes != null &&
        result.reportIntervalMinutes! >= 5 &&
        result.reportIntervalMinutes! != _reportIntervalMinutes) {
      _reportIntervalMinutes = result.reportIntervalMinutes!;
      await _storageService.saveReportInterval(_reportIntervalMinutes);
      await BackgroundService().schedulePeriodicReports(intervalMinutes: _reportIntervalMinutes);
    }

    if (!mounted) return;

    setState(() {
      _isSyncing = false;
      _lastReportTime = now;
      _lastReportSuccess = result.isSuccess;
      _lastReportMessage = result.message;
      _secondsUntilNextReport = result.isSuccess ? _reportIntervalSeconds : 60;
    });

    await _loadSyncLogs();

    await _updateStatusNotification(
      isOnline: result.isSuccess,
      statusMessage: result.isSuccess
          ? 'Posledná synchronizácia: ${DateFormat('HH:mm:ss').format(now)}'
          : 'Chyba spojenia: ${result.message}',
      nextReportSeconds: _secondsUntilNextReport,
    );

    if (!silent && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                result.isSuccess ? Icons.check_circle : Icons.error,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  result.isSuccess
                      ? 'Hlásenie odoslané: $_batteryLevel% (${_isCharging ? "Nabíja sa" : "Batéria"})'
                      : 'Hlásenie zlyhalo: ${result.message}',
                ),
              ),
            ],
          ),
          backgroundColor: result.isSuccess ? Colors.green.shade700 : Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  Future<void> _changeReportInterval(int newMinutes) async {
    final clamped = newMinutes.clamp(5, 60);
    if (clamped == _reportIntervalMinutes) return;

    setState(() {
      _reportIntervalMinutes = clamped;
      _secondsUntilNextReport = clamped * 60;
    });

    await _storageService.saveReportInterval(clamped);
    await BackgroundService().schedulePeriodicReports(intervalMinutes: clamped);
    await _updateStatusNotification(
      isOnline: _lastReportSuccess ?? true,
      statusMessage: _lastReportMessage ?? 'TabMonitor pripravený',
      nextReportSeconds: _secondsUntilNextReport,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Interval odosielania bol zmenený na $clamped minút.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _runPingTest() async {
    if (_config == null || _isPinging) return;
    setState(() => _isPinging = true);

    final stopwatch = Stopwatch()..start();
    final result = await _apiService.testConnection(_config!);
    stopwatch.stop();

    if (!mounted) return;
    setState(() {
      _isPinging = false;
      _lastPingMs = stopwatch.elapsedMilliseconds;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.isSuccess
              ? 'Server odpovedal za $_lastPingMs ms (${result.deviceName ?? "OK"})'
              : 'Test zlyhal: ${result.message}',
        ),
        backgroundColor: result.isSuccess ? Colors.teal.shade700 : Colors.orange.shade800,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _copyDiagnosticsToClipboard() {
    final text = '''
TabMonitor Diagnostika:
• ID Zariadenia: ${_config?.deviceId ?? 'Nezadané'}
• Zariadenie: $_detectedDeviceName
• Android: $_detectedAndroidVersion
• Stav batérie: $_batteryLevel% (${_isCharging ? "Nabíja sa" : "Batéria"})
• Server URL: ${_config?.normalizedUrl ?? 'N/A'}
• Posledné hlásenie: ${_lastReportTime != null ? DateFormat('yyyy-MM-dd HH:mm:ss').format(_lastReportTime!) : 'Nikdy'}
• Stav spojenia: ${_lastReportSuccess == true ? 'OK (200)' : 'Chyba'}
• Posledná správa: ${_lastReportMessage ?? 'N/A'}
• Latencia: ${_lastPingMs != null ? '$_lastPingMs ms' : 'Nemerané'}
''';

    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Diagnostická správa skopírovaná do schránky.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
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

  String get _detectedDeviceName {
    final manufacturer = _deviceInfo['manufacturer']?.toString() ?? '';
    final model = _deviceInfo['model']?.toString() ?? '';
    if (manufacturer.isNotEmpty && model.isNotEmpty) {
      return '${manufacturer[0].toUpperCase()}${manufacturer.substring(1)} $model';
    } else if (model.isNotEmpty) {
      return model;
    }
    return 'Tvoje zariadenie';
  }

  String get _detectedAndroidVersion {
    final release = _deviceInfo['release']?.toString();
    final sdk = _deviceInfo['sdkInt']?.toString();
    if (release != null && sdk != null) {
      return 'Android $release (API $sdk)';
    } else if (release != null) {
      return 'Android $release';
    }
    return 'Android OS';
  }

  String _formatCountdown(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Color _getBatteryColor() {
    if (_batteryLevel <= 20) return Colors.red.shade600;
    if (_batteryLevel <= 35) return Colors.amber.shade700;
    return Colors.green.shade600;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TabMonitor',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            Text(
              '$_detectedDeviceName • ${_config?.deviceId ?? ""}',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Kopírovať diagnostiku',
            onPressed: _copyDiagnosticsToClipboard,
          ),
          IconButton(
            icon: const Icon(Icons.help_outline_rounded),
            tooltip: 'Pravidlá pozadia v Androide',
            onPressed: () => BackgroundInfoSheet.show(context),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Nastavenia',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedTab,
        children: [
          _buildOverviewTab(theme),
          _buildTelemetryTab(theme),
          _buildDiagnosticsTab(theme),
          _buildSettingsTab(theme),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (idx) => setState(() => _selectedTab = idx),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Prehľad',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history_rounded),
            label: 'Telemetria',
          ),
          NavigationDestination(
            icon: Icon(Icons.monitor_heart_outlined),
            selectedIcon: Icon(Icons.monitor_heart_rounded),
            label: 'Diagnostika',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune_rounded),
            label: 'Systém',
          ),
        ],
      ),
    );
  }

  // TAB 1: OVERVIEW & HERO STATUS
  Widget _buildOverviewTab(ThemeData theme) {
    final batteryColor = _getBatteryColor();
    final isOnline = _lastReportSuccess == true;

    return RefreshIndicator(
      onRefresh: () => _sendBatteryReport(silent: false),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status & Countdown Banner
            Row(
              children: [
                // Device ID pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.badge_rounded, size: 16, color: theme.colorScheme.primary),
                      const SizedBox(width: 6),
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
                const Spacer(),

                // Live ticking countdown to next report
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.timer_outlined, size: 15, color: theme.colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        'Odpočet: ${_formatCountdown(_secondsUntilNextReport)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Hero Battery Card with M3 shape styling
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.4)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(22.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Stav akumulátora',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  '$_batteryLevel',
                                  style: theme.textTheme.displayMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: batteryColor,
                                  ),
                                ),
                                Text(
                                  '%',
                                  style: theme.textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: batteryColor,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        // Animated charging icon or battery icon
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: batteryColor.withOpacity(0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _isCharging ? Icons.bolt_rounded : Icons.battery_std_rounded,
                            size: 42,
                            color: batteryColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Charging State Badge
                    Row(
                      children: [
                        Icon(
                          _isCharging ? Icons.power_rounded : Icons.battery_charging_full_rounded,
                          size: 16,
                          color: _isCharging ? Colors.amber.shade800 : Colors.grey.shade600,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _isCharging ? 'Pripojené k nabíjačke (AC / USB)' : 'Prevádzka na batériu',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _isCharging ? Colors.amber.shade900 : Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Linear battery progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: _batteryLevel / 100.0,
                        minHeight: 12,
                        backgroundColor: theme.colorScheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(batteryColor),
                      ),
                    ),

                    if (_batteryLevel <= 20) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Nízka úroveň batérie (≤ 20%). Pripojte tablet k nabíjačke.',
                                style: TextStyle(fontSize: 12, color: Colors.red.shade900, fontWeight: FontWeight.w500),
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
            const SizedBox(height: 16),

            // Ongoing Notification Status Card
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.3)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: isOnline ? Colors.green.shade100 : Colors.orange.shade100,
                      child: Icon(
                        isOnline ? Icons.notifications_active_rounded : Icons.notifications_off_rounded,
                        color: isOnline ? Colors.green.shade800 : Colors.orange.shade900,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Stála notifikácia s odpočtom',
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Zobrazuje stav (${isOnline ? "🟢 Pripojené" : "🔴 Offline"}) a živý chronometer v lište.',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Main Action Button: Synchronize Now with M3 Shape Morph Loader!
            FilledButton.icon(
              onPressed: _isSyncing ? null : () => _sendBatteryReport(silent: false),
              icon: _isSyncing
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: M3ShapeMorphLoader(size: 22, strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded),
              label: Text(_isSyncing ? 'Odosielam hlásenie na server...' : 'Synchronizovať teraz'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 12),

            // Quick Actions Grid
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isPinging ? null : _runPingTest,
                    icon: _isPinging
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.speed_rounded, size: 18),
                    label: Text(_isPinging ? 'Ping...' : 'Test latencie'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showPermissionsChecklistModal(context),
                    icon: const Icon(Icons.checklist_rounded, size: 18),
                    label: const Text('Povolenia'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // TAB 2: TELEMETRY & SYNC LOGS
  Widget _buildTelemetryTab(ThemeData theme) {
    final filteredLogs = _syncLogs.where((log) {
      if (_logFilter == 'success') return log.isSuccess;
      if (_logFilter == 'error') return !log.isSuccess;
      return true;
    }).toList();

    return Column(
      children: [
        // Filter Chips & Clear Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              FilterChip(
                label: const Text('Všetky'),
                selected: _logFilter == 'all',
                onSelected: (_) => setState(() => _logFilter = 'all'),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Úspešné'),
                selected: _logFilter == 'success',
                onSelected: (_) => setState(() => _logFilter = 'success'),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Iba chyby'),
                selected: _logFilter == 'error',
                onSelected: (_) => setState(() => _logFilter = 'error'),
              ),
              const Spacer(),
              if (_syncLogs.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                  tooltip: 'Vymazať históriu',
                  onPressed: () async {
                    await _storageService.clearSyncLogs();
                    await _loadSyncLogs();
                  },
                ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Logs List
        Expanded(
          child: filteredLogs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history_rounded, size: 48, color: theme.colorScheme.outlineVariant),
                      const SizedBox(height: 12),
                      Text(
                        'Zatiaľ žiadne záznamy v denníku',
                        style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: filteredLogs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final log = filteredLogs[index];
                    return Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.35),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      child: ListTile(
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: log.isSuccess ? Colors.green.shade100 : Colors.red.shade100,
                          child: Icon(
                            log.isSuccess ? Icons.check_circle_outline : Icons.error_outline,
                            color: log.isSuccess ? Colors.green.shade800 : Colors.red.shade800,
                            size: 20,
                          ),
                        ),
                        title: Row(
                          children: [
                            Text(
                              DateFormat('HH:mm:ss').format(log.timestamp),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: log.isSuccess ? Colors.green.shade50 : Colors.red.shade50,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${log.batteryLevel}% ${log.isCharging ? "⚡" : ""}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: log.isSuccess ? Colors.green.shade900 : Colors.red.shade900,
                                ),
                              ),
                            ),
                            const Spacer(),
                            if (log.latencyMs != null)
                              Text(
                                '${log.latencyMs} ms',
                                style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                              ),
                          ],
                        ),
                        subtitle: Text(
                          log.message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // TAB 3: DIAGNOSTICS & REAL HARDWARE
  Widget _buildDiagnosticsTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Real Detected Hardware Card
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.4)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.memory_rounded, color: theme.colorScheme.primary),
                      const SizedBox(width: 10),
                      Text(
                        'Hardvér zariadenia',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  _buildDiagRow('Výrobca (Manufacturer)', _deviceInfo['manufacturer']?.toString() ?? 'N/A'),
                  _buildDiagRow('Model zariadenia', _deviceInfo['model']?.toString() ?? 'N/A'),
                  _buildDiagRow('Značka (Brand)', _deviceInfo['brand']?.toString() ?? 'N/A'),
                  _buildDiagRow('Zariadenie (Device)', _deviceInfo['device']?.toString() ?? 'N/A'),
                  _buildDiagRow('Verzia Androidu', _detectedAndroidVersion),
                  _buildDiagRow('SDK Int', _deviceInfo['sdkInt']?.toString() ?? 'N/A'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Network & Ping Latency Card with M3 Morph Loader
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.4)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.wifi_tethering_rounded, color: theme.colorScheme.primary),
                          const SizedBox(width: 10),
                          Text(
                            'Sieť & Odozva',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      if (_lastPingMs != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.green.shade300),
                          ),
                          child: Text(
                            '$_lastPingMs ms',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade900),
                          ),
                        ),
                    ],
                  ),
                  const Divider(height: 20),
                  _buildDiagRow('Cieľový server', _config?.normalizedUrl ?? 'Nekonfigurovaný'),
                  _buildDiagRow('Režim spojenia', _config?.normalizedUrl.startsWith('https://') == true ? 'Zabezpečené HTTPS' : 'Lokálne HTTP'),
                  const SizedBox(height: 12),

                  OutlinedButton.icon(
                    onPressed: _isPinging ? null : _runPingTest,
                    icon: _isPinging
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: M3ShapeMorphLoader(size: 20, strokeWidth: 2),
                          )
                        : const Icon(Icons.speed_rounded),
                    label: Text(_isPinging ? 'Meriam latenciu...' : 'Zmerať odozvu servera'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  // TAB 4: SYSTEM & SETTINGS
  Widget _buildSettingsTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Current Tablet Config Summary
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.4)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Konfigurácia klienta',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.badge_outlined),
                    title: const Text('Tablet ID', style: TextStyle(fontSize: 13, color: Colors.grey)),
                    subtitle: Text(
                      _config?.deviceId ?? 'Nezadané',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.cloud_outlined),
                    title: const Text('Server URL', style: TextStyle(fontSize: 13, color: Colors.grey)),
                    subtitle: Text(
                      _config?.normalizedUrl ?? 'Nezadané',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (_config != null && _config!.isValid) ...[
                    const Divider(height: 18),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.flash_on_rounded, color: Colors.amber),
                      title: const Text('Bulk Setup Kód', style: TextStyle(fontSize: 13, color: Colors.grey)),
                      subtitle: Text(
                        _config!.bulkSetupCode,
                        style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 20),
                        tooltip: 'Kopírovať kód',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _config!.bulkSetupCode));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Bulk Setup kód bol skopírovaný do schránky.'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: _openSettings,
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('Upraviť nastavenia a pripojenie'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Telemetry Reporting Interval Card
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.4)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.schedule_rounded, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Interval odosielania dát',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$_reportIntervalMinutes min',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Frekvencia odosielania telemetrie batérie na server. Predvolené je 15 minút, no môžete ju znížiť až na 5 minút pre rýchlejší monitoring.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final m in [5, 10, 15, 30, 60])
                        ChoiceChip(
                          label: Text(
                            m == 15 ? '15 min (Predvolené)' : '$m min',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: _reportIntervalMinutes == m ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          selected: _reportIntervalMinutes == m,
                          onSelected: (selected) {
                            if (selected) {
                              _changeReportInterval(m);
                            }
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('5 min', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      Expanded(
                        child: Slider(
                          value: _reportIntervalMinutes.toDouble(),
                          min: 5.0,
                          max: 60.0,
                          divisions: 11,
                          label: '$_reportIntervalMinutes min',
                          onChanged: (val) {
                            _changeReportInterval(val.round());
                          },
                        ),
                      ),
                      const Text('60 min', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Permissions & OS Optimizations Shortcut
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.4)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Optimalizácia a povolenia',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Kontrola systémových oprávnení pre beh na pozadí.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: () => _showPermissionsChecklistModal(context),
                    icon: const Icon(Icons.checklist_rtl_rounded),
                    label: const Text('Otvoriť kontrolný zoznam povolení'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPermissionsChecklistModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.78,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (ctx, scrollController) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: ListView(
            controller: scrollController,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              PermissionsChecklist(
                isServerVerified: _lastReportSuccess == true,
                onTestServerConnection: () {
                  Navigator.of(ctx).pop();
                  _sendBatteryReport(silent: false);
                },
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(ctx).pop(),
                icon: const Icon(Icons.check),
                label: const Text('Hotovo'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
