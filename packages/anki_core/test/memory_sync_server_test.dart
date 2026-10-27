import 'package:anki_core/anki_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  late MemorySyncServer server;
  setUp(() => server = MemorySyncServer());

  SyncPush push(List<Op> ops, {int since = 0}) =>
      SyncPush(clientId: 'c', since: since, ops: ops);

  test('sequence is dense from 1 and ops echo back', () async {
    final pull = await server.sync(
      'u',
      push([deckCreated('d1'), cardAdded('c1', 'd1')]),
    );
    expect(pull.head, 2);
    expect(pull.ops.map((s) => s.seq), [1, 2]);
    expect(pull.acked, hasLength(2));
  });

  test('duplicate op id is acked but not re-sequenced', () async {
    final op = deckCreated('d1');
    await server.sync('u', push([op]));
    final again = await server.sync('u', push([op], since: 1));
    expect(again.head, 1);
    expect(again.acked, [op.id]);
    expect(again.ops, isEmpty);
  });

  test('more than maxOps is rejected', () async {
    final ops = [for (var i = 0; i <= SyncPush.maxOps; i++) deckCreated('d$i')];
    expect(server.sync('u', push(ops)), throwsFormatException);
  });

  test('pulls are paged', () async {
    for (var i = 0; i < 5; i++) {
      await server.sync(
        'u',
        push([
          for (var j = 0; j < 500; j++) deckCreated('d$i-$j'),
        ], since: i * 500),
      );
    }
    final first = await server.sync('u', push([]));
    expect(first.ops, hasLength(SyncPull.pageSize));
    expect(first.more, isTrue);
    final rest = await server.sync('u', push([], since: first.ops.last.seq));
    expect(rest.ops, hasLength(500));
    expect(rest.more, isFalse);
  });

  test('cursor behind the floor or ahead of head expires', () async {
    await server.sync('u', push([deckCreated('d1'), deckCreated('d2')]));
    await server.compact('u', 1);
    expect(server.sync('u', push([])), throwsA(isA<CursorExpired>()));
    expect(server.sync('u', push([], since: 9)), throwsA(isA<CursorExpired>()));
    final ok = await server.sync('u', push([], since: 1));
    expect(ok.ops.map((s) => s.seq), [2]);
  });

  test('users are isolated', () async {
    await server.sync('a', push([deckCreated('d1')]));
    final b = await server.collection('b');
    expect(b.seq, 0);
    expect(b.collection.isPristine, isTrue);
  });

  test('snapshot equals the fold of the log', () async {
    final ops = [
      deckCreated('d1'),
      cardAdded('c1', 'd1'),
      reviewed('c1', minutes: 5),
      cardRemoved('c1'),
    ];
    await server.sync('u', push(ops));
    final snap = await server.collection('u');
    expect(snap.seq, 4);
    expect(snap.collection.toJson(), reduce(ops).toJson());
  });
}
