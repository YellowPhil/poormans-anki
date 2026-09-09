import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/seed_data.dart';
import '../domain/deck.dart';
import '../domain/flashcard.dart';
import '../domain/rating.dart';
import 'providers.dart';

class DecksNotifier extends AsyncNotifier<List<Deck>> {
  static const _uuid = Uuid();

  @override
  Future<List<Deck>> build() async {
    final repo = ref.watch(deckRepositoryProvider);
    final decks = await repo.loadDecks();
    if (decks.isNotEmpty) return decks;
    final seeded = seedDecks(ref.read(clockProvider)())
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    for (final deck in seeded) {
      await repo.saveDeck(deck);
    }
    return seeded;
  }

  Future<Deck> createDeck(String name) async {
    final now = ref.read(clockProvider)();
    final deck = Deck(
      id: _uuid.v4(),
      name: name,
      createdAt: now,
      updatedAt: now,
    );
    await _replace(deck);
    return deck;
  }

  Future<Flashcard> addCard(String deckId, String front, String back) async {
    final now = ref.read(clockProvider)();
    final deck = _current().firstWhere((d) => d.id == deckId);
    final card = Flashcard(
      id: _uuid.v4(),
      deckId: deckId,
      front: front,
      back: back,
      createdAt: now,
      updatedAt: now,
      scheduling: ref.read(schedulerProvider).newScheduling(now),
    );
    await _replace(deck.copyWith(updatedAt: now, cards: [...deck.cards, card]));
    return card;
  }

  Future<void> rateCard(Flashcard card, Rating rating) async {
    final now = ref.read(clockProvider)();
    final deck = _current().firstWhere((d) => d.id == card.deckId);
    final result = ref.read(schedulerProvider).rate(card, rating, now);
    final cards = [
      for (final c in deck.cards) c.id == card.id ? result.card : c,
    ];
    await _replace(deck.copyWith(updatedAt: now, cards: cards));
    await ref.read(deckRepositoryProvider).appendReview(result.entry);
  }

  Future<void> updateCard(Flashcard card, String front, String back) async {
    final now = ref.read(clockProvider)();
    final deck = _current().firstWhere((d) => d.id == card.deckId);
    final cards = [
      for (final c in deck.cards)
        c.id == card.id
            ? c.copyWith(front: front, back: back, updatedAt: now)
            : c,
    ];
    await _replace(deck.copyWith(updatedAt: now, cards: cards));
  }

  Future<void> deleteCard(Flashcard card) async {
    final now = ref.read(clockProvider)();
    final deck = _current().firstWhere((d) => d.id == card.deckId);
    await _replace(
      deck.copyWith(
        updatedAt: now,
        cards: [
          for (final c in deck.cards)
            if (c.id != card.id) c,
        ],
      ),
    );
  }

  List<Deck> _current() => state.value ?? const [];

  Future<void> _replace(Deck deck) async {
    final decks = _current();
    final index = decks.indexWhere((d) => d.id == deck.id);
    final next = [...decks];
    if (index < 0) {
      next.add(deck);
      next.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } else {
      next[index] = deck;
    }
    state = AsyncData(next);
    await ref.read(deckRepositoryProvider).saveDeck(deck);
  }
}
