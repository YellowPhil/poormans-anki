import 'dart:convert';

import 'package:anki_core/anki_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:poormans_anki/data/seed_data.dart';
import 'package:poormans_anki/state/providers.dart';
import 'package:poormans_anki/storage/memory_file_store.dart';

import '../features/test_harness.dart';

void main() {
  final now = testNow;

  ProviderContainer makeContainer(MemoryFileStore store, {DateTime? clock}) {
    final container = ProviderContainer(
      overrides: [
        fileStoreProvider.overrideWithValue(store),
        clockProvider.overrideWithValue(() => clock ?? now),
        schedulerProvider.overrideWithValue(CardScheduler(fuzz: false)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<MemoryFileStore> oneCard() => storeWith([
    deck('d1', 'D', [card('c1', 'd1', 'f', 'b')]),
  ]);

  test('build seeds the sample decks into an empty store', () async {
    final store = MemoryFileStore();
    final decks = await makeContainer(store).read(decksProvider.future);

    expect(decks.map((d) => d.name), ['Capitals', 'Spanish basics']);
    expect(decks.map((d) => d.id), [
      seedId('Capitals'),
      seedId('Spanish basics'),
    ]);
    expect(await persistedDecks(store), hasLength(2));
  });

  test('build does not seed when decks already exist', () async {
    final decks = await makeContainer(await oneCard())
        .read(decksProvider.future);
    expect(decks.map((d) => d.id), ['d1']);
  });

  test('build does not seed when sync is enabled', () async {
    final store = MemoryFileStore();
    await store.write(
      'sync/settings.json',
      jsonEncode({'serverUrl': 'http://x'}),
    );
    final decks = await makeContainer(store).read(decksProvider.future);
    expect(decks, isEmpty);
  });

  test('createDeck persists a new empty deck', () async {
    final store = await oneCard();
    final container = makeContainer(store);
    await container.read(decksProvider.future);

    final deck = await container.read(decksProvider.notifier).createDeck('New');

    expect(deck.cards, isEmpty);
    expect(container.read(decksProvider).value, hasLength(2));
    expect(await persistedDecks(store), hasLength(2));
  });

  test('addCard appends a due card to the deck and persists it', () async {
    final store = await oneCard();
    final later = now.add(const Duration(minutes: 1));
    final container = makeContainer(store, clock: later);
    await container.read(decksProvider.future);

    final added = await container
        .read(decksProvider.notifier)
        .addCard('d1', 'q', 'a');

    expect(added.due, later);
    final saved = (await persistedDecks(store)).single;
    expect(saved.cards.map((c) => c.front), ['f', 'q']);
    expect(container.read(dueCardsProvider).map((c) => c.front), ['f', 'q']);
  });

  test(
    'rateCard Easy graduates the card out of the due list and persists review',
    () async {
      final store = await oneCard();
      final container = makeContainer(store);
      await container.read(decksProvider.future);
      final card = container.read(dueCardsProvider).single;

      await container.read(decksProvider.notifier).rateCard(card, Rating.easy);

      expect(container.read(dueCardsProvider), isEmpty);
      final saved = (await persistedDecks(store)).single.cards.single;
      expect(saved.due.isAfter(now), isTrue);
      expect(await persistedRatings(store), [Rating.easy]);
    },
  );

  test(
    'rateCard Again keeps the card in the due list via learn-ahead',
    () async {
      final store = await oneCard();
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
    final store = await storeWith([
      deck('d1', 'D', [card('later', 'd1', 'f', 'b').copyWith()]),
    ]);
    await store.write(
      'reviews.jsonl',
      '${jsonEncode({'cardId': 'later', 'deckId': 'd1', 'rating': 4, 'reviewedAt': now.toIso8601String()})}\n',
    );
    final container = makeContainer(store);
    await container.read(decksProvider.future);

    final later = container.read(allCardsProvider).single;
    expect(later.scheduling.state, fsrs.State.review);
    expect(container.read(dueCardsProvider), isEmpty);
  });

  test('allCardsProvider flattens every deck', () async {
    final container = makeContainer(MemoryFileStore());
    final decks = await container.read(decksProvider.future);

    final all = container.read(allCardsProvider);
    expect(all.length, decks.fold(0, (n, d) => n + d.cards.length));
    expect(all, hasLength(20));
  });

  test('updateCard rewrites both sides and keeps scheduling', () async {
    final store = await oneCard();
    final container = makeContainer(store);
    await container.read(decksProvider.future);
    final card = container.read(allCardsProvider).single;

    await container.read(decksProvider.notifier).updateCard(card, 'q2', 'a2');

    final saved = (await persistedDecks(store)).single.cards.single;
    expect((saved.front, saved.back), ('q2', 'a2'));
    expect(saved.scheduling.toMap(), card.scheduling.toMap());
  });

  test('deleteCard drops the card from the deck and persists', () async {
    final store = await oneCard();
    final container = makeContainer(store);
    await container.read(decksProvider.future);
    final card = container.read(allCardsProvider).single;

    await container.read(decksProvider.notifier).deleteCard(card);

    expect(container.read(allCardsProvider), isEmpty);
    expect((await persistedDecks(store)).single.cards, isEmpty);
  });
}
