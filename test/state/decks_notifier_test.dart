import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:poormans_anki/data/deck_repository.dart';
import 'package:anki_core/anki_core.dart';
import 'package:poormans_anki/scheduler/review_scheduler.dart';
import 'package:poormans_anki/state/providers.dart';
import 'package:poormans_anki/storage/memory_file_store.dart';

void main() {
  final now = DateTime.utc(2026, 9, 8, 12);

  ProviderContainer makeContainer(MemoryFileStore store) {
    final container = ProviderContainer(
      overrides: [
        fileStoreProvider.overrideWithValue(store),
        clockProvider.overrideWithValue(() => now),
        schedulerProvider.overrideWithValue(
          ReviewScheduler(fsrs.Scheduler(enableFuzzing: false)),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> seedOneCard(MemoryFileStore store, {DateTime? due}) async {
    final repo = DeckRepository(store);
    await repo.saveDeck(
      Deck(
        id: 'd1',
        name: 'D',
        createdAt: now,
        updatedAt: now,
        cards: [
          Flashcard(
            id: 'c1',
            deckId: 'd1',
            front: 'f',
            back: 'b',
            createdAt: now,
            updatedAt: now,
            scheduling: fsrs.Card(cardId: 1, due: due ?? now),
          ),
        ],
      ),
    );
  }

  test('build seeds placeholder decks into an empty store', () async {
    final store = MemoryFileStore();
    final container = makeContainer(store);

    final decks = await container.read(decksProvider.future);

    expect(decks, hasLength(2));
    expect(store.files.keys.where((k) => k.startsWith('decks/')), hasLength(2));
  });

  test('build does not seed when decks already exist', () async {
    final store = MemoryFileStore();
    await seedOneCard(store);
    final container = makeContainer(store);

    final decks = await container.read(decksProvider.future);

    expect(decks.map((d) => d.id), ['d1']);
  });

  test('createDeck persists a new empty deck', () async {
    final store = MemoryFileStore();
    await seedOneCard(store);
    final container = makeContainer(store);
    await container.read(decksProvider.future);

    final deck = await container.read(decksProvider.notifier).createDeck('New');

    expect(deck.cards, isEmpty);
    expect(await DeckRepository(store).loadDecks(), hasLength(2));
  });

  test('addCard appends a due card to the deck and persists it', () async {
    final store = MemoryFileStore();
    await seedOneCard(store);
    final container = makeContainer(store);
    await container.read(decksProvider.future);

    await container.read(decksProvider.notifier).addCard('d1', 'q', 'a');

    final saved = (await DeckRepository(store).loadDecks()).single;
    expect(saved.cards.map((c) => c.front), ['f', 'q']);
    expect(saved.cards.last.due, now);
    expect(saved.updatedAt, now);
    expect(container.read(dueCardsProvider).map((c) => c.front), ['f', 'q']);
  });

  test(
    'rateCard Easy graduates the card out of the due list and persists review',
    () async {
      final store = MemoryFileStore();
      await seedOneCard(store);
      final container = makeContainer(store);
      await container.read(decksProvider.future);
      final card = container.read(dueCardsProvider).single;

      await container.read(decksProvider.notifier).rateCard(card, Rating.easy);

      expect(container.read(dueCardsProvider), isEmpty);
      final saved = (await DeckRepository(
        store,
      ).loadDecks()).single.cards.single;
      expect(saved.due.isAfter(now), isTrue);
      expect(store.files['reviews.jsonl'], contains('"cardId":"c1"'));
    },
  );

  test(
    'rateCard Again keeps the card in the due list via learn-ahead',
    () async {
      final store = MemoryFileStore();
      await seedOneCard(store);
      final container = makeContainer(store);
      await container.read(decksProvider.future);
      final card = container.read(dueCardsProvider).single;

      await container.read(decksProvider.notifier).rateCard(card, Rating.again);

      final due = container.read(dueCardsProvider);
      expect(due.map((c) => c.id), ['c1']);
      expect(due.single.due.isAfter(now), isTrue);
    },
  );

  test('dueCards excludes review-state cards due beyond now', () async {
    final store = MemoryFileStore();
    await DeckRepository(store).saveDeck(
      Deck(
        id: 'd1',
        name: 'D',
        createdAt: now,
        updatedAt: now,
        cards: [
          Flashcard(
            id: 'later',
            deckId: 'd1',
            front: 'f',
            back: 'b',
            createdAt: now,
            updatedAt: now,
            scheduling: fsrs.Card(
              cardId: 1,
              state: fsrs.State.review,
              stability: 5,
              difficulty: 5,
              due: now.add(const Duration(minutes: 5)),
              lastReview: now.subtract(const Duration(days: 3)),
            ),
          ),
        ],
      ),
    );
    final container = makeContainer(store);
    await container.read(decksProvider.future);

    expect(container.read(dueCardsProvider), isEmpty);
  });

  test('allCardsProvider flattens every deck', () async {
    final store = MemoryFileStore();
    final container = makeContainer(store);
    final decks = await container.read(decksProvider.future);

    final all = container.read(allCardsProvider);
    expect(all.length, decks.fold(0, (n, d) => n + d.cards.length));
  });

  test('updateCard rewrites both sides and persists', () async {
    final store = MemoryFileStore();
    await seedOneCard(store);
    final container = makeContainer(store);
    await container.read(decksProvider.future);
    final card = container.read(allCardsProvider).single;

    await container.read(decksProvider.notifier).updateCard(card, 'q2', 'a2');

    final saved = (await DeckRepository(store).loadDecks()).single.cards.single;
    expect((saved.front, saved.back), ('q2', 'a2'));
    expect(saved.scheduling, card.scheduling);
  });

  test('deleteCard drops the card from the deck and persists', () async {
    final store = MemoryFileStore();
    await seedOneCard(store);
    final container = makeContainer(store);
    await container.read(decksProvider.future);
    final card = container.read(allCardsProvider).single;

    await container.read(decksProvider.notifier).deleteCard(card);

    expect(container.read(allCardsProvider), isEmpty);
    expect((await DeckRepository(store).loadDecks()).single.cards, isEmpty);
  });
}
