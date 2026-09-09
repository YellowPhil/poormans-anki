import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:anki_core/anki_core.dart';
import 'package:poormans_anki/scheduler/review_scheduler.dart';

void main() {
  final now = DateTime.utc(2026, 1, 1, 12);
  final scheduler = ReviewScheduler(fsrs.Scheduler(enableFuzzing: false));

  Flashcard card() => Flashcard(
    id: 'c1',
    deckId: 'd1',
    front: 'f',
    back: 'b',
    createdAt: now,
    updatedAt: now,
    scheduling: scheduler.newScheduling(now),
  );

  test('newScheduling is due immediately in learning state', () {
    final s = scheduler.newScheduling(now);
    expect(s.due, now);
    expect(s.state, fsrs.State.learning);
    expect(s.cardId, now.millisecondsSinceEpoch);
  });

  test('rate Good pushes due forward and records the review', () {
    final (card: updated, entry: entry) = scheduler.rate(
      card(),
      Rating.good,
      now,
    );

    expect(updated.due.isAfter(now), isTrue);
    expect(updated.scheduling.lastReview, now);
    expect(updated.updatedAt, now);
    expect(entry.cardId, 'c1');
    expect(entry.deckId, 'd1');
    expect(entry.rating, Rating.good);
    expect(entry.reviewedAt, now);
  });

  test('easier ratings schedule no sooner than harder ones', () {
    final again = scheduler.rate(card(), Rating.again, now).card.due;
    final hard = scheduler.rate(card(), Rating.hard, now).card.due;
    final good = scheduler.rate(card(), Rating.good, now).card.due;
    final easy = scheduler.rate(card(), Rating.easy, now).card.due;

    expect(again.isAfter(hard), isFalse);
    expect(hard.isAfter(good), isFalse);
    expect(good.isAfter(easy), isFalse);
    expect(again.isBefore(easy), isTrue);
  });

  test('rate leaves the input card untouched', () {
    final original = card();
    scheduler.rate(original, Rating.easy, now);

    expect(original.due, now);
    expect(original.scheduling.lastReview, isNull);
  });

  test('rate rejects non-UTC review time', () {
    expect(
      () => scheduler.rate(card(), Rating.good, DateTime(2026, 1, 1)),
      throwsArgumentError,
    );
  });
}
