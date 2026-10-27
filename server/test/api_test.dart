import 'dart:convert';

import 'package:anki_core/anki_core.dart';
import 'package:anki_server/api.dart';
import 'package:anki_server/config.dart';
import 'package:anki_server/memory_sync_store.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'store_contract.dart';

void main() {
  final config = Config.fromEnv(const {'MAX_BODY_BYTES': '4096'});
  late MemorySyncStore store;
  late Handler handler;

  setUp(() {
    store = MemorySyncStore();
    handler = buildHandler(store, config);
  });

  Request req(String method, String path, {String? user, Object? body}) =>
      Request(
        method,
        Uri.parse('http://localhost$path'),
        headers: {'Remote-Email': ?user, 'content-type': 'application/json'},
        body: body == null ? null : jsonEncode(body),
      );

  Future<Map<String, dynamic>> json(Response r) async =>
      jsonDecode(await r.readAsString()) as Map<String, dynamic>;

  test('healthz is public', () async {
    final r = await handler(req('GET', '/healthz'));
    expect(r.statusCode, 200);
    expect(await json(r), {'status': 'ok', 'database': true});
  });

  test('api requires a valid identity header', () async {
    expect((await handler(req('GET', '/api/v1/me'))).statusCode, 401);
    expect((await handler(req('GET', '/api/v2/collection'))).statusCode, 401);
    expect(
      (await handler(req('GET', '/api/v1/me', user: 'not-an-email')))
          .statusCode,
      401,
    );
    final ok = await handler(req('GET', '/api/v1/me', user: 'Me@X.io'));
    expect(await json(ok), {'email': 'me@x.io'});
  });

  test('push, pull and snapshot through the HTTP layer', () async {
    final ops = [deckCreated('d1'), cardAdded('c1', 'd1'), reviewed('c1', 5)];
    final r = await handler(
      req('POST', '/api/v2/sync', user: 'a@x.io', body: push(ops).toJson()),
    );
    expect(r.statusCode, 200);
    final pull = SyncPull.fromJson(await json(r));
    expect(pull.head, 3);
    expect(pull.acked, [for (final o in ops) o.id]);

    final snap = await handler(
      req('GET', '/api/v2/collection', user: 'A@x.io'),
    );
    final snapshot = CollectionSnapshot.fromJson(await json(snap));
    expect(snapshot.seq, 3);
    expect(snapshot.collection.toJson(), fold(ops));
  });

  test('expired cursor maps to 410 with the floor', () async {
    await store.sync('a@x.io', push([deckCreated('d1'), deckCreated('d2')]));
    await store.compact('a@x.io', 2);
    final r = await handler(
      req('POST', '/api/v2/sync', user: 'a@x.io', body: push([]).toJson()),
    );
    expect(r.statusCode, 410);
    expect((await json(r))['floor'], 2);
  });

  test('v1 sync is retired with 410', () async {
    for (final method in ['GET', 'POST']) {
      final r = await handler(req(method, '/api/v1/sync', user: 'a@x.io'));
      expect(r.statusCode, 410);
    }
  });

  test('malformed bodies are rejected with 400', () async {
    final notJson = Request(
      'POST',
      Uri.parse('http://localhost/api/v2/sync'),
      headers: {'Remote-Email': 'a@x.io'},
      body: '{not json',
    );
    expect((await handler(notJson)).statusCode, 400);
    Future<int> post(Object body) async =>
        (await handler(req('POST', '/api/v2/sync', user: 'a@x.io', body: body)))
            .statusCode;
    expect(
      await post({
        'clientId': 'c',
        'ops': [1],
      }),
      400,
    );
    expect(
      await post({
        'clientId': 'c',
        'ops': [
          {'id': 'x', 'type': 'bogus', 'issuedAt': '2026-01-01T00:00:00Z'},
        ],
      }),
      400,
    );
    expect(
      await post({
        'clientId': 'c',
        'ops': [
          {...reviewed('c1', 1).toJson(), 'rating': 7},
        ],
      }),
      400,
    );
  });

  test('more than maxOps per push is rejected with 400', () async {
    final big = buildHandler(
      MemorySyncStore(),
      Config.fromEnv(const {'MAX_BODY_BYTES': '10000000'}),
    );
    final ops = [for (var i = 0; i <= SyncPush.maxOps; i++) deckCreated('$i')];
    final r = await big(
      req('POST', '/api/v2/sync', user: 'a@x.io', body: push(ops).toJson()),
    );
    expect(r.statusCode, 400);
  });

  test('oversized bodies are rejected with 413', () async {
    final big = await handler(
      req('POST', '/api/v2/sync', user: 'a@x.io', body: {'pad': 'x' * 8192}),
    );
    expect(big.statusCode, 413);
  });
}
