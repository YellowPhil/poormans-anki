/// Anki-style rollover: a study day runs from this local hour to the same hour
/// the next day, so cards due late tonight are reviewable this evening.
const dayRolloverHour = 4;

/// Local calendar date the study day containing [t] started on.
DateTime studyDayOf(DateTime t) {
  final local = t.toLocal();
  final shift = local.hour < dayRolloverHour ? 1 : 0;
  return DateTime(local.year, local.month, local.day - shift);
}

DateTime studyDayEnd(DateTime now) {
  final day = studyDayOf(now);
  return DateTime(day.year, day.month, day.day + 1, dayRolloverHour);
}

/// Counted on calendar dates, so a DST shift never yields a 23-hour "day".
int studyDaysBetween(DateTime from, DateTime to) {
  final a = studyDayOf(from);
  final b = studyDayOf(to);
  return DateTime.utc(
    b.year,
    b.month,
    b.day,
  ).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
}
