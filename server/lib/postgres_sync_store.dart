import 'package:anki_core/anki_core.dart';
import 'package:postgres/postgres.dart';

import 'sync_store.dart';

/// Per-user `SELECT ... FOR UPDATE` on `users` serializes syncs, and
/// `synced_at`/cursor come from `clock_timestamp()` taken under that lock, so
/// `synced_at > since` never skips a concurrent writer.
class PostgresSyncStore implements SyncStore {
  PostgresSyncStore._(this._pool);

  final Pool _pool;

  static Future<PostgresSyncStore> open(String databaseUrl) async {
    final uri = Uri.parse(databaseUrl);
    final sslMode = switch (uri.queryParameters['sslmode']) {
      'disable' => SslMode.disable,
      'require' || 'verify-ca' || 'verify-full' => SslMode.verifyFull,
      _ => SslMode.disable,
    };
    final userInfo = uri.userInfo.split(':');
    final pool = Pool.withEndpoints([
      Endpoint(
        host: uri.host,
        port: uri.hasPort ? uri.port : 5432,
        database: uri.pathSegments.isEmpty
            ? 'postgres'
            : uri.pathSegments.first,
        username: Uri.decodeComponent(userInfo.first),
        password: userInfo.length > 1 ? Uri.decodeComponent(userInfo[1]) : null,
      ),
    ], settings: PoolSettings(sslMode: sslMode, maxConnectionCount: 8));
    final store = PostgresSyncStore._(pool);
    await store._migrate();
    return store;
  }

  static const _migrations = <String>[
    '''
    CREATE TABLE IF NOT EXISTS users (
      email text PRIMARY KEY,
      created_at timestamptz NOT NULL DEFAULT now()
    );
    CREATE TABLE IF NOT EXISTS decks (
      user_email text NOT NULL REFERENCES users(email),
      id text NOT NULL,
      body jsonb,
      updated_at timestamptz NOT NULL,
      deleted_at timestamptz,
      synced_at timestamptz NOT NULL,
      PRIMARY KEY (user_email, id)
    );
    CREATE INDEX IF NOT EXISTS decks_user_synced ON decks (user_email, synced_at);
    CREATE TABLE IF NOT EXISTS reviews (
      user_email text NOT NULL REFERENCES users(email),
      card_id text NOT NULL,
      reviewed_at timestamptz NOT NULL,
      deck_id text NOT NULL,
      body jsonb NOT NULL,
      synced_at timestamptz NOT NULL,
      PRIMARY KEY (user_email, card_id, reviewed_at)
    );
    CREATE INDEX IF NOT EXISTS reviews_user_synced ON reviews (user_email, synced_at);
    ''',
  ];

  Future<void> _migrate() async {
    await _pool.execute('''
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version integer PRIMARY KEY,
        applied_at timestamptz NOT NULL DEFAULT now()
      )''');
    await _pool.runTx((tx) async {
      await tx.execute('LOCK TABLE schema_migrations IN EXCLUSIVE MODE');
      final applied = {
        for (final row in await tx.execute(
          'SELECT version FROM schema_migrations',
        ))
          row[0] as int,
      };
      for (final (i, sql) in _migrations.indexed) {
        final version = i + 1;
        if (applied.contains(version)) continue;
        for (final statement in sql.split(';')) {
          if (statement.trim().isNotEmpty) await tx.execute(statement);
        }
        await tx.execute(
          Sql.named('INSERT INTO schema_migrations (version) VALUES (@v)'),
          parameters: {'v': version},
        );
      }
    });
  }

  @override
  Future<SyncResponse> sync(String user, SyncRequest request) => _pool.runTx((
    tx,
  ) async {
    await tx.execute(
      Sql.named('INSERT INTO users (email) VALUES (@u) ON CONFLICT DO NOTHING'),
      parameters: {'u': user},
    );
    await tx.execute(
      Sql.named('SELECT email FROM users WHERE email = @u FOR UPDATE'),
      parameters: {'u': user},
    );
    for (final incoming in request.decks) {
      await _upsertDeck(tx, user, incoming);
    }
    for (final tombstone in request.deletedDecks) {
      await _applyTombstone(tx, user, tombstone);
    }
    for (final entry in request.reviews) {
      await tx.execute(
        Sql.named('''
              INSERT INTO reviews (user_email, card_id, reviewed_at, deck_id, body, synced_at)
              VALUES (@u, @card, @at, @deck, @body, clock_timestamp())
              ON CONFLICT DO NOTHING'''),
        parameters: {
          'u': user,
          'card': entry.cardId,
          'at': TypedValue(Type.timestampWithTimezone, entry.reviewedAt),
          'deck': entry.deckId,
          'body': TypedValue(Type.jsonb, entry.toJson()),
        },
      );
    }
    final since = TypedValue(
      Type.timestampWithTimezone,
      request.since ?? DateTime.utc(1970),
    );
    final decks = await tx.execute(
      Sql.named('''
            SELECT body FROM decks
            WHERE user_email = @u AND deleted_at IS NULL AND body IS NOT NULL
              AND synced_at > @since'''),
      parameters: {'u': user, 'since': since},
    );
    final tombstones = await tx.execute(
      Sql.named(
        '''
            SELECT id, deleted_at FROM decks
            WHERE user_email = @u AND deleted_at IS NOT NULL AND synced_at > @since''',
      ),
      parameters: {'u': user, 'since': since},
    );
    final reviews = await tx.execute(
      Sql.named('''
            SELECT body FROM reviews WHERE user_email = @u AND synced_at > @since
            ORDER BY reviewed_at'''),
      parameters: {'u': user, 'since': since},
    );
    final cursor = await tx.execute('SELECT clock_timestamp()');
    return SyncResponse(
      cursor: (cursor.first[0] as DateTime).toUtc(),
      decks: [for (final row in decks) Deck.fromJson(_json(row[0]))],
      deletedDecks: [
        for (final row in tombstones)
          DeckTombstone(
            id: row[0] as String,
            deletedAt: (row[1] as DateTime).toUtc(),
          ),
      ],
      reviews: [for (final row in reviews) ReviewEntry.fromJson(_json(row[0]))],
    );
  });

  Future<void> _upsertDeck(TxSession tx, String user, Deck incoming) async {
    final rows = await tx.execute(
      Sql.named(
        'SELECT body, deleted_at FROM decks WHERE user_email = @u AND id = @id',
      ),
      parameters: {'u': user, 'id': incoming.id},
    );
    Deck next = incoming;
    if (rows.isNotEmpty) {
      final existing = switch (rows.first[0]) {
        null => null,
        final body => Deck.fromJson(_json(body)),
      };
      final deletedAt = (rows.first[1] as DateTime?)?.toUtc();
      if (deletedAt != null && !incoming.updatedAt.isAfter(deletedAt)) return;
      if (existing != null) {
        next = mergeDecks(existing, incoming);
        if (deletedAt == null && sameDeck(existing, next)) return;
      }
    }
    await tx.execute(
      Sql.named('''
        INSERT INTO decks (user_email, id, body, updated_at, deleted_at, synced_at)
        VALUES (@u, @id, @body, @updated, NULL, clock_timestamp())
        ON CONFLICT (user_email, id) DO UPDATE SET
          body = EXCLUDED.body, updated_at = EXCLUDED.updated_at,
          deleted_at = NULL, synced_at = EXCLUDED.synced_at'''),
      parameters: {
        'u': user,
        'id': next.id,
        'body': TypedValue(Type.jsonb, next.toJson()),
        'updated': TypedValue(Type.timestampWithTimezone, next.updatedAt),
      },
    );
  }

  Future<void> _applyTombstone(
    TxSession tx,
    String user,
    DeckTombstone tombstone,
  ) async {
    final rows = await tx.execute(
      Sql.named(
        'SELECT updated_at, deleted_at FROM decks WHERE user_email = @u AND id = @id',
      ),
      parameters: {'u': user, 'id': tombstone.id},
    );
    if (rows.isNotEmpty) {
      final updatedAt = (rows.first[0] as DateTime).toUtc();
      final alreadyDeleted = rows.first[1] != null;
      if (alreadyDeleted || !tombstone.deletedAt.isAfter(updatedAt)) return;
    }
    await tx.execute(
      Sql.named('''
        INSERT INTO decks (user_email, id, body, updated_at, deleted_at, synced_at)
        VALUES (@u, @id, NULL, @deleted, @deleted, clock_timestamp())
        ON CONFLICT (user_email, id) DO UPDATE SET
          deleted_at = EXCLUDED.deleted_at, synced_at = EXCLUDED.synced_at'''),
      parameters: {
        'u': user,
        'id': tombstone.id,
        'deleted': TypedValue(Type.timestampWithTimezone, tombstone.deletedAt),
      },
    );
  }

  static Map<String, dynamic> _json(Object? value) =>
      (value as Map).cast<String, dynamic>();

  @override
  Future<bool> healthy() async {
    try {
      await _pool.execute('SELECT 1');
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> close() => _pool.close();
}
