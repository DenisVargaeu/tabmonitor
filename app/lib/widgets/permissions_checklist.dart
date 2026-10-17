import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/system_settings_service.dart';

/// Checklist widget for Android 15 permissions, battery optimization, and network connectivity.
/// Displays checkmarks (✔️) for granted items and crosses (❌) for missing ones.
/// Tapping an item navigates directly to that specific Android system settings screen.
class PermissionsChecklist extends StatefulWidget {
  final bool isServerVerified;
  final VoidCallback? onTestServerConnection;

  const PermissionsChecklist({
    super.key,
    this.isServerVerified = false,
    this.onTestServerConnection,
  });

  @override
  State<PermissionsChecklist> createState() => _PermissionsChecklistState();
}

class _PermissionsChecklistState extends State<PermissionsChecklist> with WidgetsBindingObserver {
  final SystemSettingsService _settingsService = SystemSettingsService();

  bool _isBatteryIgnored = false;
  bool _areNotificationsEnabled = false;
  bool _isNetworkConnected = false;
  bool _isLenovoAppDetailsOpened = false;
  bool _isLoading = true;

  static const String _prefLenovoDetails = 'tm_lenovo_details_opened';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAllPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-evaluate permissions when returning from Android system settings
      _checkAllPermissions();
    }
  }

  Future<void> _checkAllPermissions() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final batteryIgnored = await _settingsService.isIgnoringBatteryOptimizations();
      final notifications = await _settingsService.areNotificationsEnabled();
      final network = await _settingsService.isNetworkConnected();

      final prefs = await SharedPreferences.getInstance();
      final lenovoOpened = prefs.getBool(_prefLenovoDetails) ?? false;

      if (!mounted) return;
      setState(() {
        _isBatteryIgnored = batteryIgnored;
        _areNotificationsEnabled = notifications;
        _isNetworkConnected = network;
        _isLenovoAppDetailsOpened = lenovoOpened;
      });
    } catch (_) {
      // Safe fallback
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleBatteryTap() async {
    await _settingsService.requestIgnoreBatteryOptimizations();
  }

  Future<void> _handleNotificationsTap() async {
    await _settingsService.openNotificationSettings();
  }

  Future<void> _handleNetworkTap() async {
    await _settingsService.openWifiSettings();
  }

  Future<void> _handleLenovoTap() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefLenovoDetails, true);
    setState(() => _isLenovoAppDetailsOpened = true);
    await _settingsService.openAppDetailsSettings();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(Icons.checklist_rtl_rounded, color: theme.colorScheme.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Zoznam povolení a nastavení',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Kliknutím na položku prejdete priamo do nastavení Androidu.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (_isLoading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    tooltip: 'Znovu skontrolovať povolenia',
                    onPressed: _checkAllPermissions,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // 1. Battery Optimization Item
            _buildChecklistItem(
              icon: Icons.battery_charging_full_rounded,
              title: 'Ignorovať optimalizáciu batérie',
              description: 'Zabezpečuje, že Android 15 neuspí TabMonitor na pozadí.',
              isGranted: _isBatteryIgnored,
              grantedLabel: 'Povolené (Neobmedzené)',
              missingLabel: 'Optimalizované (Kliknite pre povolenie)',
              onTap: _handleBatteryTap,
            ),

            // 2. Notifications Permission Item
            _buildChecklistItem(
              icon: Icons.notifications_active_outlined,
              title: 'Systémové notifikácie',
              description: 'Zobrazovanie stavu hlásení a upozornení o stave batérie.',
              isGranted: _areNotificationsEnabled,
              grantedLabel: 'Povolené',
              missingLabel: 'Zablokované (Kliknite pre zapnutie)',
              onTap: _handleNotificationsTap,
            ),

            // 3. Network Connection Item
            _buildChecklistItem(
              icon: Icons.wifi,
              title: 'Pripojenie k internetu / Wi-Fi',
              description: 'Aktívne sieťové pripojenie pre odosielanie údajov na server.',
              isGranted: _isNetworkConnected,
              grantedLabel: 'Pripojené',
              missingLabel: 'Bez pripojenia (Otvoriť Wi-Fi)',
              onTap: _handleNetworkTap,
            ),

            // 4. Lenovo Power Management & Activity Pause
            _buildChecklistItem(
              icon: Icons.tune_rounded,
              title: 'Lenovo Správa napájania',
              description: 'Vypnúť "Pozastaviť aktivitu aplikácie pri nepoužívaní".',
              isGranted: _isLenovoAppDetailsOpened,
              grantedLabel: 'Nastavenia skontrolované',
              missingLabel: 'Skontrolovať v detailoch aplikácie',
              onTap: _handleLenovoTap,
            ),

            // 5. Server Test Connection Status
            _buildChecklistItem(
              icon: Icons.cloud_done_outlined,
              title: 'Overenie spojenia so serverom',
              description: 'Overenie platnosti URL, Tablet ID a zdieľaného kľúča.',
              isGranted: widget.isServerVerified,
              grantedLabel: 'Overené so serverom',
              missingLabel: 'Neoverené (Kliknite na Test spojenia)',
              onTap: widget.onTestServerConnection,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChecklistItem({
    required IconData icon,
    required String title,
    required String description,
    required bool isGranted,
    required String grantedLabel,
    required String missingLabel,
    required VoidCallback? onTap,
  }) {
    final color = isGranted ? Colors.green : Colors.red;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: isGranted ? Colors.green.withOpacity(0.06) : Colors.red.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isGranted ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3),
              ),
            ),
            child: Row(
              children: [
                // Icon
                CircleAvatar(
                  radius: 16,
                  backgroundColor: isGranted ? Colors.green.shade100 : Colors.red.shade100,
                  child: Icon(
                    icon,
                    size: 18,
                    color: isGranted ? Colors.green.shade800 : Colors.red.shade800,
                  ),
                ),
                const SizedBox(width: 12),

                // Title and description
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isGranted ? '✓ $grantedLabel' : '✕ $missingLabel',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: color.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Status Badge: Checkmark or Cross
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isGranted ? Colors.green.shade600 : Colors.red.shade600,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: (isGranted ? Colors.green : Colors.red).withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isGranted ? Icons.check_circle_rounded : Icons.cancel_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isGranted ? 'Povolené' : 'Chýba',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(Icons.chevron_right, color: Colors.white, size: 14),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
