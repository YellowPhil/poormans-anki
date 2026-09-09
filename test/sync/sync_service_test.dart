import 'dart:convert';

import 'package:anki_core/anki_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:poormans_anki/data/deck_repository.dart';
import 'package:poormans_anki/scheduler/review_scheduler.dart';
import 'package:poormans_anki/state/providers.dart';
import 'package:poormans_anki/storage/memory_file_store.dart';
import 'package:poormans_anki/sync/sync_client.dart';
import 'package:poormans_anki/sync/sync_service.dart';
import 'package:poormans_anki/sync/sync_settings.dart';

class MemorySyncClient implements SyncClient {
  MemorySyncClient(this.server, this.user, {this.offline = false});

  final MemorySyncServer server;
  final String user;
  bool offline;

  @override
  Future<SyncResponse> sync(SyncRequest request) {
    if (offline) throw const SyncException('offline');
    return server.sync(user, request);
  }
}

void main() {
  var now = DateTime.utc(2026, 9, 8, 12);
  void tick() => now = now.add(const Duration(minutes: 1));

  late MemorySyncServer server;

  setUp(() => server = MemorySyncServer(clock: () => now));

  Future<(ProviderContainer, MemoryFileStore, MemorySyncClient)> device({
    bool enabled = true,
  }) async {
    final store = MemoryFileStore();
    if (enabled) {
      await store.write(
        'sync/settings.json',
        jsonEncode(const SyncSettings(serverUrl: 'http://test').toJson()),
      );
    }
    final client = MemorySyncClient(server, 'me@x.io');
    final container = ProviderContainer(
      overrides: [
        fileStoreProvider.overrideWithValue(store),
        clockProvider.overrideWithValue(() => now),
        schedulerProvider.overrideWithValue(
          ReviewScheduler(fsrs.Scheduler(enableFuzzing: false)),
        ),
        syncClientFactoryProvider.overrideWithValue((_) => client),
      ],
    );
    addTearDown(container.dispose);
    return (container, store, client);
  }

  Future<List<Deck>> decksOf(ProviderContainer c) =>
      c.read(decksProvider.future);

  Future<void> sync(ProviderContainer c) =>
      c.read(syncServiceProvider.notifier).syncNow();

  test('sync stays off without a server URL', () async {
    final (c, _, _) = await device(enabled: false);
    expect(await decksOf(c), isNotEmpty);
    await sync(c);
    expect(c.read(syncServiceProvider).phase, SyncPhase.off);
  });

  test(
    'first device seeds after an empty pull; second device inherits',
    () async {
      final (a, _, _) = await device();
      expect(await decksOf(a), isEmpty);
      await sync(a);
      final seeded = await decksOf(a);
      expect(seeded, hasLength(2));
      tick();
      await sync(a);

      final (b, _, _) = await device();
      await sync(b);
      final inherited = await decksOf(b);
      expect(inherited.map((d) => d.id), seeded.map((d) => d.id));
      expect(b.read(syncServiceProvider).phase, SyncPhase.idle);
    },
  );

  test('edits on two devices converge card-wise; reviews propagate', () async {
    final (a, storeA, _) = await device();
    await sync(a);
    tick();
    await sync(a);
    final (b, storeB, _) = await device();
    await sync(b);

    tick();
    final deckA = (await decksOf(a)).first;
    await a
        .read(decksProvider.notifier)
        .addCard(deckA.id, 'added on A', 'back');
    tick();
    final target = (await decksOf(b)).first.cards.first;
    await b.read(decksProvider.notifier).rateCard(target, Rating.good);

    tick();
    await sync(a);
    tick();
    await sync(b);
    tick();
    await sync(a);

    final finalA = (await decksOf(a)).first;
    final finalB = (await decksOf(b)).first;
    expect(sameDeck(finalA, finalB), isTrue);
    expect(finalA.cards.map((c) => c.front), contains('added on A'));
    expect(
      finalA.cards.firstWhere((c) => c.id == target.id).scheduling.lastReview,
      isNotNull,
    );
    expect(await DeckRepository(storeA).loadReviews(), hasLength(1));
    expect(await DeckRepository(storeB).loadReviews(), hasLength(1));
  });

  test('a card deleted on one device disappears on the other', () async {
    final (a, _, _) = await device();
    await sync(a);
    tick();
    await sync(a);
    final (b, _, _) = await device();
    await sync(b);

    tick();
    final victim = (await decksOf(a)).first.cards.first;
    await a.read(decksProvider.notifier).deleteCard(victim);
    tick();
    await sync(a);
    tick();
    await sync(b);
    final deckB = (await decksOf(b)).first;
    expect(deckB.cards.map((c) => c.id), isNot(contains(victim.id)));
    expect(deckB.removedCards.keys, contains(victim.id));
  });

  test('server failure reports an error and keeps local data', () async {
    final (a, _, client) = await device();
    await sync(a);
    tick();
    await sync(a);
    final before = await decksOf(a);
    client.offline = true;
    tick();
    await sync(a);
    final status = a.read(syncServiceProvider);
    expect(status.phase, SyncPhase.error);
    expect(status.error, contains('offline'));
    expect(await decksOf(a), same(before));
  });
}
