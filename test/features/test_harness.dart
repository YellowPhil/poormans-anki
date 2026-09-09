import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:poormans_anki/data/deck_repository.dart';
import 'package:poormans_anki/domain/deck.dart';
import 'package:poormans_anki/domain/flashcard.dart';
import 'package:poormans_anki/scheduler/review_scheduler.dart';
import 'package:poormans_anki/state/providers.dart';
import 'package:poormans_anki/storage/memory_file_store.dart';

final testNow = DateTime.utc(2026, 9, 8, 12);

Widget harness(MemoryFileStore store, Widget tab) => ProviderScope(
  overrides: [
    fileStoreProvider.overrideWithValue(store),
    clockProvider.overrideWithValue(() => testNow),
    schedulerProvider.overrideWithValue(
      ReviewScheduler(fsrs.Scheduler(enableFuzzing: false)),
    ),
  ],
  child: MaterialApp(home: Scaffold(body: tab)),
);

Flashcard card(String id, String deckId, String front, String back) =>
    Flashcard(
      id: id,
      deckId: deckId,
      front: front,
      back: back,
      createdAt: testNow,
      updatedAt: testNow,
      scheduling: fsrs.Card(cardId: 1, due: testNow),
    );

Future<MemoryFileStore> storeWith(List<Deck> decks) async {
  final store = MemoryFileStore();
  final repo = DeckRepository(store);
  for (final d in decks) {
    await repo.saveDeck(d);
  }
  return store;
}

Deck deck(String id, String name, List<Flashcard> cards) => Deck(
  id: id,
  name: name,
  createdAt: testNow,
  updatedAt: testNow,
  cards: cards,
);
