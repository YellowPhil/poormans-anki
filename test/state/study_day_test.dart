import 'package:flutter_test/flutter_test.dart';
import 'package:poormans_anki/state/study_day.dart';

void main() {
  test('hours before the rollover belong to the previous study day', () {
    expect(studyDayOf(DateTime(2026, 11, 2, 3, 59)), DateTime(2026, 11, 1));
    expect(studyDayOf(DateTime(2026, 11, 2, 4)), DateTime(2026, 11, 2));
    expect(studyDayOf(DateTime(2026, 11, 2, 23)), DateTime(2026, 11, 2));
  });

  test('study day ends at the next rollover', () {
    expect(
      studyDayEnd(DateTime(2026, 11, 2, 10)),
      DateTime(2026, 11, 3, dayRolloverHour),
    );
    expect(
      studyDayEnd(DateTime(2026, 11, 3, 1)),
      DateTime(2026, 11, 3, dayRolloverHour),
    );
  });

  test('studyDaysBetween counts rollovers, not 24-hour spans', () {
    final evening = DateTime(2026, 11, 2, 22);
    expect(studyDaysBetween(evening, DateTime(2026, 11, 3, 2)), 0);
    expect(studyDaysBetween(evening, DateTime(2026, 11, 3, 5)), 1);
    expect(studyDaysBetween(evening, DateTime(2026, 11, 1, 12)), -1);
  });
}
