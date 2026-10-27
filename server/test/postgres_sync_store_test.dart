@Tags(['postgres'])
library;

import 'dart:io';

import 'package:anki_core/anki_core.dart';
import 'package:anki_server/postgres_sync_store.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'store_contract.dart';

/// Runs only with `TEST_DATABASE_URL`; each test starts from an empty schema.
void main() {
  final url = Platform.environment['TEST_DATABASE_URL'];
  if (url == null) {
    test('skipped: TEST_DATABASE_URL not set', () {}, skip: true);
    return;
  }

  Future<Connection> connect() {
    final uri = Uri.parse(url);
    return Connection.open(
      Endpoint(
        host: uri.host,
        port: uri.port,
        database: uri.pathSegments.first,
        username: uri.userInfo.split(':').first,
        password: uri.userInfo.split(':').last,
      ),
      settings: const ConnectionSettings(sslMode: SslMode.disable),
    );
  }

  Future<void> resetSchema() async {
    final conn = await connect();
    await conn.execute('DROP SCHEMA public CASCADE');
    await conn.execute('CREATE SCHEMA public');
    await conn.close();
  }

  group('contract', () {
    syncStoreContract(() async {
      await resetSchema();
      return PostgresSyncStore.open(url);
    }, reopen: () => PostgresSyncStore.open(url));
  });

  test('v1 data is migrated into the v2 tables', () async {
    await resetSchema();
    final conn = await connect();
    await conn.execute('''
      CREATE TABLE schema_migrations (
        version integer PRIMARY KEY,
        applied_at timestamptz NOT NULL DEFAULT now())''');
    await conn.execute('''
      CREATE TABLE users (email text PRIMARY KEY,
        created_at timestamptz NOT NULL DEFAULT now())''');
    await conn.execute('''
      CREATE TABLE decks (user_email text NOT NULL REFERENCES users(email),
        id text NOT NULL, body jsonb, updated_at timestamptz NOT NULL,
        deleted_at timestamptz, synced_at timestamptz NOT NULL,
        PRIMARY KEY (user_email, id))''');
    await conn.execute(
      'CREATE INDEX decks_user_synced ON decks (user_email, synced_at)',
    );
    await conn.execute('''
      CREATE TABLE reviews (user_email text NOT NULL REFERENCES users(email),
        card_id text NOT NULL, reviewed_at timestamptz NOT NULL,
        deck_id text NOT NULL, body jsonb NOT NULL,
        synced_at timestamptz NOT NULL,
        PRIMARY KEY (user_email, card_id, reviewed_at))''');
    await conn.execute(
      'CREATE INDEX reviews_user_synced ON reviews (user_email, synced_at)',
    );
    await conn.execute('INSERT INTO schema_migrations (version) VALUES (1)');
    await conn.execute("INSERT INTO users (email) VALUES ('a@x.io')");
    final reviewedAt = DateTime.utc(2026, 9, 2, 10, 0, 0, 123);
    final review = ReviewEntry.fromJson({
      'cardId': 'c1',
      'deckId': 'd1',
      'rating': 3,
      'reviewedAt': reviewedAt.toIso8601String(),
    });
    final body = {
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
          'fsrs': {},
        },
      ],
      'removedCards': {'c0': '2026-09-01T09:00:00.000Z'},
    };
    await conn.execute(
      Sql.named('''
        INSERT INTO decks (user_email, id, body, updated_at, synced_at)
        VALUES ('a@x.io', 'd1', @body, now(), now())'''),
      parameters: {'body': TypedValue(Type.jsonb, body)},
    );
    await conn.execute(
      Sql.named('''
        INSERT INTO decks (user_email, id, body, updated_at, deleted_at, synced_at)
        VALUES ('a@x.io', 'gone', NULL, now(), now(), now())'''),
    );
    await conn.execute(
      Sql.named('''
        INSERT INTO reviews (user_email, card_id, reviewed_at, deck_id, body, synced_at)
        VALUES ('a@x.io', 'c1', @at, 'd1', @body, now())'''),
      parameters: {
        'at': TypedValue(Type.timestampWithTimezone, reviewedAt),
        'body': TypedValue(Type.jsonb, {
          'cardId': 'c1',
          'deckId': 'd1',
          'rating': 3,
          'reviewedAt': reviewedAt.toIso8601String(),
        }),
      },
    );
    await conn.close();

    final store = await PostgresSyncStore.open(url);
    addTearDown(store.close);
    final snap = await store.collection('a@x.io');
    expect(snap.seq, 1);
    final c = snap.collection;
    expect(c.deckRow('d1')!.name, 'Spanish');
    expect(c.deckRow('gone')!.deleted, isTrue);
    expect(c.cardRow('c1')!.front, 'hola');
    expect(c.cardRow('c0')!.removed, isTrue);
    expect(c.reviews.single.id, review.id);
    expect(review.id, 'v1:c1@2026-09-02T10:00:00.123Z');
    await expectLater(
      store.sync('a@x.io', const SyncPush(clientId: 'c')),
      throwsA(isA<CursorExpired>()),
    );
    final resent = await store.sync(
      'a@x.io',
      SyncPush(
        clientId: 'c',
        since: 1,
        ops: [
          CardReviewed(
            id: review.id,
            issuedAt: reviewedAt,
            cardId: 'c1',
            deckId: 'd1',
            rating: Rating.good,
            reviewedAt: reviewedAt,
          ),
        ],
      ),
    );
    expect(resent.acked, [review.id]);
    expect((await store.collection('a@x.io')).collection.reviews, hasLength(1));
  });
}
