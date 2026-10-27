import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:anki_core/anki_core.dart';

void main() {
  final now = DateTime.utc(2026, 9, 8, 10);

  Flashcard freshCard() => Flashcard(
    id: 'c1',
    deckId: 'd1',
    front: 'hola',
    back: 'hello',
    createdAt: now,
    updatedAt: now,
    scheduling: fsrs.Card(cardId: 1, due: now),
  );

  Flashcard reviewedCard() => Flashcard(
    id: 'c2',
    deckId: 'd1',
    front: 'adiós',
    back: 'goodbye',
    createdAt: now,
    updatedAt: now.add(const Duration(days: 1)),
    scheduling: fsrs.Card(
      cardId: 2,
      state: fsrs.State.review,
      stability: 3.5,
      difficulty: 5.25,
      due: now.add(const Duration(days: 4)),
      lastReview: now.add(const Duration(days: 1)),
    ),
  );

  Map<String, dynamic> roundTrip(Map<String, dynamic> json) =>
      jsonDecode(jsonEncode(json)) as Map<String, dynamic>;

  test('Deck survives JSON round trip', () {
    final deck = Deck(
      id: 'd1',
      name: 'Spanish',
      createdAt: now,
      updatedAt: now,
      cards: [freshCard(), reviewedCard()],
    );

    final restored = Deck.fromJson(roundTrip(deck.toJson()));

    expect(restored.toJson(), deck.toJson());
    expect(restored.cards[1].scheduling.stability, 3.5);
    expect(restored.cards[1].scheduling.due.isUtc, isTrue);
  });

  test('Deck JSON carries schema version 1', () {
    final deck = Deck(id: 'd1', name: 'x', createdAt: now, updatedAt: now);
    expect(deck.toJson()['version'], 1);
  });

  test('ReviewEntry survives JSON round trip', () {
    final entry = ReviewEntry(
      id: 'r1',
      cardId: 'c1',
      deckId: 'd1',
      rating: Rating.hard,
      reviewedAt: now,
    );

    final restored = ReviewEntry.fromJson(roundTrip(entry.toJson()));

    expect(restored.toJson(), entry.toJson());
    expect(restored.rating, Rating.hard);
    expect(entry.toJson()['rating'], 2);
  });

  test('ReviewEntry without an id gets the v1 legacy id', () {
    final restored = ReviewEntry.fromJson({
      'cardId': 'c1',
      'deckId': 'd1',
      'rating': 3,
      'reviewedAt': now.toIso8601String(),
    });
    expect(restored.id, 'v1:c1@2026-09-08T10:00:00.000Z');
  });

  test('Flashcard.copyWith replaces scheduling and updatedAt only', () {
    final card = freshCard();
    final later = now.add(const Duration(minutes: 5));
    final next = fsrs.Card(cardId: 1, due: later);

    final updated = card.copyWith(scheduling: next, updatedAt: later);

    expect(updated.id, card.id);
    expect(updated.front, card.front);
    expect(updated.scheduling.due, later);
    expect(updated.updatedAt, later);
    expect(card.scheduling.due, now);
  });
}
