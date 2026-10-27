import 'dart:io';

import 'package:anki_core/anki_core.dart';
import 'package:anki_server/api.dart';
import 'package:anki_server/config.dart';
import 'package:anki_server/memory_sync_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:poormans_anki/sync/sync_client.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

void main() {
  late HttpServer httpServer;
  late MemorySyncStore store;

  setUp(() async {
    store = MemorySyncStore();
    httpServer = await shelf_io.serve(
      buildHandler(store, Config.fromEnv(const {})),
      InternetAddress.loopbackIPv4,
      0,
    );
  });
  tearDown(() => httpServer.close(force: true));

  String url([String path = '']) =>
      'http://${httpServer.address.address}:${httpServer.port}$path';

  HttpSyncClient client({String path = '', String? email = 'me@x.io'}) =>
      HttpSyncClient(http.Client(), url(path), email: email);

  final op = DeckCreated(
    id: 'op-1',
    issuedAt: DateTime.utc(2026, 9, 9),
    deckId: 'd',
    name: 'D',
  );

  test('pushes ops with the identity header and parses the pull', () async {
    final pull = await client().sync(SyncPush(clientId: 'c', ops: [op]));
    expect(pull.head, 1);
    expect(pull.acked, ['op-1']);
    expect(pull.ops.single.op.toJson(), op.toJson());
    final again = await client().sync(
      SyncPush(clientId: 'c', since: pull.head),
    );
    expect(again.ops, isEmpty);
    expect(
      (await store.collection('me@x.io')).collection.decks.single.name,
      'D',
    );
  });

  test('fetches the collection snapshot', () async {
    await client().sync(SyncPush(clientId: 'c', ops: [op]));
    final snapshot = await client().collection();
    expect(snapshot.seq, 1);
    expect(snapshot.collection.decks.single.id, 'd');
  });

  test('trailing slash on the server URL is tolerated', () async {
    final pull = await client(path: '/').sync(const SyncPush(clientId: 'c'));
    expect(pull.head, 0);
  });

  test('a compacted cursor surfaces as CursorExpired with the floor', () async {
    await client().sync(SyncPush(clientId: 'c', ops: [op]));
    await store.compact('me@x.io', 1);
    expect(
      () => client().sync(const SyncPush(clientId: 'c')),
      throwsA(isA<CursorExpired>().having((e) => e.floor, 'floor', 1)),
    );
  });

  test('non-200 responses surface the server error message', () async {
    expect(
      () => client(email: null).sync(const SyncPush(clientId: 'c')),
      throwsA(
        isA<SyncException>().having(
          (e) => e.message,
          'message',
          allOf(contains('401'), contains('remote-email header')),
        ),
      ),
    );
  });

  test('the retired v1 endpoint is not mistaken for a cursor expiry', () async {
    final response = await http.post(
      Uri.parse(url('/api/v1/sync')),
      headers: {'Remote-Email': 'me@x.io'},
    );
    expect(response.statusCode, 410);
    expect(response.body, contains('retired'));
    expect(response.body, isNot(contains('floor')));
  });

  test('unreachable servers surface as SyncException', () async {
    final dead = client();
    await httpServer.close(force: true);
    expect(
      () => dead.sync(const SyncPush(clientId: 'c')),
      throwsA(isA<SyncException>()),
    );
  });
}
