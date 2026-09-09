import 'package:anki_core/anki_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/seed_data.dart';
import '../sync/sync_service.dart';
import 'providers.dart';

class DecksNotifier extends AsyncNotifier<List<Deck>> {
  static const _uuid = Uuid();

  @override
  Future<List<Deck>> build() async {
    final repo = ref.watch(deckRepositoryProvider);
    final decks = await repo.loadDecks();
    if (decks.isNotEmpty) return decks;
    final sync = await ref.read(syncSettingsProvider.future);
    if (sync.enabled) return const [];
    return _seed();
  }

  /// Sync-enabled replicas seed only after the first pull came back empty, so
  /// two devices never create two copies of the sample decks.
  Future<void> seedIfEmpty() async {
    if (_current().isNotEmpty) return;
    state = AsyncData(await _seed());
    ref.read(syncServiceProvider.notifier).schedule();
  }

  Future<List<Deck>> _seed() async {
    final repo = ref.read(deckRepositoryProvider);
    final seeded = seedDecks(ref.read(clockProvider)())
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    for (final deck in seeded) {
      await repo.saveDeck(deck);
    }
    return seeded;
  }

  Future<void> applyRemote(
    List<Deck> remote,
    List<DeckTombstone> tombstones,
  ) async {
    final repo = ref.read(deckRepositoryProvider);
    final next = <String, Deck>{for (final d in _current()) d.id: d};
    var changed = false;
    for (final incoming in remote) {
      final local = next[incoming.id];
      final merged = local == null ? incoming : mergeDecks(local, incoming);
      if (local != null && sameDeck(local, merged)) continue;
      next[incoming.id] = merged;
      changed = true;
      await repo.saveDeck(merged);
    }
    for (final tombstone in tombstones) {
      final local = next[tombstone.id];
      if (local == null || !tombstone.deletedAt.isAfter(local.updatedAt)) {
        continue;
      }
      next.remove(tombstone.id);
      changed = true;
      await repo.deleteDeck(tombstone.id);
    }
    if (!changed) return;
    final decks = next.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    state = AsyncData(decks);
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
        removedCards: {...deck.removedCards, card.id: now},
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
    ref.read(syncServiceProvider.notifier).schedule();
  }
}
