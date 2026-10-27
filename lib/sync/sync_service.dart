import 'dart:async';
import 'dart:convert';

import 'package:anki_core/anki_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../state/providers.dart';
import 'sync_client.dart';
import 'sync_settings.dart';

enum SyncPhase { off, idle, syncing, error }

class SyncStatus {
  const SyncStatus({required this.phase, this.lastSyncAt, this.error});

  final SyncPhase phase;
  final DateTime? lastSyncAt;
  final String? error;
}

const _settingsPath = 'sync/settings.json';

class SyncSettingsNotifier extends AsyncNotifier<SyncSettings> {
  @override
  Future<SyncSettings> build() async {
    final raw = await ref.watch(fileStoreProvider).read(_settingsPath);
    if (raw == null) return SyncSettings.defaults();
    return SyncSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> save(SyncSettings settings) async {
    await ref
        .read(fileStoreProvider)
        .write(_settingsPath, jsonEncode(settings.toJson()));
    state = AsyncData(settings);
  }
}

final syncSettingsProvider =
    AsyncNotifierProvider<SyncSettingsNotifier, SyncSettings>(
      SyncSettingsNotifier.new,
    );

final syncClientFactoryProvider = Provider<SyncClient Function(SyncSettings)>(
  (_) =>
      (settings) => HttpSyncClient(
        http.Client(),
        settings.serverUrl!,
        email: settings.email,
      ),
);

final syncServiceProvider = NotifierProvider<SyncService, SyncStatus>(
  SyncService.new,
);

/// Push the outbox, pull ops after the cursor, rebase. One run at a time; a
/// request arriving mid-run queues exactly one follow-up run.
class SyncService extends Notifier<SyncStatus> {
  static const debounce = Duration(milliseconds: 1500);
  static const _maxRounds = 1000;

  Timer? _debounce;
  Future<void>? _inFlight;
  bool _runAgain = false;

  @override
  SyncStatus build() {
    ref.onDispose(() => _debounce?.cancel());
    return const SyncStatus(phase: SyncPhase.off);
  }

  void schedule() {
    if (!(ref.read(syncSettingsProvider).value?.enabled ?? false)) return;
    _debounce?.cancel();
    _debounce = Timer(debounce, syncNow);
  }

  Future<void> syncNow() {
    _debounce?.cancel();
    if (_inFlight case final running?) {
      _runAgain = true;
      return running;
    }
    final run = _run().whenComplete(() {
      _inFlight = null;
      if (_runAgain) {
        _runAgain = false;
        syncNow();
      }
    });
    _inFlight = run;
    return run;
  }

  Future<void> _run() async {
    final settings = await ref.read(syncSettingsProvider.future);
    if (!settings.enabled) {
      state = const SyncStatus(phase: SyncPhase.off);
      return;
    }
    state = SyncStatus(phase: SyncPhase.syncing, lastSyncAt: state.lastSyncAt);
    try {
      final store = await ref.read(collectionStoreProvider.future);
      final key = targetKey(settings);
      if (store.attachedTo != key) await store.rebind(key);
      final client = ref.read(syncClientFactoryProvider)(settings);
      final fresh = store.seq == 0;
      if (fresh) await store.applySnapshot(await client.collection());
      for (var round = 0; round < _maxRounds; round++) {
        final batch = await store.pending(SyncPush.maxOps);
        final SyncPull pull;
        try {
          pull = await client.sync(
            SyncPush(clientId: store.clientId, since: store.seq, ops: batch),
          );
        } on CursorExpired {
          await store.applySnapshot(await client.collection());
          continue;
        }
        await store.applyPull(pull);
        if (!pull.more && batch.length < SyncPush.maxOps) break;
      }
      if (fresh) await ref.read(decksProvider.notifier).seedIfEmpty();
      state = SyncStatus(
        phase: SyncPhase.idle,
        lastSyncAt: ref.read(clockProvider)(),
      );
    } on Object catch (e) {
      state = SyncStatus(
        phase: SyncPhase.error,
        lastSyncAt: state.lastSyncAt,
        error: '$e',
      );
    }
  }

  /// A different server or identity is a different collection.
  static String targetKey(SyncSettings settings) =>
      '${settings.serverUrl!.trim()}|${settings.email?.trim() ?? ''}';
}
