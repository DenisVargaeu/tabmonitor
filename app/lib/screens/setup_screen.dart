import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/api_response.dart';
import '../models/device_config.dart';
import '../services/api_service.dart';
import '../services/background_service.dart';
import '../services/storage_service.dart';
import '../services/system_settings_service.dart';
import '../widgets/m3_shape_morph_loader.dart';
import '../widgets/permissions_checklist.dart';
import 'dashboard_screen.dart';

/// Multi-step Material 3 setup wizard for configuring TabMonitor on any Android device.
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
  final PageController _pageController = PageController();
  int _currentStep = 0;
  static const int _totalSteps = 4;

  final _formKeyStep1 = GlobalKey<FormState>();
  final _formKeyStep2 = GlobalKey<FormState>();

  late final TextEditingController _urlController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _deviceIdController;

  bool _obscureApiKey = true;
  bool _isTesting = false;
  bool _isSaving = false;
  ApiTestResult? _lastTestResult;

  // Real hardware device info detected from native Android
  Map<String, dynamic> _deviceInfo = {};
  bool _isLoadingDeviceInfo = true;

  final ApiService _apiService = ApiService();
  final StorageService _storageService = StorageService();
  final SystemSettingsService _settingsService = SystemSettingsService();

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.initialConfig?.serverUrl ?? '');
    _apiKeyController = TextEditingController(text: widget.initialConfig?.apiKey ?? '');
    _deviceIdController = TextEditingController(text: widget.initialConfig?.deviceId ?? '');

    _loadNativeDeviceInfo();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _urlController.dispose();
    _apiKeyController.dispose();
    _deviceIdController.dispose();
    _apiService.dispose();
    super.dispose();
  }

  Future<void> _loadNativeDeviceInfo() async {
    try {
      final info = await _settingsService.getDeviceInfo();
      if (mounted) {
        setState(() {
          _deviceInfo = info;
          _isLoadingDeviceInfo = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingDeviceInfo = false);
      }
    }
  }

  DeviceConfig _buildCurrentConfig() {
    return DeviceConfig(
      serverUrl: _urlController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      deviceId: _deviceIdController.text.trim(),
    );
  }

  Future<void> _handleTestConnection() async {
    if (!_formKeyStep1.currentState!.validate()) {
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

  void _nextStep() {
    if (_currentStep == 0) {
      if (!_formKeyStep1.currentState!.validate()) return;
    } else if (_currentStep == 1) {
      if (!_formKeyStep2.currentState!.validate()) return;
    }

    if (_currentStep < _totalSteps - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOutCubic,
      );
      setState(() => _currentStep++);
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOutCubic,
      );
      setState(() => _currentStep--);
    }
  }

  Future<void> _handleSave() async {
    if (_urlController.text.trim().isEmpty ||
        _apiKeyController.text.trim().isEmpty ||
        _deviceIdController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vyplňte prosím všetky požadované údaje.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    final config = _buildCurrentConfig();
    await _storageService.saveConfig(config);
    await BackgroundService().schedulePeriodicReports();

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (widget.isEditing) {
      Navigator.of(context).pop(true);
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
    }
  }

  void _openBulkSetupDialog() {
    final theme = Theme.of(context);
    final bulkController = TextEditingController();
    DeviceConfig? parsedConfig;
    bool isTestingBulk = false;
    String? errorMessage;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (bottomSheetContext) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;

            void updateParsing(String val) {
              setModalState(() {
                errorMessage = null;
                parsedConfig = DeviceConfig.parseBulkSetupCode(val);
              });
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: bottomInset + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.outlineVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.flash_on_rounded, color: theme.colorScheme.primary, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hromadné nastavenie (Bulk Setup)',
                                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                'Syntax: adresaserveru-tabletkey-tabid',
                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: bulkController,
                      autofocus: true,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Bulk Setup Kód',
                        hintText: 'https://skola.sk/tabmonitor-secretkey123-TAB-01',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        prefixIcon: const Icon(Icons.qr_code_2_rounded),
                        suffixIcon: IconButton(
                          tooltip: 'Vložiť zo schránky',
                          icon: const Icon(Icons.content_paste_rounded),
                          onPressed: () async {
                            final data = await Clipboard.getData(Clipboard.kTextPlain);
                            if (data?.text != null && data!.text!.trim().isNotEmpty) {
                              bulkController.text = data.text!.trim();
                              updateParsing(data.text!.trim());
                            }
                          },
                        ),
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                      ),
                      onChanged: updateParsing,
                    ),
                    const SizedBox(height: 14),

                    // Live preview of parsed values
                    if (parsedConfig != null) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.green.withOpacity(0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.check_circle_rounded, color: Colors.green, size: 18),
                                const SizedBox(width: 6),
                                Text(
                                  'Kód bol úspešne rozpoznaný',
                                  style: TextStyle(
                                    color: Colors.green.shade800,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 16),
                            _buildParsedRow('Server URL:', parsedConfig!.serverUrl, Icons.link_rounded, theme),
                            const SizedBox(height: 6),
                            _buildParsedRow('API Kľúč:', '${parsedConfig!.apiKey.substring(0, parsedConfig!.apiKey.length.clamp(0, 8))}••••••••', Icons.key_rounded, theme),
                            const SizedBox(height: 6),
                            _buildParsedRow('Tablet ID:', parsedConfig!.deviceId, Icons.badge_rounded, theme),
                          ],
                        ),
                      ),
                    ] else if (bulkController.text.trim().isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline_rounded, color: theme.colorScheme.error, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Kód musí obsahovať server, kľúč a tablet ID oddelené pomlčkou (-) napr. server.sk-kluc-TAB01',
                                style: TextStyle(color: theme.colorScheme.onErrorContainer, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    if (errorMessage != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.withOpacity(0.3)),
                        ),
                        child: Text(
                          errorMessage!,
                          style: const TextStyle(color: Colors.red, fontSize: 13),
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: (parsedConfig == null || isTestingBulk)
                                ? null
                                : () {
                                    setState(() {
                                      _urlController.text = parsedConfig!.serverUrl;
                                      _apiKeyController.text = parsedConfig!.apiKey;
                                      _deviceIdController.text = parsedConfig!.deviceId;
                                      _lastTestResult = null;
                                    });
                                    Navigator.of(ctx).pop();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Údaje pre tablet "${parsedConfig!.deviceId}" boli vložené do sprievodcu.'),
                                      ),
                                    );
                                  },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Vyplniť polia'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: (parsedConfig == null || isTestingBulk)
                                ? null
                                : () async {
                                    setModalState(() {
                                      isTestingBulk = true;
                                      errorMessage = null;
                                    });

                                    final navigator = Navigator.of(context);
                                    final result = await _apiService.testConnection(parsedConfig!);
                                    if (!mounted || !ctx.mounted) return;

                                    if (result.isSuccess) {
                                      setState(() {
                                        _urlController.text = parsedConfig!.serverUrl;
                                        _apiKeyController.text = parsedConfig!.apiKey;
                                        _deviceIdController.text = parsedConfig!.deviceId;
                                      });

                                      await _storageService.saveConfig(parsedConfig!);
                                      await BackgroundService().schedulePeriodicReports();

                                      if (!mounted) return;
                                      if (ctx.mounted) {
                                        Navigator.of(ctx).pop();
                                      }

                                      if (widget.isEditing) {
                                        navigator.pop(true);
                                      } else {
                                        navigator.pushReplacement(
                                          MaterialPageRoute(builder: (_) => const DashboardScreen()),
                                        );
                                      }
                                    } else {
                                      setModalState(() {
                                        isTestingBulk = false;
                                        errorMessage = 'Chyba overenia: ${result.message}';
                                      });
                                    }
                                  },
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: isTestingBulk
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: M3ShapeMorphLoader(size: 20, color: Colors.white),
                                  )
                                : const Text('Použiť a dokončiť'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildParsedRow(String label, String value, IconData icon, ThemeData theme) {
    return Row(
      children: [
        Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String get _detectedDeviceName {
    final manufacturer = _deviceInfo['manufacturer']?.toString() ?? '';
    final model = _deviceInfo['model']?.toString() ?? '';
    if (manufacturer.isNotEmpty && model.isNotEmpty) {
      return '${manufacturer[0].toUpperCase()}${manufacturer.substring(1)} $model';
    } else if (model.isNotEmpty) {
      return model;
    }
    return 'Android Tablet';
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.isEditing ? 'Nastavenia klienta' : 'TabMonitor Sprievodca'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'v2.1.0',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
        elevation: 0,
        centerTitle: true,
        leading: widget.isEditing
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on_rounded),
            tooltip: 'Hromadné nastavenie (Bulk Setup)',
            onPressed: _openBulkSetupDialog,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // M3 Stepper Header
            _buildStepperHeader(theme),

            // Step Content Pages
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(), // Controlled via buttons
                onPageChanged: (idx) => setState(() => _currentStep = idx),
                children: [
                  _buildStep1Server(theme),
                  _buildStep2Device(theme),
                  _buildStep3Permissions(theme),
                  _buildStep4Finish(theme),
                ],
              ),
            ),

            // Bottom Navigation Actions
            _buildBottomBar(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildStepperHeader(ThemeData theme) {
    const titles = ['Server', 'Zariadenie', 'Povolenia', 'Hotovo'];
    const icons = [Icons.dns_rounded, Icons.tablet_rounded, Icons.security_rounded, Icons.check_circle_rounded];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.3))),
      ),
      child: Column(
        children: [
          Row(
            children: List.generate(_totalSteps, (i) {
              final isPassed = i < _currentStep;
              final isCurrent = i == _currentStep;

              return Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isPassed
                                  ? theme.colorScheme.primary
                                  : (isCurrent
                                      ? theme.colorScheme.primaryContainer
                                      : theme.colorScheme.surfaceContainerHighest),
                              border: Border.all(
                                color: isCurrent ? theme.colorScheme.primary : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: Center(
                              child: isPassed
                                  ? const Icon(Icons.check, size: 18, color: Colors.white)
                                  : Icon(
                                      icons[i],
                                      size: 16,
                                      color: isCurrent
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.onSurfaceVariant,
                                    ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            titles[i],
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                              color: isCurrent
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (i < _totalSteps - 1)
                      Container(
                        width: 16,
                        height: 2,
                        color: i < _currentStep
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outlineVariant.withOpacity(0.4),
                      ),
                  ],
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (_currentStep + 1) / _totalSteps,
              minHeight: 4,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  // STEP 1: SERVER & API KEY
  Widget _buildStep1Server(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKeyStep1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(Icons.cloud_sync_rounded, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Krok 1: Pripojenie k serveru',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Zadajte URL adresu servera a zdieľaný kľúč pre tablet.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Bulk Setup Quick Banner Card
            Card(
              elevation: 0,
              color: theme.colorScheme.primaryContainer.withOpacity(0.35),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.2)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.flash_on_rounded, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hromadné nastavenie (Bulk Setup)',
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Máte kód? (adresaserveru-tabletkey-tabid)',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.tonal(
                      onPressed: _openBulkSetupDialog,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      child: const Text('Zadať kód'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Server URL Field
            TextFormField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: 'Server URL',
                hintText: 'http://192.168.1.50:8080 alebo domena.sk',
                prefixIcon: const Icon(Icons.link_rounded),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Zadajte URL adresu servera';
                }
                final cleaned = val.trim().toLowerCase();
                if (!cleaned.startsWith('http://') && !cleaned.startsWith('https://')) {
                  if (!cleaned.contains('.')) {
                    return 'Zadajte platnú URL adresu alebo IP adresu s portom';
                  }
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // API Key Field
            TextFormField(
              controller: _apiKeyController,
              obscureText: _obscureApiKey,
              decoration: InputDecoration(
                labelText: 'Zdieľaný API kľúč',
                hintText: 'Kľúč z config.php na serveri',
                prefixIcon: const Icon(Icons.key_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_obscureApiKey ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscureApiKey = !_obscureApiKey),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Zadajte API kľúč';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),

            // Test Connection Button with M3 Morph Loader
            OutlinedButton.icon(
              onPressed: _isTesting ? null : _handleTestConnection,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: _isTesting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: M3ShapeMorphLoader(size: 22, strokeWidth: 2),
                    )
                  : const Icon(Icons.network_check_rounded),
              label: Text(_isTesting ? 'Overujem spojenie so serverom...' : 'Otestovať spojenie'),
            ),

            if (_lastTestResult != null) ...[
              const SizedBox(height: 16),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _lastTestResult!.isSuccess ? Colors.green.shade50 : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _lastTestResult!.isSuccess ? Colors.green.shade300 : Colors.red.shade300,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _lastTestResult!.isSuccess ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                      color: _lastTestResult!.isSuccess ? Colors.green.shade700 : Colors.red.shade700,
                      size: 26,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _lastTestResult!.isSuccess ? 'Server odpovedá úspešne!' : 'Chyba spojenia',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _lastTestResult!.isSuccess ? Colors.green.shade900 : Colors.red.shade900,
                            ),
                          ),
                          Text(
                            _lastTestResult!.message,
                            style: TextStyle(
                              fontSize: 12,
                              color: _lastTestResult!.isSuccess ? Colors.green.shade800 : Colors.red.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // STEP 2: DEVICE IDENTIFICATION & HARDWARE
  Widget _buildStep2Device(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKeyStep2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(Icons.devices_rounded, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Krok 2: Identifikácia zariadenia',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Zadajte ID tabletu podľa registrácie vo webovom paneli.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Live Detected Hardware Card (Zero hardcoded Lenovo, reads actual device!)
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.tablet_mac_rounded, color: theme.colorScheme.primary, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tvoje zariadenie',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _isLoadingDeviceInfo ? 'Zisťujem model...' : _detectedDeviceName,
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            _detectedAndroidVersion,
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Device ID Input
            TextFormField(
              controller: _deviceIdController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Tablet ID',
                hintText: 'napr. XX-01, TAB-02, TAB-15',
                prefixIcon: const Icon(Icons.badge_rounded),
                helperText: 'Toto ID musí byť zaregistrované administrátorom na webe.',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Zadajte Tablet ID (napr. XX-01)';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Quick Preset ID Chips
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['XX-01', 'XX-02', 'TAB-01', 'TAB-02', 'TAB-03'].map((sampleId) {
                return ActionChip(
                  label: Text(sampleId),
                  avatar: const Icon(Icons.add, size: 14),
                  onPressed: () {
                    setState(() {
                      _deviceIdController.text = sampleId;
                    });
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // STEP 3: SYSTEM PERMISSIONS & OPTIMIZATIONS
  Widget _buildStep3Permissions(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(Icons.security_rounded, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Krok 3: Systémové nastavenia',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Pre spoľahlivý beh na pozadí povoľte potrebné nastavenia.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          PermissionsChecklist(
            isServerVerified: _lastTestResult?.isSuccess == true,
            onTestServerConnection: _handleTestConnection,
          ),
        ],
      ),
    );
  }

  // STEP 4: REVIEW & FINISH
  Widget _buildStep4Finish(ThemeData theme) {
    final config = _buildCurrentConfig();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primaryContainer,
              ),
              child: const M3ShapeMorphLoader(
                size: 64,
                strokeWidth: 3.5,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Všetko je pripravené!',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Skontrolujte zhrnutie konfigurácie pred spustením monitorovania.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // Configuration Summary Card
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildSummaryRow('Tablet ID', config.deviceId.isEmpty ? 'Nezadané' : config.deviceId),
                  const Divider(height: 16),
                  _buildSummaryRow('Server', config.serverUrl.isEmpty ? 'Nezadané' : config.serverUrl),
                  const Divider(height: 16),
                  _buildSummaryRow('Zariadenie', _detectedDeviceName),
                  const Divider(height: 16),
                  _buildSummaryRow('Verzia klienta', 'v2.1.0'),
                  const Divider(height: 16),
                  _buildSummaryRow(
                    'Stav spojenia',
                    _lastTestResult?.isSuccess == true ? '🟢 Overené' : '🟡 Vyžaduje overenie',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          FilledButton.icon(
            onPressed: _isSaving ? null : _handleSave,
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.rocket_launch_rounded),
            label: Text(_isSaving ? 'Ukladám...' : 'Spustiť monitorovanie'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: Colors.grey)),
        Flexible(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  // BOTTOM NAVIGATION BAR
  Widget _buildBottomBar(ThemeData theme) {
    final isFirst = _currentStep == 0;
    final isLast = _currentStep == _totalSteps - 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.3))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (!isFirst)
            OutlinedButton.icon(
              onPressed: _previousStep,
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('Späť'),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            )
          else
            const SizedBox(width: 80),

          if (!isLast)
            FilledButton.icon(
              onPressed: _nextStep,
              label: const Text('Ďalej'),
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            )
          else
            const SizedBox.shrink(),
        ],
      ),
    );
  }
}
