import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sync/sync_service.dart';
import '../../sync/sync_settings.dart';
import '../../theme/app_theme.dart';

class SyncSettingsDialog extends ConsumerStatefulWidget {
  const SyncSettingsDialog({super.key});

  @override
  ConsumerState<SyncSettingsDialog> createState() => _SyncSettingsDialogState();
}

class _SyncSettingsDialogState extends ConsumerState<SyncSettingsDialog> {
  late final TextEditingController _url;
  late final TextEditingController _email;

  @override
  void initState() {
    super.initState();
    final current =
        ref.read(syncSettingsProvider).value ?? SyncSettings.defaults();
    _url = TextEditingController(text: current.serverUrl ?? '');
    _email = TextEditingController(text: current.email ?? '');
  }

  @override
  void dispose() {
    _url.dispose();
    _email.dispose();
    super.dispose();
  }

  String? _clean(String raw) => raw.trim().isEmpty ? null : raw.trim();

  Future<void> _save() async {
    final previous = ref.read(syncSettingsProvider).value;
    final next = SyncSettings(
      serverUrl: _clean(_url.text),
      email: _clean(_email.text),
    );
    final service = ref.read(syncServiceProvider.notifier);
    if (previous?.serverUrl != next.serverUrl) await service.resetCursor();
    await ref.read(syncSettingsProvider.notifier).save(next);
    if (mounted) Navigator.of(context).pop();
    service.syncNow();
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(syncServiceProvider);
    final settings = ref.watch(syncSettingsProvider).value;
    return AlertDialog(
      title: const Text('Sync'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('sync-url'),
              controller: _url,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Server URL',
                hintText: 'https://anki.example.com',
                helperText: 'Leave empty to keep data on this device only.',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('sync-email'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email (development only)',
                helperText:
                    'Sent as Remote-Email when no auth proxy sets it for you.',
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _describe(status),
              key: const Key('sync-status'),
              style: TextStyle(
                fontSize: 13,
                color: status.phase == SyncPhase.error
                    ? AppColors.danger
                    : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('sync-now'),
          onPressed:
              (settings?.enabled ?? false) && status.phase != SyncPhase.syncing
              ? ref.read(syncServiceProvider.notifier).syncNow
              : null,
          child: const Text('Sync now'),
        ),
        FilledButton(
          key: const Key('sync-save'),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  static String _describe(SyncStatus status) => switch (status.phase) {
    SyncPhase.off => 'Sync is off.',
    SyncPhase.syncing => 'Syncing…',
    SyncPhase.idle => 'Last synced ${formatClock(status.lastSyncAt)}.',
    SyncPhase.error => status.error ?? 'Sync failed.',
  };
}

String formatClock(DateTime? time) {
  if (time == null) return 'never';
  final local = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}';
}
