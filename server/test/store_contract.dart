import 'package:anki_core/anki_core.dart';
import 'package:anki_server/sync_store.dart';
import 'package:test/test.dart';

final t0 = DateTime.utc(2026, 9, 1, 8);
DateTime at(int minutes) => t0.add(Duration(minutes: minutes));

var _n = 0;
String nextId() => 'op-${_n++}';

DeckCreated deckCreated(String deckId, {String name = 'Deck'}) =>
    DeckCreated(id: nextId(), issuedAt: t0, deckId: deckId, name: name);

CardAdded cardAdded(String cardId, String deckId, {String front = 'f'}) =>
    CardAdded(
      id: nextId(),
      issuedAt: at(1),
      cardId: cardId,
      deckId: deckId,
      front: front,
      back: 'b',
    );

CardReviewed reviewed(String cardId, int minutes, {String? id}) => CardReviewed(
  id: id ?? nextId(),
  issuedAt: at(minutes),
  cardId: cardId,
  deckId: 'd1',
  rating: Rating.good,
  reviewedAt: at(minutes),
);

SyncPush push(List<Op> ops, {int since = 0, String client = 'c1'}) =>
    SyncPush(clientId: client, since: since, ops: ops);

Map<String, dynamic> fold(List<Op> ops) {
  final c = Collection();
  for (final op in ops) {
    c.apply(op);
  }
  return c.toJson();
}

/// Behaviour every [SyncStore] must share. [create] returns an empty store;
/// [reopen] returns a new instance over the same storage.
void syncStoreContract(
  Future<SyncStore> Function() create, {
  Future<SyncStore> Function()? reopen,
}) {
  late SyncStore store;

  setUp(() async => store = await create());
  tearDown(() => store.close());

  test('sequence is dense from 1 and pushed ops echo back', () async {
    final pull = await store.sync(
      'a@x.io',
      push([deckCreated('d1'), cardAdded('c1', 'd1')]),
    );
    expect(pull.head, 2);
    expect(pull.ops.map((s) => s.seq), [1, 2]);
    expect(pull.ops.map((s) => s.op.type), ['deckCreated', 'cardAdded']);
    expect(pull.acked, hasLength(2));
    expect(pull.more, isFalse);
  });

  test('resent op is acked without a new sequence number', () async {
    final op = deckCreated('d1');
    await store.sync('a@x.io', push([op]));
    final again = await store.sync('a@x.io', push([op], since: 1));
    expect(again.head, 1);
    expect(again.acked, [op.id]);
    expect(again.ops, isEmpty);
  });

  test('pull returns only ops after since, from every client', () async {
    await store.sync('a@x.io', push([deckCreated('d1')], client: 'phone'));
    await store.sync(
      'a@x.io',
      push([cardAdded('c1', 'd1')], since: 1, client: 'desktop'),
    );
    final phone = await store.sync('a@x.io', push([], since: 1));
    expect(phone.ops.single.op, isA<CardAdded>());
  });

  test('pulls are paged at SyncPull.pageSize', () async {
    var since = 0;
    for (var i = 0; i < 5; i++) {
      final pull = await store.sync(
        'a@x.io',
        push([
          for (var j = 0; j < SyncPush.maxOps; j++) deckCreated('d$i-$j'),
        ], since: since),
      );
      since = pull.head;
    }
    final first = await store.sync('a@x.io', push([]));
    expect(first.ops, hasLength(SyncPull.pageSize));
    expect(first.more, isTrue);
    final rest = await store.sync(
      'a@x.io',
      push([], since: first.ops.last.seq),
    );
    expect(rest.ops, hasLength(2500 - SyncPull.pageSize));
    expect(rest.more, isFalse);
  });

  test('since outside [floor, head] expires the cursor', () async {
    await store.sync('a@x.io', push([deckCreated('d1'), deckCreated('d2')]));
    await store.compact('a@x.io', 1);
    await expectLater(
      store.sync('a@x.io', push([])),
      throwsA(isA<CursorExpired>().having((e) => e.floor, 'floor', 1)),
    );
    await expectLater(
      store.sync('a@x.io', push([], since: 3)),
      throwsA(isA<CursorExpired>()),
    );
    final ok = await store.sync('a@x.io', push([], since: 1));
    expect(ok.ops.map((s) => s.seq), [2]);
  });

  test('compaction keeps de-duplication', () async {
    final op = deckCreated('d1');
    await store.sync('a@x.io', push([op]));
    await store.compact('a@x.io', 1);
    final again = await store.sync('a@x.io', push([op], since: 1));
    expect(again.head, 1);
  });

  test('users are isolated', () async {
    await store.sync('a@x.io', push([deckCreated('d1')]));
    final other = await store.collection('b@x.io');
    expect(other.seq, 0);
    expect(other.collection.isPristine, isTrue);
    final pull = await store.sync('b@x.io', push([]));
    expect(pull.ops, isEmpty);
  });

  test('snapshot equals the fold of every accepted op', () async {
    final ops = <Op>[
      deckCreated('d1', name: 'Spanish'),
      deckCreated('d2'),
      cardAdded('c1', 'd1'),
      cardAdded('c2', 'd1'),
      cardAdded('c3', 'd2'),
      CardEdited(
        id: nextId(),
        issuedAt: at(5),
        cardId: 'c1',
        front: 'edited',
        back: 'b',
      ),
      reviewed('c1', 10),
      reviewed('c2', 11),
      CardRemoved(id: nextId(), issuedAt: at(12), cardId: 'c2'),
      CardEdited(
        id: nextId(),
        issuedAt: at(13),
        cardId: 'c2',
        front: 'ghost',
        back: 'b',
      ),
      DeckRenamed(id: nextId(), issuedAt: at(14), deckId: 'd1', name: 'ES'),
      DeckDeleted(id: nextId(), issuedAt: at(15), deckId: 'd2'),
      cardAdded('c4', 'd2'),
      reviewed('c3', 16),
      CardRemoved(id: nextId(), issuedAt: at(17), cardId: 'never-added'),
    ];
    await store.sync('a@x.io', push(ops));
    final snap = await store.collection('a@x.io');
    expect(snap.seq, ops.length);
    expect(snap.collection.toJson(), fold(ops));
  });

  test('re-sent review after compaction is not duplicated', () async {
    final review = reviewed('c1', 3);
    await store.sync(
      'a@x.io',
      push([deckCreated('d1'), cardAdded('c1', 'd1'), review]),
    );
    final snapshot = (await store.collection('a@x.io')).collection.reviews;
    expect(snapshot, hasLength(1));
    await store.sync('a@x.io', push([review], since: 3));
    expect((await store.collection('a@x.io')).collection.reviews, hasLength(1));
  });

  test('concurrent syncs for one user get unique dense sequences', () async {
    final results = await Future.wait([
      for (var i = 0; i < 20; i++)
        store.sync('a@x.io', push([deckCreated('d$i')], client: 'c$i')),
    ]);
    expect(results.map((r) => r.head).toSet(), {
      for (var i = 1; i <= 20; i++) i,
    });
    final all = await store.sync('a@x.io', push([]));
    expect(all.ops.map((s) => s.seq), [for (var i = 1; i <= 20; i++) i]);
    final snapshot = await store.collection('a@x.io');
    expect(snapshot.collection.deckRows, hasLength(20));
  });

  if (reopen != null) {
    test('data survives closing and reopening the store', () async {
      await store.sync(
        'a@x.io',
        push([deckCreated('d1'), cardAdded('c1', 'd1'), reviewed('c1', 9)]),
      );
      final before = await store.collection('a@x.io');
      await store.close();
      store = await reopen();
      final after = await store.collection('a@x.io');
      expect(after.seq, 3);
      expect(after.collection.toJson(), before.collection.toJson());
      final pull = await store.sync('a@x.io', push([], since: 1));
      expect(pull.ops.map((s) => s.seq), [2, 3]);
    });
  }
}
