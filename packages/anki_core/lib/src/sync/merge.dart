import 'dart:convert';

import '../domain/deck.dart';
import '../domain/flashcard.dart';

/// Commutative, associative and idempotent: replicas converge regardless of
/// the order in which they exchange decks. Per-card last-writer-wins on
/// `updatedAt`; an edit newer than a tombstone resurrects the card.
Deck mergeDecks(Deck a, Deck b) {
  final newest = b.updatedAt.isAfter(a.updatedAt) ? b : a;
  final removed = <String, DateTime>{...a.removedCards};
  for (final MapEntry(:key, :value) in b.removedCards.entries) {
    final existing = removed[key];
    if (existing == null || value.isAfter(existing)) removed[key] = value;
  }
  final byId = <String, Flashcard>{};
  for (final card in [...a.cards, ...b.cards]) {
    final existing = byId[card.id];
    if (existing == null || card.updatedAt.isAfter(existing.updatedAt)) {
      byId[card.id] = card;
    }
  }
  final cards = <Flashcard>[];
  for (final card in byId.values) {
    final deletedAt = removed[card.id];
    if (deletedAt == null || card.updatedAt.isAfter(deletedAt)) {
      cards.add(card);
      removed.remove(card.id);
    }
  }
  cards.sort((x, y) {
    final byCreated = x.createdAt.compareTo(y.createdAt);
    return byCreated != 0 ? byCreated : x.id.compareTo(y.id);
  });
  return Deck(
    id: a.id,
    name: newest.name,
    createdAt: a.createdAt.isBefore(b.createdAt) ? a.createdAt : b.createdAt,
    updatedAt: newest.updatedAt,
    cards: cards,
    removedCards: removed,
  );
}

bool sameDeck(Deck a, Deck b) =>
    jsonEncode(a.toJson()) == jsonEncode(b.toJson());
