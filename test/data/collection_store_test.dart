import 'dart:async';
import 'dart:convert';

import 'package:anki_core/anki_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poormans_anki/data/collection_store.dart';
import 'package:poormans_anki/data/seed_data.dart';
import 'package:poormans_anki/storage/file_store.dart';
import 'package:poormans_anki/storage/memory_file_store.dart';

/// Fails the next write or append to [failPath], modelling a crash or a full
/// disk at that exact step.
class FaultyFileStore implements FileStore {
  FaultyFileStore(this.inner);

  final MemoryFileStore inner;
  String? failPath;
  Completer<void>? gate;

  void _maybeFail(String path) {
    if (path == failPath) {
      failPath = null;
      throw StateError('injected failure writing $path');
    }
  }

  @override
  Future<List<String>> list(String dir) => inner.list(dir);

  @override
  Future<String?> read(String path) => inner.read(path);

  @override
  Future<void> write(String path, String contents) async {
    if (gate case final g?) await g.future;
    _maybeFail(path);
    await inner.write(path, contents);
  }

  @override
  Future<void> append(String path, String line) async {
    _maybeFail(path);
    await inner.append(path, line);
  }

  @override
  Future<void> delete(String path) => inner.delete(path);
}

final t0 = DateTime.utc(2026, 9, 8, 12);
var _n = 0;
String newId() => 'id-${_n++}';

DeckCreated deckOp(String id) =>
    DeckCreated(id: newId(), issuedAt: t0, deckId: id, name: 'Deck $id');

CardAdded cardOp(String id, String deckId) => CardAdded(
  id: newId(),
  issuedAt: t0.add(const Duration(seconds: 1)),
  cardId: id,
  deckId: deckId,
  front: 'front $id',
  back: 'back',
);

CardReviewed reviewOp(String cardId, {int minutes = 5}) => CardReviewed(
  id: newId(),
  issuedAt: t0.add(Duration(minutes: minutes)),
  cardId: cardId,
  deckId: 'd1',
  rating: Rating.good,
  reviewedAt: t0.add(Duration(minutes: minutes)),
);

Future<CollectionStore> openStore(
  FileStore files, {
  int compactAt = 256,
}) async {
  final store = CollectionStore(
    files,
    scheduler: CardScheduler(),
    newId: newId,
    localCompactAt: compactAt,
  );
  await store.open();
  return store;
}

Map<String, dynamic> fingerprint(Collection c) => {
  ...c.toJson(),
  'due': {
    for (final d in c.decks)
      for (final card in d.cards) card.id: card.due.toIso8601String(),
  },
};

void main() {
  late MemoryFileStore files;
  setUp(() => files = MemoryFileStore());

  group('persistence', () {
    test('dispatched ops survive a restart as pending ops', () async {
      final store = await openStore(files);
      await store.rebind('srv');
      await store.dispatchAll([deckOp('d1'), cardOp('c1', 'd1')]);
      await store.dispatch(reviewOp('c1'));

      final reopened = await openStore(files);
      expect(reopened.clientId, store.clientId);
      expect(reopened.attachedTo, 'srv');
      expect(reopened.pendingCount, 3);
      expect(fingerprint(reopened.view), fingerprint(store.view));
      expect(reopened.view.reviews, hasLength(1));
    });

    test('applyPull persists base and seq and drops acked ops', () async {
      final server = MemorySyncServer();
      final store = await openStore(files);
      await store.rebind('srv');
      await store.dispatchAll([deckOp('d1'), cardOp('c1', 'd1')]);
      final pull = await server.sync(
        'u',
        SyncPush(clientId: store.clientId, ops: await store.pending(500)),
      );
      await store.applyPull(pull);
      expect(store.seq, 2);
      expect(store.pendingCount, 0);

      final reopened = await openStore(files);
      expect(reopened.seq, 2);
      expect(reopened.pendingCount, 0);
      expect(reopened.view.decks.single.cards.single.id, 'c1');
      expect(fingerprint(reopened.view), fingerprint(store.view));
    });

    test(
      'crash between base and outbox writes resends; server dedupes',
      () async {
        final server = MemorySyncServer();
        final faulty = FaultyFileStore(files);
        final store = await openStore(faulty);
        await store.rebind('srv');
        await store.dispatchAll([
          deckOp('d1'),
          cardOp('c1', 'd1'),
          reviewOp('c1'),
        ]);
        final pull = await server.sync(
          'u',
          SyncPush(clientId: store.clientId, ops: await store.pending(500)),
        );
        faulty.failPath = CollectionStore.outboxPath;
        await expectLater(store.applyPull(pull), throwsStateError);

        final reopened = await openStore(files);
        expect(reopened.seq, 3);
        expect(reopened.pendingCount, 3);
        expect(reopened.view.reviews, hasLength(1));
        final resend = await server.sync(
          'u',
          SyncPush(
            clientId: reopened.clientId,
            since: reopened.seq,
            ops: await reopened.pending(500),
          ),
        );
        expect(resend.head, 3);
        await reopened.applyPull(resend);
        expect(reopened.pendingCount, 0);
        expect((await server.collection('u')).collection.reviews, hasLength(1));
        expect(
          reopened.view.toJson(),
          (await server.collection('u')).collection.toJson(),
        );
      },
    );

    test('a failed append never reaches the view', () async {
      final faulty = FaultyFileStore(files);
      final store = await openStore(faulty);
      await store.dispatch(deckOp('d1'));
      faulty.failPath = CollectionStore.outboxPath;
      await expectLater(store.dispatch(deckOp('d2')), throwsStateError);
      expect(store.view.decks.map((d) => d.id), ['d1']);
      await store.dispatch(deckOp('d3'));
      final reopened = await openStore(files);
      expect(reopened.view.decks.map((d) => d.id), ['d1', 'd3']);
    });

    test('a torn last outbox line is dropped on open', () async {
      final store = await openStore(files);
      await store.rebind('srv');
      await store.dispatch(deckOp('d1'));
      files.files[CollectionStore.outboxPath] =
          '${files.files[CollectionStore.outboxPath]}{"id":"x","type":"deckCr';
      final reopened = await openStore(files);
      expect(reopened.pendingCount, 1);
      expect(reopened.view.decks.single.id, 'd1');
    });

    test('never-synced store folds its outbox into base', () async {
      final store = await openStore(files, compactAt: 3);
      await store.dispatchAll([
        deckOp('d1'),
        cardOp('c1', 'd1'),
        reviewOp('c1'),
      ]);
      expect(store.pendingCount, 0);
      expect(files.files[CollectionStore.outboxPath], isEmpty);
      final reopened = await openStore(files, compactAt: 3);
      expect(fingerprint(reopened.view), fingerprint(store.view));
    });

    test('a synced store keeps its outbox until the server acks', () async {
      final store = await openStore(files, compactAt: 2);
      await store.rebind('srv');
      await store.dispatchAll([
        deckOp('d1'),
        cardOp('c1', 'd1'),
        reviewOp('c1'),
      ]);
      expect(store.pendingCount, 3);
    });

    test('rebind exports the view as ops and restarts the cursor', () async {
      final server = MemorySyncServer();
      final store = await openStore(files);
      await store.rebind('old');
      await store.dispatchAll([
        deckOp('d1'),
        cardOp('c1', 'd1'),
        reviewOp('c1'),
      ]);
      await store.applyPull(
        await server.sync(
          'u',
          SyncPush(clientId: 'c', ops: await store.pending(500)),
        ),
      );
      final before = fingerprint(store.view);

      await store.rebind('new');
      expect(store.seq, 0);
      expect(store.pendingCount, greaterThanOrEqualTo(3));
      expect(fingerprint(store.view), before);

      final reopened = await openStore(files);
      expect(reopened.attachedTo, 'new');
      expect(fingerprint(reopened.view), before);
    });

    test('snapshot replaces base and keeps pending ops on top', () async {
      final server = MemorySyncServer();
      await server.sync(
        'u',
        SyncPush(
          clientId: 'other',
          ops: [deckOp('remote'), cardOp('r1', 'remote')],
        ),
      );
      final store = await openStore(files);
      await store.rebind('srv');
      await store.dispatch(deckOp('local'));

      await store.applySnapshot(await server.collection('u'));
      expect(store.seq, 2);
      expect(store.view.decks.map((d) => d.id), ['local', 'remote']);
      expect(store.view.card('r1')!.scheduling, isNotNull);

      final reopened = await openStore(files);
      expect(reopened.seq, 2);
      expect(reopened.view.decks.map((d) => d.id), ['local', 'remote']);
    });

    test('a dispatch issued while a pull is being written survives', () async {
      final faulty = FaultyFileStore(files);
      final store = await openStore(faulty);
      await store.rebind('srv');
      await store.dispatchAll([deckOp('d1'), cardOp('c1', 'd1')]);
      final server = MemorySyncServer();
      final pull = await server.sync(
        'u',
        SyncPush(clientId: 'c', ops: await store.pending(500)),
      );

      faulty.gate = Completer();
      final applying = store.applyPull(pull);
      final editing = store.dispatch(
        CardEdited(
          id: newId(),
          issuedAt: t0.add(const Duration(minutes: 9)),
          cardId: 'c1',
          front: 'edited mid-pull',
          back: 'back',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(store.view.card('c1')!.front, 'front c1');
      faulty.gate!.complete();
      faulty.gate = null;
      await Future.wait([applying, editing]);

      expect(store.view.card('c1')!.front, 'edited mid-pull');
      expect(store.pendingCount, 1);
      final reopened = await openStore(files);
      expect(reopened.view.card('c1')!.front, 'edited mid-pull');
    });
  });

  group('legacy import', () {
    Future<void> writeV1() async {
      await files.write(
        'decks/d1.json',
        jsonEncode({
          'version': 1,
          'id': 'd1',
          'name': 'Spanish',
          'createdAt': '2026-09-01T08:00:00.000Z',
          'updatedAt': '2026-09-02T10:00:00.000Z',
          'cards': [
            {
              'id': 'c1',
              'deckId': 'd1',
              'front': 'hola',
              'back': 'hello',
              'createdAt': '2026-09-01T08:00:00.000Z',
              'updatedAt': '2026-09-02T10:00:00.000Z',
              'fsrs': {
                'cardId': 1,
                'state': 1,
                'step': 0,
                'due': '2026-09-01T08:00:00.000Z',
              },
            },
          ],
          'removedCards': {'c0': '2026-09-01T09:00:00.000Z'},
        }),
      );
      for (final at in [
        '2026-09-01T09:00:00.000Z',
        '2026-09-02T10:00:00.000Z',
      ]) {
        await files.append(
          'reviews.jsonl',
          jsonEncode({
            'cardId': 'c1',
            'deckId': 'd1',
            'rating': 3,
            'reviewedAt': at,
          }),
        );
      }
    }

    test('v1 decks, tombstones and reviews become the base', () async {
      await writeV1();
      final store = await openStore(files);
      final c = store.view;
      expect(c.decks.single.name, 'Spanish');
      expect(c.decks.single.cards.single.front, 'hola');
      expect(c.cardRow('c0')!.removed, isTrue);
      expect(c.reviews.map((r) => r.id), [
        'v1:c1@2026-09-01T09:00:00.000Z',
        'v1:c1@2026-09-02T10:00:00.000Z',
      ]);
      expect(
        c.card('c1')!.scheduling.toMap(),
        CardScheduler().fold(c.cardRow('c1')!.createdAt, c.reviews).toMap(),
      );
      expect(files.files.containsKey(CollectionStore.basePath), isTrue);
      expect(files.files.containsKey('decks/d1.json'), isTrue);
    });

    test('import runs once; later edits to v1 files are ignored', () async {
      await writeV1();
      await openStore(files);
      await files.delete('decks/d1.json');
      final reopened = await openStore(files);
      expect(reopened.view.decks.single.name, 'Spanish');
    });
  });

  test('seed ids are stable across calls and devices', () {
    final a = seedOps(t0, newId).whereType<CardAdded>().map((o) => o.cardId);
    final b = seedOps(
      t0.add(const Duration(days: 3)),
      newId,
    ).whereType<CardAdded>().map((o) => o.cardId);
    expect(a, b);
    expect(a.toSet(), hasLength(20));
  });
}
