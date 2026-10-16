import 'package:flutter/material.dart';

/// Modal bottom sheet explaining Android 15 background execution behavior.
class BackgroundInfoSheet extends StatelessWidget {
  const BackgroundInfoSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const BackgroundInfoSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
              Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.blueAccent, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Android 15 Background Execution',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Card(
                color: Colors.amber.shade50,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.amber.shade200),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Why exact 5-minute background intervals are impossible without draining the battery:',
                          style: TextStyle(
                            color: Colors.amber.shade900,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _buildSection(
                icon: Icons.timer_outlined,
                title: '1. WorkManager 15-Minute Minimum',
                body:
                    'Google Android OS imposes a hard minimum periodic interval of 15 minutes for background workers (PeriodicWorkRequest.MIN_PERIODIC_INTERVAL_MILLIS). Exact intervals under 15 minutes are blocked by the OS.',
              ),
              _buildSection(
                icon: Icons.bedtime_outlined,
                title: '2. Doze Mode & Maintenance Windows',
                body:
                    'When a tablet is unplugged and motionless with screen off, Android 15 enters "Doze Mode". Background tasks are suspended and only allowed to execute during sporadic "maintenance windows" (e.g., every 15 to 60 minutes) to conserve battery life.',
              ),
              _buildSection(
                icon: Icons.tablet_android,
                title: '3. Lenovo Tab K11 Power Management',
                body:
                    'Lenovo\'s custom Android build includes aggressive background app killing. To ensure TabMonitor can report periodically, configure the tablet settings:\n'
                    '• Go to Android Settings > Apps > TabMonitor > Battery.\n'
                    '• Select "Unrestricted" instead of "Optimized".\n'
                    '• Turn off "Pause app activity if unused".',
              ),
              _buildSection(
                icon: Icons.sync,
                title: '4. Active Foreground Reporting',
                body:
                    'While the TabMonitor app is open in the foreground, a high-frequency live timer reports battery status every 5 minutes and immediately upon power plug/unplug events.',
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.check),
                label: const Text('Understood'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSection({
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Colors.blue.shade50,
            child: Icon(icon, size: 18, color: Colors.blue.shade700),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(color: Colors.grey.shade800, fontSize: 13, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
