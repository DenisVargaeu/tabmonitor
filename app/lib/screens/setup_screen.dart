import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/api_response.dart';
import '../models/device_config.dart';
import '../services/api_service.dart';
import '../services/background_service.dart';
import '../services/battery_service.dart';
import '../services/storage_service.dart';
import '../widgets/permissions_checklist.dart';
import 'dashboard_screen.dart';

/// Setup screen displayed on first launch or when editing configuration.
class SetupScreen extends StatefulWidget {
  final DeviceConfig? initialConfig;
  final bool isEditing;

  const SetupScreen({
    super.key,
    this.initialConfig,
    this.isEditing = false,
  });

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _urlController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _deviceIdController;

  bool _obscureApiKey = true;
  bool _isTesting = false;
  bool _isSaving = false;
  ApiTestResult? _lastTestResult;

  final ApiService _apiService = ApiService();
  final StorageService _storageService = StorageService();

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.initialConfig?.serverUrl ?? '');
    _apiKeyController = TextEditingController(text: widget.initialConfig?.apiKey ?? '');
    _deviceIdController = TextEditingController(text: widget.initialConfig?.deviceId ?? '');
  }

  @override
  void dispose() {
    _urlController.dispose();
    _apiKeyController.dispose();
    _deviceIdController.dispose();
    _apiService.dispose();
    super.dispose();
  }

  DeviceConfig _buildCurrentConfig() {
    return DeviceConfig(
      serverUrl: _urlController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      deviceId: _deviceIdController.text.trim(),
    );
  }

  Future<void> _handleTestConnection() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isTesting = true;
      _lastTestResult = null;
    });

    final config = _buildCurrentConfig();
    final result = await _apiService.testConnection(config);

    if (!mounted) return;
    setState(() {
      _isTesting = false;
      _lastTestResult = result;
    });
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // If connection was not tested yet or failed, ask user if they want to test or proceed
    if (_lastTestResult == null || !_lastTestResult!.isSuccess) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Save without verified connection?'),
          content: const Text(
            'The connection has not been verified with the server yet. You can still save, but battery reports may fail if credentials or server URL are incorrect.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Back to Test'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Save Anyway'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() {
      _isSaving = true;
    });

    final config = _buildCurrentConfig();
    await _storageService.saveConfig(config);

    // Schedule background WorkManager tasks
    await BackgroundService().schedulePeriodicReports();

    // Trigger an initial report right away
    try {
      final battery = BatteryService();
      final level = await battery.getBatteryLevel();
      final isCharging = await battery.isCharging();
      final reportResult = await _apiService.sendBatteryReport(
        config: config,
        batteryLevel: level,
        isCharging: isCharging,
      );
      await _storageService.recordReportResult(
        batteryLevel: level,
        isCharging: isCharging,
        success: reportResult.isSuccess,
        message: reportResult.message,
      );
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _isSaving = false;
    });

    if (widget.isEditing) {
      Navigator.of(context).pop(true);
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Tablet Settings' : 'TabMonitor Setup'),
        elevation: 0,
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header banner
                Card(
                  elevation: 0,
                  color: theme.colorScheme.primaryContainer.withOpacity(0.4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: theme.colorScheme.primary,
                          child: const Icon(Icons.tablet_android, color: Colors.white, size: 28),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.isEditing ? 'Configure Tablet Client' : 'Welcome to TabMonitor',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Connect this Lenovo Tab K11 to your TabMonitor server dashboard.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Server URL input
                TextFormField(
                  controller: _urlController,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Server URL',
                    hintText: 'https://example.com/tabmonitor',
                    helperText: 'Web address of the TabMonitor server (HTTPS recommended)',
                    prefixIcon: const Icon(Icons.link),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    suffixIcon: _urlController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(() => _urlController.clear()),
                          )
                        : null,
                  ),
                  onChanged: (_) => setState(() => _lastTestResult = null),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Server URL is required';
                    }
                    final v = value.trim();
                    if (!v.startsWith('http://') && !v.startsWith('https://')) {
                      return 'URL must start with https:// or http://';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 18),

                // Tablet ID input
                TextFormField(
                  controller: _deviceIdController,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_\-\.]')),
                  ],
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Tablet ID',
                    hintText: 'e.g. TAB-01, XX-01',
                    helperText: 'Unique identifier pre-registered in teacher dashboard',
                    prefixIcon: const Icon(Icons.badge_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onChanged: (_) => setState(() => _lastTestResult = null),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Tablet ID is required (e.g. TAB-01)';
                    }
                    if (value.trim().length > 50) {
                      return 'Tablet ID must be under 50 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 18),

                // Shared API Key input
                TextFormField(
                  controller: _apiKeyController,
                  obscureText: _obscureApiKey,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'Shared Tablet API Key',
                    hintText: 'Configured tablet_api_key',
                    helperText: 'Found in server config.php or installer output',
                    prefixIcon: const Icon(Icons.key),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureApiKey ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscureApiKey = !_obscureApiKey),
                    ),
                  ),
                  onChanged: (_) => setState(() => _lastTestResult = null),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Shared API key is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                // Test Connection Button
                OutlinedButton.icon(
                  onPressed: _isTesting ? null : _handleTestConnection,
                  icon: _isTesting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.network_check),
                  label: Text(_isTesting ? 'Testing Connection...' : 'Test Connection'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 16),

                // Test Result Card
                if (_lastTestResult != null) ...[
                  _buildTestResultCard(_lastTestResult!),
                  const SizedBox(height: 16),
                ],

                // Permissions & System Checklist
                PermissionsChecklist(
                  isServerVerified: _lastTestResult?.isSuccess == true,
                  onTestServerConnection: _handleTestConnection,
                ),
                const SizedBox(height: 20),

                // Save Button
                FilledButton.icon(
                  onPressed: _isSaving ? null : _handleSave,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: Text(_isSaving ? 'Saving...' : (widget.isEditing ? 'Save Changes' : 'Complete Setup')),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTestResultCard(ApiTestResult result) {
    final isSuccess = result.isSuccess;
    final color = isSuccess ? Colors.green : Colors.red;

    return Card(
      elevation: 0,
      color: isSuccess ? Colors.green.shade50 : Colors.red.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isSuccess ? Colors.green.shade300 : Colors.red.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isSuccess ? Icons.check_circle : Icons.error_outline,
              color: color.shade700,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isSuccess ? 'Connection Verified' : 'Connection Failed',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: color.shade900,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    result.message,
                    style: TextStyle(color: color.shade900, fontSize: 13),
                  ),
                  if (result.deviceName != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Registered Device: "${result.deviceName}"',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.green.shade900,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (result.statusCode != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'HTTP Status: ${result.statusCode}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
