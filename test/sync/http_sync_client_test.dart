import 'dart:convert';
import 'dart:io';

import 'package:anki_core/anki_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:poormans_anki/sync/sync_client.dart';

/// Minimal stand-in for the real server: same JSON contract, same header.
Future<HttpServer> fakeServer(MemorySyncServer server) async {
  final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  httpServer.listen((request) async {
    final email = request.headers.value('Remote-Email');
    if (email == null) {
      request.response
        ..statusCode = 401
        ..write(jsonEncode({'error': 'missing Remote-Email header'}));
      await request.response.close();
      return;
    }
    final body = jsonDecode(await utf8.decoder.bind(request).join());
    final response = await server.sync(
      email,
      SyncRequest.fromJson(body as Map<String, dynamic>),
    );
    request.response
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(response.toJson()));
    await request.response.close();
  });
  return httpServer;
}

void main() {
  late HttpServer httpServer;
  late MemorySyncServer server;

  setUp(() async {
    server = MemorySyncServer();
    httpServer = await fakeServer(server);
  });
  tearDown(() => httpServer.close(force: true));

  String url({String path = ''}) =>
      'http://${httpServer.address.address}:${httpServer.port}$path';

  test(
    'posts to /api/v1/sync with the identity header and parses the reply',
    () async {
      final client = HttpSyncClient(http.Client(), url(), email: 'me@x.io');
      final now = DateTime.utc(2026, 9, 9);
      final response = await client.sync(
        SyncRequest(
          decks: [Deck(id: 'd', name: 'D', createdAt: now, updatedAt: now)],
        ),
      );
      expect(response.decks.single.name, 'D');
      final again = await client.sync(SyncRequest(since: response.cursor));
      expect(again.decks, isEmpty);
    },
  );

  test('trailing slash on the server URL is tolerated', () async {
    final client = HttpSyncClient(
      http.Client(),
      url(path: '/'),
      email: 'me@x.io',
    );
    expect((await client.sync(const SyncRequest())).decks, isEmpty);
  });

  test('non-200 responses surface the server error message', () async {
    final client = HttpSyncClient(http.Client(), url());
    expect(
      () => client.sync(const SyncRequest()),
      throwsA(
        isA<SyncException>().having(
          (e) => e.message,
          'message',
          allOf(contains('401'), contains('Remote-Email')),
        ),
      ),
    );
  });

  test('unreachable servers surface as SyncException', () async {
    final dead = url();
    await httpServer.close(force: true);
    final client = HttpSyncClient(http.Client(), dead, email: 'me@x.io');
    expect(
      () => client.sync(const SyncRequest()),
      throwsA(isA<SyncException>()),
    );
  });
}
