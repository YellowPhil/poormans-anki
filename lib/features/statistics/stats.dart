import 'package:anki_core/anki_core.dart';

import '../../state/study_day.dart';
import '../deck/card_status.dart';

/// Days are local calendar days; arithmetic goes through the `DateTime`
/// constructor so DST shifts never skip or double a day.
DateTime dayOf(DateTime t) {
  final local = t.toLocal();
  return DateTime(local.year, local.month, local.day);
}

DateTime addDays(DateTime day, int days) =>
    DateTime(day.year, day.month, day.day + days);

Map<DateTime, int> reviewsPerDay(Iterable<ReviewEntry> reviews) {
  final counts = <DateTime, int>{};
  for (final r in reviews) {
    counts.update(dayOf(r.reviewedAt), (n) => n + 1, ifAbsent: () => 1);
  }
  return counts;
}

/// A streak survives a today without reviews; it breaks only on a missed day.
int currentStreak(Map<DateTime, int> perDay, DateTime today) {
  var day = (perDay[today] ?? 0) > 0 ? today : addDays(today, -1);
  var streak = 0;
  while ((perDay[day] ?? 0) > 0) {
    streak++;
    day = addDays(day, -1);
  }
  return streak;
}

int longestStreak(Map<DateTime, int> perDay) {
  final days = [
    for (final MapEntry(:key, :value) in perDay.entries)
      if (value > 0) key,
  ]..sort();
  var longest = 0;
  var run = 0;
  DateTime? previous;
  for (final day in days) {
    run = previous != null && addDays(previous, 1) == day ? run + 1 : 1;
    if (run > longest) longest = run;
    previous = day;
  }
  return longest;
}

Map<Rating, int> ratingCounts(Iterable<ReviewEntry> reviews) {
  final counts = {for (final r in Rating.values) r: 0};
  for (final r in reviews) {
    counts[r.rating] = counts[r.rating]! + 1;
  }
  return counts;
}

/// Share of reviews not rated Again; null without reviews.
double? retention(Iterable<ReviewEntry> reviews) {
  var total = 0;
  var recalled = 0;
  for (final r in reviews) {
    total++;
    if (r.rating != Rating.again) recalled++;
  }
  return total == 0 ? null : recalled / total;
}

/// Buckets by study day, matching the inbox; index 0 includes overdue cards.
List<int> dueForecast(Iterable<Flashcard> cards, DateTime now, int days) {
  final counts = List.filled(days, 0);
  for (final c in cards) {
    final offset = studyDaysBetween(now, c.due);
    final index = offset < 0 ? 0 : offset;
    if (index < days) counts[index]++;
  }
  return counts;
}

Map<CardPhase, int> phaseCounts(Iterable<Flashcard> cards) {
  final counts = {for (final p in CardPhase.values) p: 0};
  for (final c in cards) {
    final phase = cardStatus(c).phase;
    counts[phase] = counts[phase]! + 1;
  }
  return counts;
}
