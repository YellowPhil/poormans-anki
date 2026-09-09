import 'dart:convert';

import 'package:anki_core/anki_core.dart';
import 'package:anki_server/api.dart';
import 'package:anki_server/config.dart';
import 'package:anki_server/memory_sync_store.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'store_contract.dart';

void main() {
  final config = Config.fromEnv(const {'MAX_BODY_BYTES': '2048'});
  late Handler handler;

  setUp(() => handler = buildHandler(MemorySyncStore(), config));

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
    expect(
      (await handler(req('GET', '/api/v1/me', user: 'not-an-email')))
          .statusCode,
      401,
    );
    final ok = await handler(req('GET', '/api/v1/me', user: 'Me@X.io'));
    expect(await json(ok), {'email': 'me@x.io'});
  });

  test('sync round trip through the HTTP layer', () async {
    final push = await handler(
      req(
        'POST',
        '/api/v1/sync',
        user: 'a@x.io',
        body: SyncRequest(
          decks: [
            deck('d1', [card('c1', 'd1', 'front', at(1))]),
          ],
          reviews: [review('c1', at(1))],
        ).toJson(),
      ),
    );
    expect(push.statusCode, 200);
    final pushed = SyncResponse.fromJson(await json(push));
    expect(pushed.decks.single.id, 'd1');
    expect(pushed.reviews, hasLength(1));

    final pull = await handler(
      req(
        'GET',
        '/api/v1/sync?since=${Uri.encodeComponent(pushed.cursor.toIso8601String())}',
        user: 'a@x.io',
      ),
    );
    final pulled = SyncResponse.fromJson(await json(pull));
    expect(pulled.decks, isEmpty);
    expect(pulled.reviews, isEmpty);
  });

  test('malformed bodies are rejected with 400', () async {
    final notJson = Request(
      'POST',
      Uri.parse('http://localhost/api/v1/sync'),
      headers: {'Remote-Email': 'a@x.io'},
      body: '{not json',
    );
    expect((await handler(notJson)).statusCode, 400);
    final wrongShape = await handler(
      req(
        'POST',
        '/api/v1/sync',
        user: 'a@x.io',
        body: {
          'decks': [1],
        },
      ),
    );
    expect(wrongShape.statusCode, 400);
  });

  test('oversized bodies are rejected with 413', () async {
    final big = await handler(
      req('POST', '/api/v1/sync', user: 'a@x.io', body: {'pad': 'x' * 4096}),
    );
    expect(big.statusCode, 413);
  });
}
