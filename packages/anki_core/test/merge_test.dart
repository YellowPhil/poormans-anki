import 'package:anki_core/anki_core.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:test/test.dart';

final t0 = DateTime.utc(2026, 9, 1);
DateTime at(int hours) => t0.add(Duration(hours: hours));

Flashcard card(String id, String front, DateTime updatedAt) => Flashcard(
  id: id,
  deckId: 'd',
  front: front,
  back: 'b',
  createdAt: t0,
  updatedAt: updatedAt,
  scheduling: fsrs.Card(cardId: 1, due: t0),
);

Deck deck(
  List<Flashcard> cards, {
  String name = 'Deck',
  DateTime? updatedAt,
  Map<String, DateTime> removed = const {},
}) => Deck(
  id: 'd',
  name: name,
  createdAt: t0,
  updatedAt: updatedAt ?? t0,
  cards: cards,
  removedCards: removed,
);

void main() {
  test('newer card version wins per card', () {
    final a = deck([card('c1', 'old', at(1)), card('c2', 'a2', at(1))]);
    final b = deck([card('c1', 'new', at(2)), card('c2', 'b2', at(0))]);
    final m = mergeDecks(a, b);
    expect(m.cards.map((c) => c.front), ['new', 'a2']);
  });

  test('cards present on one side only are kept', () {
    final a = deck([card('c1', 'x', at(1))]);
    final b = deck([card('c2', 'y', at(1))]);
    expect(mergeDecks(a, b).cards.map((c) => c.id), ['c1', 'c2']);
  });

  test('tombstone removes a card unless it was edited afterwards', () {
    final a = deck([card('c1', 'x', at(1)), card('c2', 'y', at(1))]);
    final b = deck([], removed: {'c1': at(2), 'c2': at(0)});
    final m = mergeDecks(a, b);
    expect(m.cards.map((c) => c.id), ['c2']);
    expect(m.removedCards.keys, ['c1']);
  });

  test('name follows the newer deck; updatedAt is the max', () {
    final a = deck([], name: 'A', updatedAt: at(1));
    final b = deck([], name: 'B', updatedAt: at(3));
    final m = mergeDecks(a, b);
    expect(m.name, 'B');
    expect(m.updatedAt, at(3));
    expect(mergeDecks(b, a).name, 'B');
  });

  test('merge is commutative and idempotent', () {
    final a = deck(
      [card('c1', 'a1', at(2)), card('c3', 'a3', at(1))],
      removed: {'c2': at(2)},
    );
    final b = deck(
      [card('c1', 'b1', at(1)), card('c2', 'b2', at(1))],
      name: 'Renamed',
      updatedAt: at(5),
    );
    final ab = mergeDecks(a, b);
    final ba = mergeDecks(b, a);
    expect(sameDeck(ab, ba), isTrue);
    expect(sameDeck(mergeDecks(ab, a), ab), isTrue);
    expect(sameDeck(mergeDecks(ab, b), ab), isTrue);
  });

  test('payloads round-trip through JSON', () {
    final request = SyncRequest(
      since: at(1),
      decks: [
        deck([card('c1', 'x', at(1))], removed: {'c9': at(0)}),
      ],
      deletedDecks: [DeckTombstone(id: 'gone', deletedAt: at(2))],
      reviews: [
        ReviewEntry(
          cardId: 'c1',
          deckId: 'd',
          rating: Rating.good,
          reviewedAt: at(1),
        ),
      ],
    );
    final back = SyncRequest.fromJson(request.toJson());
    expect(back.since, at(1));
    expect(back.decks.single.removedCards, {'c9': at(0)});
    expect(back.deletedDecks.single.id, 'gone');
    expect(back.reviews.single.key, request.reviews.single.key);
  });
}
