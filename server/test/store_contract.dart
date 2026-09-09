import 'package:anki_core/anki_core.dart';
import 'package:anki_server/sync_store.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:test/test.dart';

final t0 = DateTime.utc(2026, 9, 1);
DateTime at(int hours) => t0.add(Duration(hours: hours));

Flashcard card(String id, String deckId, String front, DateTime updatedAt) =>
    Flashcard(
      id: id,
      deckId: deckId,
      front: front,
      back: 'back',
      createdAt: t0,
      updatedAt: updatedAt,
      scheduling: fsrs.Card(cardId: 1, due: t0),
    );

Deck deck(String id, List<Flashcard> cards, {DateTime? updatedAt}) => Deck(
  id: id,
  name: 'Deck $id',
  createdAt: t0,
  updatedAt: updatedAt ?? t0,
  cards: cards,
);

ReviewEntry review(String cardId, DateTime when) => ReviewEntry(
  cardId: cardId,
  deckId: 'd1',
  rating: Rating.good,
  reviewedAt: when,
);

/// Behaviour every [SyncStore] must share; [create] returns an empty store.
void syncStoreContract(Future<SyncStore> Function() create) {
  late SyncStore store;

  setUp(() async => store = await create());
  tearDown(() => store.close());

  test('first sync returns everything pushed and a cursor', () async {
    final r = await store.sync(
      'a@x.io',
      SyncRequest(
        decks: [
          deck('d1', [card('c1', 'd1', 'x', at(1))]),
        ],
      ),
    );
    expect(r.decks.map((d) => d.id), ['d1']);
    expect(r.reviews, isEmpty);
    expect(r.cursor, isNotNull);
  });

  test('users are isolated', () async {
    await store.sync('a@x.io', SyncRequest(decks: [deck('d1', [])]));
    final other = await store.sync('b@x.io', const SyncRequest());
    expect(other.decks, isEmpty);
  });

  test('cursor filters unchanged rows and delivers later changes', () async {
    final first = await store.sync(
      'a@x.io',
      SyncRequest(
        decks: [
          deck('d1', [card('c1', 'd1', 'x', at(1))]),
        ],
      ),
    );
    final quiet = await store.sync('a@x.io', SyncRequest(since: first.cursor));
    expect(quiet.decks, isEmpty);
    await store.sync(
      'a@x.io',
      SyncRequest(
        decks: [
          deck('d1', [card('c1', 'd1', 'y', at(2))]),
        ],
      ),
    );
    final later = await store.sync('a@x.io', SyncRequest(since: quiet.cursor));
    expect(later.decks.single.cards.single.front, 'y');
  });

  test('two devices merge card-wise', () async {
    final base = deck('d1', [card('c1', 'd1', 'x', at(1))]);
    await store.sync('a@x.io', SyncRequest(decks: [base]));
    final phone = base.copyWith(
      updatedAt: at(2),
      cards: [card('c1', 'd1', 'x', at(1)), card('c2', 'd1', 'phone', at(2))],
    );
    final laptop = base.copyWith(
      updatedAt: at(3),
      cards: [card('c1', 'd1', 'laptop-edit', at(3))],
    );
    await store.sync('a@x.io', SyncRequest(decks: [phone]));
    final r = await store.sync('a@x.io', SyncRequest(decks: [laptop]));
    final merged = r.decks.single;
    expect(merged.cards.map((c) => c.front), ['laptop-edit', 'phone']);
    expect(merged.updatedAt, at(3));
  });

  test('older card version does not overwrite newer server state', () async {
    await store.sync(
      'a@x.io',
      SyncRequest(
        decks: [
          deck('d1', [card('c1', 'd1', 'new', at(5))]),
        ],
      ),
    );
    final r = await store.sync(
      'a@x.io',
      SyncRequest(
        decks: [
          deck('d1', [card('c1', 'd1', 'old', at(1))]),
        ],
      ),
    );
    expect(r.decks.single.cards.single.front, 'new');
  });

  test(
    'deck tombstone hides the deck and a newer edit resurrects it',
    () async {
      await store.sync(
        'a@x.io',
        SyncRequest(decks: [deck('d1', [], updatedAt: at(1))]),
      );
      final deleted = await store.sync(
        'a@x.io',
        SyncRequest(
          deletedDecks: [DeckTombstone(id: 'd1', deletedAt: at(2))],
        ),
      );
      expect(deleted.decks, isEmpty);
      expect(deleted.deletedDecks.single.id, 'd1');
      final stale = await store.sync(
        'a@x.io',
        SyncRequest(decks: [deck('d1', [], updatedAt: at(1))]),
      );
      expect(stale.decks, isEmpty);
      final revived = await store.sync(
        'a@x.io',
        SyncRequest(decks: [deck('d1', [], updatedAt: at(3))]),
      );
      expect(revived.decks.single.id, 'd1');
      expect(revived.deletedDecks, isEmpty);
    },
  );

  test('reviews are de-duplicated and streamed by cursor', () async {
    final first = await store.sync(
      'a@x.io',
      SyncRequest(reviews: [review('c1', at(1)), review('c1', at(1))]),
    );
    expect(first.reviews, hasLength(1));
    final second = await store.sync(
      'a@x.io',
      SyncRequest(
        since: first.cursor,
        reviews: [review('c1', at(1)), review('c2', at(2))],
      ),
    );
    expect(second.reviews.map((r) => r.cardId), ['c2']);
  });
}
