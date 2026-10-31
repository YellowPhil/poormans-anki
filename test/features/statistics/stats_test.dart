import 'package:anki_core/anki_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poormans_anki/features/statistics/stats.dart';

ReviewEntry review(DateTime at, [Rating rating = Rating.good]) => ReviewEntry(
  id: 'r${at.microsecondsSinceEpoch}${rating.name}',
  cardId: 'c',
  deckId: 'd',
  rating: rating,
  reviewedAt: at.toUtc(),
);

void main() {
  final today = DateTime(2026, 10, 31);

  test('reviewsPerDay buckets by local calendar day', () {
    final perDay = reviewsPerDay([
      review(DateTime(2026, 10, 31, 0, 5)),
      review(DateTime(2026, 10, 31, 23, 55)),
      review(DateTime(2026, 10, 30, 12)),
    ]);
    expect(perDay, {today: 2, DateTime(2026, 10, 30): 1});
  });

  group('currentStreak', () {
    test('counts consecutive days ending today', () {
      final perDay = {today: 1, addDays(today, -1): 3, addDays(today, -3): 1};
      expect(currentStreak(perDay, today), 2);
    });

    test('a today without reviews keeps yesterday’s streak alive', () {
      final perDay = {addDays(today, -1): 1, addDays(today, -2): 1};
      expect(currentStreak(perDay, today), 2);
    });

    test('a missed yesterday breaks it', () {
      expect(currentStreak({addDays(today, -2): 1}, today), 0);
    });
  });

  test('longestStreak finds the longest run of consecutive days', () {
    final perDay = {
      for (var i = 0; i < 4; i++) addDays(today, -10 - i): 1,
      today: 1,
      addDays(today, -1): 1,
    };
    expect(longestStreak(perDay), 4);
    expect(longestStreak({}), 0);
  });

  test('retention is the share of reviews not rated Again', () {
    expect(retention([]), isNull);
    expect(
      retention([
        review(today, Rating.again),
        review(today, Rating.hard),
        review(today, Rating.good),
        review(today, Rating.easy),
      ]),
      0.75,
    );
  });

  test('ratingCounts includes every rating', () {
    expect(ratingCounts([review(today, Rating.easy)]), {
      Rating.again: 0,
      Rating.hard: 0,
      Rating.good: 0,
      Rating.easy: 1,
    });
  });
}
