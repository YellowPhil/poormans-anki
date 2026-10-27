import 'package:anki_core/anki_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poormans_anki/data/collection_store.dart';
import 'package:poormans_anki/data/seed_data.dart';
import 'package:poormans_anki/sync/sync_client.dart';
import 'package:poormans_anki/sync/sync_service.dart';

import 'devices.dart';

void main() {
  late World world;
  late Map<String, MemorySyncServer> servers;
  final devices = <Device>[];

  setUp(() {
    world = World();
    servers = {'http://a': MemorySyncServer(), 'http://b': MemorySyncServer()};
  });

  tearDown(() {
    for (final d in devices) {
      d.dispose();
    }
    devices.clear();
  });

  MemorySyncServer server() => servers['http://a']!;

  Device device({Duration skew = Duration.zero}) {
    final d = Device(world, servers, skew: skew);
    devices.add(d);
    return d;
  }

  Future<Device> online({Duration skew = Duration.zero}) async {
    final d = device(skew: skew);
    await d.boot(syncUrl: 'http://a');
    await settle([d]);
    return d;
  }

  Future<void> expectConverged(List<Device> ds, {MemorySyncServer? on}) async {
    final expected = await serverFingerprint(on ?? server());
    for (final d in ds) {
      expect(d.status.phase, SyncPhase.idle, reason: d.status.error);
      expect((await d.store).pendingCount, 0);
      expect(await deviceFingerprint(d), expected);
    }
  }

  test('first device seeds the empty server exactly once', () async {
    final a = await online();
    expect(a.decks.map((d) => d.name), ['Capitals', 'Spanish basics']);
    final snap = await server().collection('me@x.io');
    expect(snap.collection.decks.expand((d) => d.cards), hasLength(20));
    await expectConverged([a]);
  });

  test('second device downloads the collection and does not seed', () async {
    final a = await online();
    final b = await online();
    expect(b.cards, hasLength(20));
    expect(b.client().snapshotCalls, 1);
    await expectConverged([a, b]);
  });

  test('a deck and card added on A appear on B', () async {
    final a = await online();
    final b = await online();
    world.tick();
    final deck = await a.notifier.createDeck('Verbs');
    await a.notifier.addCard(deck.id, 'ser', 'to be');
    await settle([a, b]);
    expect(b.deck('Verbs').cards.single.back, 'to be');
    await expectConverged([a, b]);
  });

  test('offline reviews on two devices are both kept', () async {
    final a = await online();
    final b = await online();
    final cardId = a.cards.first.id;
    a.offline = true;
    b.offline = true;
    world.tick(const Duration(hours: 1));
    await a.notifier.rateCard(a.cardById(cardId)!, Rating.good);
    world.tick(const Duration(days: 3));
    await b.notifier.rateCard(b.cardById(cardId)!, Rating.hard);
    a.offline = false;
    b.offline = false;
    await settle([a, b]);
    final snap = await server().collection('me@x.io');
    expect(snap.collection.reviewsOf(cardId).map((r) => r.rating), [
      Rating.good,
      Rating.hard,
    ]);
    expect(
      a.cardById(cardId)!.scheduling.toMap(),
      b.cardById(cardId)!.scheduling.toMap(),
    );
    await expectConverged([a, b]);
  });

  test('edit on one device and removal on another ends removed', () async {
    final a = await online();
    final b = await online();
    final cardId = a.cards.first.id;
    a.offline = true;
    b.offline = true;
    world.tick();
    await a.notifier.updateCard(a.cardById(cardId)!, 'edited', 'x');
    await b.notifier.deleteCard(b.cardById(cardId)!);
    a.offline = false;
    b.offline = false;
    await settle([a, b]);
    expect(a.cardById(cardId), isNull);
    expect(b.cardById(cardId), isNull);
    await expectConverged([a, b]);
  });

  test('server order decides concurrent edits, not device clocks', () async {
    final a = await online();
    final b = await online(skew: const Duration(days: -1));
    final cardId = a.cards.first.id;
    world.tick();
    await a.notifier.updateCard(a.cardById(cardId)!, 'from A', 'x');
    await a.sync();
    world.tick();
    await b.notifier.updateCard(b.cardById(cardId)!, 'from B', 'x');
    await settle([b, a]);
    expect(a.cardById(cardId)!.front, 'from B');
    expect(b.cardById(cardId)!.front, 'from B');
    await expectConverged([a, b]);
  });

  test('reviews from a skewed clock still converge to one schedule', () async {
    final a = await online();
    final b = await online(skew: const Duration(hours: -7));
    final cardId = a.cards.first.id;
    for (var i = 0; i < 4; i++) {
      world.tick(const Duration(days: 2));
      final d = i.isEven ? a : b;
      await d.notifier.rateCard(d.cardById(cardId)!, Rating.good);
      await d.sync();
    }
    await settle([a, b]);
    expect(
      (await server().collection('me@x.io')).collection.reviewsOf(cardId),
      hasLength(4),
    );
    await expectConverged([a, b]);
  });

  test(
    'devices seeded independently with sync off merge into one copy',
    () async {
      final a = device();
      await a.boot();
      world.tick(const Duration(hours: 2));
      final b = device();
      await b.boot();
      expect(a.cards, hasLength(20));
      expect(b.cards, hasLength(20));
      final cardId = seedId('Capitals/France');
      await a.notifier.rateCard(a.cardById(cardId)!, Rating.good);
      world.tick();
      await b.notifier.rateCard(b.cardById(cardId)!, Rating.easy);
      await a.setSync('http://a');
      await b.setSync('http://a');
      await settle([a, b]);
      expect(a.decks.map((d) => d.name), ['Capitals', 'Spanish basics']);
      expect(a.cards, hasLength(20));
      final snap = await server().collection('me@x.io');
      expect(snap.collection.decks.expand((d) => d.cards), hasLength(20));
      expect(snap.collection.reviewsOf(cardId), hasLength(2));
      await expectConverged([a, b]);
    },
  );

  test('fresh sync-enabled devices racing to seed converge', () async {
    final a = device();
    final b = device();
    await a.boot(syncUrl: 'http://a');
    await b.boot(syncUrl: 'http://a');
    await a.sync();
    await b.sync();
    await settle([a, b]);
    expect(a.cards, hasLength(20));
    expect(b.cards, hasLength(20));
    await expectConverged([a, b]);
  });

  test('an edit made while a sync is in flight survives the pull', () async {
    final a = await online();
    final b = await online();
    final cardId = a.cards.first.id;
    world.tick();
    await b.notifier.updateCard(b.cardById(cardId)!, 'from B', 'x');
    await b.sync();
    a.client().beforeReply = () =>
        a.notifier.rateCard(a.cardById(cardId)!, Rating.again);
    await a.sync();
    expect(a.cardById(cardId)!.front, 'from B');
    expect((await a.store).view.reviewsOf(cardId), hasLength(1));
    expect((await a.store).pendingCount, 1);
    await settle([a, b]);
    expect(
      (await server().collection('me@x.io')).collection.reviewsOf(cardId),
      hasLength(1),
    );
    await expectConverged([a, b]);
  });

  test('a lost reply is resent and de-duplicated by the server', () async {
    final a = await online();
    final cardId = a.cards.first.id;
    await a.notifier.rateCard(a.cardById(cardId)!, Rating.good);
    a.client().beforeReply = () async =>
        throw const SyncException('connection reset');
    await a.sync();
    expect(a.status.phase, SyncPhase.error);
    expect((await a.store).pendingCount, 1);
    await a.sync();
    expect(
      (await server().collection('me@x.io')).collection.reviewsOf(cardId),
      hasLength(1),
    );
    await expectConverged([a]);
  });

  test('restart keeps synced data and unsent ops', () async {
    final a = await online();
    final b = await online();
    a.offline = true;
    world.tick();
    final deck = await a.notifier.createDeck('Offline');
    final card = await a.notifier.addCard(deck.id, 'q', 'a');
    await a.notifier.rateCard(card, Rating.good);
    await a.restart();
    a.offline = true;
    expect(a.cards, hasLength(21));
    expect((await a.store).pendingCount, 3);
    expect((await a.store).view.reviewsOf(card.id), hasLength(1));
    a.offline = false;
    await settle([a, b]);
    await b.restart();
    await b.sync();
    expect(b.deck('Offline').cards.single.front, 'q');
    await expectConverged([a, b]);
  });

  test('restart of a synced device needs no snapshot', () async {
    final a = await online();
    final calls = a.client().snapshotCalls;
    await a.restart();
    await a.sync();
    expect(a.client().snapshotCalls, calls);
    await expectConverged([a]);
  });

  test('switching server uploads the whole collection there', () async {
    final a = await online();
    final cardId = a.cards.first.id;
    world.tick();
    await a.notifier.rateCard(a.cardById(cardId)!, Rating.good);
    await a.notifier.updateCard(a.cardById(cardId)!, 'edited', 'x');
    await a.sync();
    await a.setSync('http://b');
    await a.sync();
    final onB = servers['http://b']!;
    expect(await serverFingerprint(onB), await serverFingerprint(server()));
    await expectConverged([a], on: onB);
    final b = device();
    await b.boot(syncUrl: 'http://b');
    await settle([b]);
    expect(b.cardById(cardId)!.front, 'edited');
    await expectConverged([a, b], on: onB);
  });

  test('a compacted log forces a snapshot and keeps unsent ops', () async {
    final a = await online();
    final b = await online();
    b.offline = true;
    world.tick();
    await b.notifier.createDeck('From B');
    for (var i = 0; i < 5; i++) {
      await a.notifier.createDeck('A$i');
    }
    await a.sync();
    final head = (await server().collection('me@x.io')).seq;
    await server().compact('me@x.io', head);
    final before = b.client().snapshotCalls;
    b.offline = false;
    await settle([a, b]);
    expect(b.client().snapshotCalls, before + 1);
    expect(b.decks.map((d) => d.name), containsAll(['A4', 'From B']));
    await expectConverged([a, b]);
  });

  test('an unreachable server reports an error and keeps local data', () async {
    final a = await online();
    a.offline = true;
    world.tick();
    await a.notifier.createDeck('Pending');
    await a.sync();
    expect(a.status.phase, SyncPhase.error);
    expect(a.status.error, contains('offline'));
    expect(a.deck('Pending').cards, isEmpty);
    a.offline = false;
    await a.sync();
    expect(a.status.phase, SyncPhase.idle);
    await expectConverged([a]);
  });

  test('outbox file is the only state needed to resend', () async {
    final a = await online();
    a.offline = true;
    await a.notifier.createDeck('X');
    expect(a.files.files[CollectionStore.outboxPath], contains('"X"'));
  });
}
