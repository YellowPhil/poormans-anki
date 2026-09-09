import 'dart:async';
import 'dart:convert';

import 'package:anki_core/anki_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../state/providers.dart';
import '../storage/file_store.dart';
import 'sync_client.dart';
import 'sync_settings.dart';

enum SyncPhase { off, idle, syncing, error }

class SyncStatus {
  const SyncStatus({required this.phase, this.lastSyncAt, this.error});

  final SyncPhase phase;
  final DateTime? lastSyncAt;
  final String? error;
}

/// [cursor] is the server's watermark; [lastPushAt] is the local clock when
/// the last push was assembled. Anything stamped at or after it is pending;
/// the inclusive bound re-sends same-instant writes, which the server
/// de-duplicates.
class SyncCursor {
  const SyncCursor({this.cursor, this.lastPushAt});

  factory SyncCursor.fromJson(Map<String, dynamic> json) => SyncCursor(
    cursor: _date(json['cursor']),
    lastPushAt: _date(json['lastPushAt']),
  );

  final DateTime? cursor;
  final DateTime? lastPushAt;

  Map<String, dynamic> toJson() => {
    if (cursor != null) 'cursor': cursor!.toIso8601String(),
    if (lastPushAt != null) 'lastPushAt': lastPushAt!.toIso8601String(),
  };

  static DateTime? _date(Object? raw) =>
      raw is String ? DateTime.parse(raw).toUtc() : null;
}

const _settingsPath = 'sync/settings.json';
const _cursorPath = 'sync/state.json';

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

/// Push local changes, pull remote ones, merge. One run at a time; a request
/// arriving mid-run queues exactly one follow-up run.
class SyncService extends Notifier<SyncStatus> {
  static const debounce = Duration(milliseconds: 1500);

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
    final store = ref.read(fileStoreProvider);
    try {
      final cursor = await _loadCursor(store);
      final decks = await ref.read(decksProvider.future);
      final repo = ref.read(deckRepositoryProvider);
      final localReviews = await repo.loadReviews();
      final lastPush = cursor.lastPushAt;
      bool pending(DateTime t) => lastPush == null || !t.isBefore(lastPush);
      final pushAt = ref.read(clockProvider)();
      final response = await ref
          .read(syncClientFactoryProvider)(settings)
          .sync(
            SyncRequest(
              since: cursor.cursor,
              decks: [
                for (final d in decks)
                  if (pending(d.updatedAt)) d,
              ],
              reviews: [
                for (final r in localReviews)
                  if (pending(r.reviewedAt)) r,
              ],
            ),
          );
      await ref
          .read(decksProvider.notifier)
          .applyRemote(response.decks, response.deletedDecks);
      final known = {for (final r in localReviews) r.key};
      for (final r in response.reviews) {
        if (known.add(r.key)) await repo.appendReview(r);
      }
      await store.write(
        _cursorPath,
        jsonEncode(
          SyncCursor(cursor: response.cursor, lastPushAt: pushAt).toJson(),
        ),
      );
      if (cursor.cursor == null) {
        await ref.read(decksProvider.notifier).seedIfEmpty();
      }
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

  Future<void> resetCursor() => ref.read(fileStoreProvider).delete(_cursorPath);

  Future<SyncCursor> _loadCursor(FileStore store) async {
    final raw = await store.read(_cursorPath);
    if (raw == null) return const SyncCursor();
    return SyncCursor.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}
