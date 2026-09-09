import 'package:flutter_test/flutter_test.dart';
import 'package:poormans_anki/data/deck_repository.dart';
import 'package:poormans_anki/data/seed_data.dart';
import 'package:anki_core/anki_core.dart';
import 'package:poormans_anki/storage/memory_file_store.dart';

void main() {
  final now = DateTime.utc(2026, 9, 8);

  test('loadDecks is empty on a fresh store', () async {
    final repo = DeckRepository(MemoryFileStore());
    expect(await repo.loadDecks(), isEmpty);
  });

  test(
    'saveDeck writes decks/<id>.json and loadDecks reads it back sorted',
    () async {
      final store = MemoryFileStore();
      final repo = DeckRepository(store);
      await repo.saveDeck(
        Deck(id: 'b', name: 'Zeta', createdAt: now, updatedAt: now),
      );
      await repo.saveDeck(
        Deck(id: 'a', name: 'Alpha', createdAt: now, updatedAt: now),
      );

      expect(store.files.keys, containsAll(['decks/a.json', 'decks/b.json']));
      final decks = await repo.loadDecks();
      expect(decks.map((d) => d.name), ['Alpha', 'Zeta']);
    },
  );

  test('deleteDeck removes the file', () async {
    final store = MemoryFileStore();
    final repo = DeckRepository(store);
    await repo.saveDeck(
      Deck(id: 'a', name: 'A', createdAt: now, updatedAt: now),
    );
    await repo.deleteDeck('a');
    expect(await repo.loadDecks(), isEmpty);
  });

  test('appendReview adds one JSONL line per entry', () async {
    final store = MemoryFileStore();
    final repo = DeckRepository(store);
    final entry = ReviewEntry(
      cardId: 'c',
      deckId: 'd',
      rating: Rating.good,
      reviewedAt: now,
    );
    await repo.appendReview(entry);
    await repo.appendReview(entry);

    final lines = (await store.read('reviews.jsonl'))!.trim().split('\n');
    expect(lines, hasLength(2));
    expect(lines.first, contains('"rating":3'));
  });

  test('seedDecks yields two decks with cards due now', () {
    final decks = seedDecks(now);
    expect(decks, hasLength(2));
    for (final deck in decks) {
      expect(deck.cards.length, greaterThanOrEqualTo(8));
      for (final card in deck.cards) {
        expect(card.deckId, deck.id);
        expect(card.due, now);
      }
    }
    final ids = {for (final d in decks) ...d.cards.map((c) => c.id)};
    expect(ids.length, decks.fold(0, (n, d) => n + d.cards.length));
  });
}
