import 'package:anki_core/anki_core.dart';
import 'package:postgres/postgres.dart';

import 'sync_store.dart';

/// - **Ordering**: `SELECT … FOR UPDATE` on the `users` row serializes one
///   user's syncs; `users.head_seq` is the dense per-user sequence.
/// - **Materialization**: each new op loads only the rows it touches into a
///   [Collection], applies the shared reducer and upserts them back.
/// - **Compaction**: nulls op bodies but keeps `op_id`, so de-duplication
///   survives it.
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
    '''
    ALTER TABLE decks RENAME TO v1_decks;
    ALTER TABLE reviews RENAME TO v1_reviews;
    ALTER INDEX decks_user_synced RENAME TO v1_decks_user_synced;
    ALTER INDEX reviews_user_synced RENAME TO v1_reviews_user_synced;
    ALTER TABLE users ADD COLUMN head_seq bigint NOT NULL DEFAULT 0;
    ALTER TABLE users ADD COLUMN floor_seq bigint NOT NULL DEFAULT 0;
    CREATE TABLE ops (
      user_email text NOT NULL REFERENCES users(email),
      seq bigint NOT NULL,
      op_id text NOT NULL,
      client_id text NOT NULL,
      body jsonb,
      received_at timestamptz NOT NULL DEFAULT now(),
      PRIMARY KEY (user_email, seq),
      UNIQUE (user_email, op_id)
    );
    CREATE TABLE decks (
      user_email text NOT NULL REFERENCES users(email),
      id text NOT NULL,
      name text NOT NULL,
      created_at timestamptz NOT NULL,
      updated_at timestamptz NOT NULL,
      deleted boolean NOT NULL,
      PRIMARY KEY (user_email, id)
    );
    CREATE TABLE cards (
      user_email text NOT NULL REFERENCES users(email),
      id text NOT NULL,
      deck_id text NOT NULL,
      front text NOT NULL,
      back text NOT NULL,
      created_at timestamptz NOT NULL,
      updated_at timestamptz NOT NULL,
      removed boolean NOT NULL,
      PRIMARY KEY (user_email, id)
    );
    CREATE INDEX cards_user_deck ON cards (user_email, deck_id);
    CREATE TABLE reviews (
      user_email text NOT NULL REFERENCES users(email),
      id text NOT NULL,
      card_id text NOT NULL,
      deck_id text NOT NULL,
      rating smallint NOT NULL,
      reviewed_at timestamptz NOT NULL,
      PRIMARY KEY (user_email, id)
    );
    INSERT INTO decks (user_email, id, name, created_at, updated_at, deleted)
      SELECT user_email, id, COALESCE(body->>'name', ''),
             COALESCE((body->>'createdAt')::timestamptz, updated_at),
             COALESCE(deleted_at, updated_at), deleted_at IS NOT NULL
      FROM v1_decks;
    INSERT INTO cards (user_email, id, deck_id, front, back, created_at, updated_at, removed)
      SELECT d.user_email, c->>'id', d.id, c->>'front', c->>'back',
             (c->>'createdAt')::timestamptz, (c->>'updatedAt')::timestamptz,
             d.deleted_at IS NOT NULL
      FROM v1_decks d, jsonb_array_elements(d.body->'cards') c
      WHERE d.body IS NOT NULL
      ON CONFLICT DO NOTHING;
    INSERT INTO cards (user_email, id, deck_id, front, back, created_at, updated_at, removed)
      SELECT d.user_email, r.key, d.id, '', '', r.value::timestamptz, r.value::timestamptz, true
      FROM v1_decks d, jsonb_each_text(d.body->'removedCards') r
      WHERE d.body IS NOT NULL
      ON CONFLICT DO NOTHING;
    INSERT INTO reviews (user_email, id, card_id, deck_id, rating, reviewed_at)
      SELECT user_email, 'v1:' || card_id || '@' || (body->>'reviewedAt'),
             card_id, deck_id, (body->>'rating')::smallint, reviewed_at
      FROM v1_reviews
      ON CONFLICT DO NOTHING;
    UPDATE users SET head_seq = 1, floor_seq = 1
      WHERE email IN (SELECT user_email FROM decks UNION SELECT user_email FROM reviews);
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
  Future<SyncPull> sync(String user, SyncPush push) => _pool.runTx((tx) async {
    await tx.execute(
      Sql.named('INSERT INTO users (email) VALUES (@u) ON CONFLICT DO NOTHING'),
      parameters: {'u': user},
    );
    final locked = await tx.execute(
      Sql.named(
        'SELECT head_seq, floor_seq FROM users WHERE email = @u FOR UPDATE',
      ),
      parameters: {'u': user},
    );
    var head = locked.first[0] as int;
    final floor = locked.first[1] as int;
    if (push.since < floor || push.since > head) throw CursorExpired(floor);
    for (final op in push.ops) {
      final inserted = await tx.execute(
        Sql.named('''
          INSERT INTO ops (user_email, seq, op_id, client_id, body)
          VALUES (@u, @seq, @id, @client, @body)
          ON CONFLICT (user_email, op_id) DO NOTHING'''),
        parameters: {
          'u': user,
          'seq': head + 1,
          'id': op.id,
          'client': push.clientId,
          'body': TypedValue(Type.jsonb, op.toJson()),
        },
      );
      if (inserted.affectedRows == 0) continue;
      head++;
      await _apply(tx, user, op);
    }
    await tx.execute(
      Sql.named('UPDATE users SET head_seq = @h WHERE email = @u'),
      parameters: {'u': user, 'h': head},
    );
    final page = await tx.execute(
      Sql.named('''
        SELECT seq, body FROM ops
        WHERE user_email = @u AND seq > @since
        ORDER BY seq LIMIT ${SyncPull.pageSize}'''),
      parameters: {'u': user, 'since': push.since},
    );
    final ops = [
      for (final row in page)
        SequencedOp(row[0] as int, Op.fromJson(_json(row[1]))),
    ];
    return SyncPull(
      head: head,
      acked: [for (final op in push.ops) op.id],
      ops: ops,
      more: ops.isNotEmpty && ops.last.seq < head,
    );
  });

  Future<void> _apply(TxSession tx, String user, Op op) async {
    final (deckIds, cardIds, cardsOfDeck) = switch (op) {
      DeckCreated(:final deckId) ||
      DeckRenamed(:final deckId) => ([deckId], <String>[], null),
      DeckDeleted(:final deckId) => ([deckId], <String>[], deckId),
      CardAdded(:final deckId, :final cardId) => ([deckId], [cardId], null),
      CardEdited(:final cardId) ||
      CardRemoved(:final cardId) ||
      CardReviewed(:final cardId) => (<String>[], [cardId], null),
    };
    final decks = await tx.execute(
      Sql.named('''
        SELECT id, name, created_at, updated_at, deleted FROM decks
        WHERE user_email = @u AND id = ANY(@ids)'''),
      parameters: {'u': user, 'ids': TypedValue(Type.textArray, deckIds)},
    );
    final cards = await tx.execute(
      Sql.named('''
        SELECT id, deck_id, front, back, created_at, updated_at, removed
        FROM cards
        WHERE user_email = @u AND (id = ANY(@ids) OR deck_id = @deck)'''),
      parameters: {
        'u': user,
        'ids': TypedValue(Type.textArray, cardIds),
        'deck': TypedValue(Type.text, cardsOfDeck),
      },
    );
    final slice = Collection.fromJson({
      'decks': [for (final r in decks) _deckJson(r)],
      'cards': [for (final r in cards) _cardJson(r)],
    });
    if (op is CardReviewed) {
      final dup = await tx.execute(
        Sql.named('SELECT 1 FROM reviews WHERE user_email = @u AND id = @id'),
        parameters: {'u': user, 'id': op.id},
      );
      if (dup.isNotEmpty) return;
    }
    if (!slice.apply(op)) return;
    for (final row in slice.deckRows) {
      await tx.execute(
        Sql.named('''
          INSERT INTO decks (user_email, id, name, created_at, updated_at, deleted)
          VALUES (@u, @id, @name, @created, @updated, @deleted)
          ON CONFLICT (user_email, id) DO UPDATE SET
            name = EXCLUDED.name, updated_at = EXCLUDED.updated_at,
            deleted = EXCLUDED.deleted'''),
        parameters: {
          'u': user,
          'id': row.id,
          'name': row.name,
          'created': _ts(row.createdAt),
          'updated': _ts(row.updatedAt),
          'deleted': row.deleted,
        },
      );
    }
    for (final row in slice.cardRows) {
      await tx.execute(
        Sql.named('''
          INSERT INTO cards (user_email, id, deck_id, front, back, created_at, updated_at, removed)
          VALUES (@u, @id, @deck, @front, @back, @created, @updated, @removed)
          ON CONFLICT (user_email, id) DO UPDATE SET
            front = EXCLUDED.front, back = EXCLUDED.back,
            updated_at = EXCLUDED.updated_at, removed = EXCLUDED.removed'''),
        parameters: {
          'u': user,
          'id': row.id,
          'deck': row.deckId,
          'front': row.front,
          'back': row.back,
          'created': _ts(row.createdAt),
          'updated': _ts(row.updatedAt),
          'removed': row.removed,
        },
      );
    }
    for (final review in slice.reviews) {
      await tx.execute(
        Sql.named('''
          INSERT INTO reviews (user_email, id, card_id, deck_id, rating, reviewed_at)
          VALUES (@u, @id, @card, @deck, @rating, @at)
          ON CONFLICT DO NOTHING'''),
        parameters: {
          'u': user,
          'id': review.id,
          'card': review.cardId,
          'deck': review.deckId,
          'rating': review.rating.value,
          'at': _ts(review.reviewedAt),
        },
      );
    }
  }

  @override
  Future<CollectionSnapshot> collection(String user) => _pool.runTx((tx) async {
    final head = await tx.execute(
      Sql.named('SELECT head_seq FROM users WHERE email = @u FOR SHARE'),
      parameters: {'u': user},
    );
    if (head.isEmpty) {
      return CollectionSnapshot(seq: 0, collection: Collection());
    }
    final params = {'u': user};
    final decks = await tx.execute(
      Sql.named('''
        SELECT id, name, created_at, updated_at, deleted
        FROM decks WHERE user_email = @u'''),
      parameters: params,
    );
    final cards = await tx.execute(
      Sql.named('''
        SELECT id, deck_id, front, back, created_at, updated_at, removed
        FROM cards WHERE user_email = @u'''),
      parameters: params,
    );
    final reviews = await tx.execute(
      Sql.named('''
        SELECT id, card_id, deck_id, rating, reviewed_at
        FROM reviews WHERE user_email = @u'''),
      parameters: params,
    );
    return CollectionSnapshot(
      seq: head.first[0] as int,
      collection: Collection.fromJson({
        'decks': [for (final r in decks) _deckJson(r)],
        'cards': [for (final r in cards) _cardJson(r)],
        'reviews': [
          for (final r in reviews)
            {
              'id': r[0],
              'cardId': r[1],
              'deckId': r[2],
              'rating': r[3],
              'reviewedAt': _iso(r[4]),
            },
        ],
      }),
    );
  });

  @override
  Future<void> compact(String user, int throughSeq) => _pool.runTx((tx) async {
    final rows = await tx.execute(
      Sql.named('''
        UPDATE users
        SET floor_seq = GREATEST(floor_seq, LEAST(@t, head_seq))
        WHERE email = @u
        RETURNING floor_seq'''),
      parameters: {'u': user, 't': throughSeq},
    );
    if (rows.isEmpty) return;
    await tx.execute(
      Sql.named(
        'UPDATE ops SET body = NULL WHERE user_email = @u AND seq <= @f',
      ),
      parameters: {'u': user, 'f': rows.first[0]},
    );
  });

  static Map<String, dynamic> _deckJson(ResultRow r) => {
    'id': r[0],
    'name': r[1],
    'createdAt': _iso(r[2]),
    'updatedAt': _iso(r[3]),
    'deleted': r[4],
  };

  static Map<String, dynamic> _cardJson(ResultRow r) => {
    'id': r[0],
    'deckId': r[1],
    'front': r[2],
    'back': r[3],
    'createdAt': _iso(r[4]),
    'updatedAt': _iso(r[5]),
    'removed': r[6],
  };

  static String _iso(Object? value) =>
      (value as DateTime).toUtc().toIso8601String();

  static TypedValue _ts(DateTime value) =>
      TypedValue(Type.timestampWithTimezone, value);

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
