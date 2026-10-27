import 'dart:convert';

import 'package:anki_core/anki_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:poormans_anki/data/collection_store.dart';
import 'package:poormans_anki/state/providers.dart';
import 'package:poormans_anki/storage/memory_file_store.dart';

final testNow = DateTime.utc(2026, 9, 8, 12);

Widget harness(MemoryFileStore store, Widget tab) => ProviderScope(
  overrides: [
    fileStoreProvider.overrideWithValue(store),
    clockProvider.overrideWithValue(() => testNow),
    schedulerProvider.overrideWithValue(CardScheduler(fuzz: false)),
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

/// Writes the pre-v2 on-disk layout, so every widget test also exercises the
/// one-time legacy import.
Future<MemoryFileStore> storeWith(List<Deck> decks) async {
  final store = MemoryFileStore();
  for (final d in decks) {
    await store.write('decks/${d.id}.json', jsonEncode(d.toJson()));
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

var _ids = 0;

/// What a fresh app launch would load from [store].
Future<Collection> persisted(MemoryFileStore store) async {
  final reopened = CollectionStore(
    store,
    scheduler: CardScheduler(fuzz: false),
    newId: () => 'reopen-${_ids++}',
  );
  await reopened.open();
  return reopened.view;
}

Future<List<Deck>> persistedDecks(MemoryFileStore store) async =>
    (await persisted(store)).decks;

Future<List<Rating>> persistedRatings(MemoryFileStore store) async => [
  for (final r in (await persisted(store)).reviews) r.rating,
];
