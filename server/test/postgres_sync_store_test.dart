@Tags(['postgres'])
library;

import 'dart:io';

import 'package:anki_server/postgres_sync_store.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'store_contract.dart';

/// Runs only with `TEST_DATABASE_URL`; each test starts from empty tables.
void main() {
  final url = Platform.environment['TEST_DATABASE_URL'];
  if (url == null) {
    test('skipped: TEST_DATABASE_URL not set', () {}, skip: true);
    return;
  }
  syncStoreContract(() async {
    final store = await PostgresSyncStore.open(url);
    final uri = Uri.parse(url);
    final conn = await Connection.open(
      Endpoint(
        host: uri.host,
        port: uri.port,
        database: uri.pathSegments.first,
        username: uri.userInfo.split(':').first,
        password: uri.userInfo.split(':').last,
      ),
      settings: const ConnectionSettings(sslMode: SslMode.disable),
    );
    await conn.execute('TRUNCATE reviews, decks, users');
    await conn.close();
    return store;
  });
}
