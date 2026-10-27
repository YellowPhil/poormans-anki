import 'dart:convert';

import 'package:anki_core/anki_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poormans_anki/data/collection_store.dart';
import 'package:poormans_anki/state/decks_notifier.dart';
import 'package:poormans_anki/state/providers.dart';
import 'package:poormans_anki/storage/memory_file_store.dart';
import 'package:poormans_anki/sync/sync_client.dart';
import 'package:poormans_anki/sync/sync_service.dart';
import 'package:poormans_anki/sync/sync_settings.dart';

/// Shared wall clock; each [Device] reads it with its own skew.
class World {
  DateTime now = DateTime.utc(2026, 9, 8, 12);

  void tick([Duration by = const Duration(minutes: 1)]) => now = now.add(by);
}

class FakeClient implements SyncClient {
  FakeClient(this.server, this.user);

  final MemorySyncServer server;
  final String user;
  bool offline = false;
  int syncCalls = 0;
  int snapshotCalls = 0;

  /// Runs after the server answered and before the device sees the answer.
  Future<void> Function()? beforeReply;

  @override
  Future<SyncPull> sync(SyncPush push) async {
    if (offline) throw const SyncException('offline');
    syncCalls++;
    final pull = await server.sync(user, push);
    final hook = beforeReply;
    beforeReply = null;
    if (hook != null) await hook();
    return pull;
  }

  @override
  Future<CollectionSnapshot> collection() async {
    if (offline) throw const SyncException('offline');
    snapshotCalls++;
    return server.collection(user);
  }
}

/// One app installation: its files outlive [restart]; its container does not.
class Device {
  Device(
    this.world,
    Map<String, MemorySyncServer> servers, {
    this.skew = Duration.zero,
    this.user = 'me@x.io',
    this.clientFactory,
  }) : _servers = servers;

  /// Replaces the in-process [FakeClient]s, e.g. with a real HTTP client.
  final SyncClient Function(SyncSettings)? clientFactory;

  final World world;
  final Map<String, MemorySyncServer> _servers;
  final Duration skew;
  final String user;
  final files = MemoryFileStore();
  final clients = <String, FakeClient>{};
  ProviderContainer? _container;

  ProviderContainer get container => _container!;

  FakeClient client([String url = 'http://a']) =>
      clients.putIfAbsent(url, () => FakeClient(_servers[url]!, user));

  set offline(bool value) {
    for (final url in _servers.keys) {
      client(url).offline = value;
    }
  }

  Future<void> boot({String? syncUrl}) async {
    if (syncUrl != null) {
      await files.write(
        'sync/settings.json',
        jsonEncode(SyncSettings(serverUrl: syncUrl, email: user).toJson()),
      );
    }
    _container = ProviderContainer(
      overrides: [
        fileStoreProvider.overrideWithValue(files),
        clockProvider.overrideWithValue(() => world.now.add(skew)),
        syncClientFactoryProvider.overrideWithValue(
          clientFactory ?? (settings) => client(settings.serverUrl!),
        ),
      ],
    );
    await container.read(decksProvider.future);
  }

  Future<void> restart() async {
    _container?.dispose();
    await boot();
  }

  void dispose() => _container?.dispose();

  Future<void> setSync(String? url) async {
    await container
        .read(syncSettingsProvider.notifier)
        .save(SyncSettings(serverUrl: url, email: user));
  }

  Future<void> sync() => container.read(syncServiceProvider.notifier).syncNow();

  SyncStatus get status => container.read(syncServiceProvider);

  Future<CollectionStore> get store =>
      container.read(collectionStoreProvider.future);

  List<Deck> get decks => container.read(decksProvider).value ?? const [];

  Deck deck(String name) => decks.firstWhere((d) => d.name == name);

  Flashcard card(String front) =>
      [for (final d in decks) ...d.cards].firstWhere((c) => c.front == front);

  Iterable<Flashcard> get cards => [for (final d in decks) ...d.cards];

  Flashcard? cardById(String id) => cards.where((c) => c.id == id).firstOrNull;

  DecksNotifier get notifier => container.read(decksProvider.notifier);
}

/// Rows plus every card's derived schedule: equal fingerprints mean the user
/// sees the same collection.
Map<String, dynamic> fingerprint(Collection c) => {
  ...c.toJson(),
  'schedule': {
    for (final d in c.decks)
      for (final card in d.cards) card.id: card.scheduling.toMap(),
  },
};

Future<Map<String, dynamic>> serverFingerprint(
  MemorySyncServer server, [
  String user = 'me@x.io',
]) async => fingerprint(
  (await server.collection(user)).collection.rescheduled(CardScheduler()),
);

Future<Map<String, dynamic>> deviceFingerprint(Device d) async =>
    fingerprint((await d.store).view);

/// Three passes let every device push, then observe every other push.
Future<void> settle(Iterable<Device> devices) async {
  for (var i = 0; i < 3; i++) {
    for (final d in devices) {
      await d.sync();
    }
  }
}
