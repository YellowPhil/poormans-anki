import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:poormans_anki/features/deck/card_status.dart';

import '../test_harness.dart';

void main() {
  test('unreviewed card is NEW', () {
    final c = card('c1', 'd1', 'a', 'b');
    expect(cardStatus(c), (phase: CardPhase.fresh, label: 'NEW'));
  });

  test('reviewed card shows interval in days', () {
    final base = card('c1', 'd1', 'a', 'b');
    final scheduled = base.copyWith(
      scheduling: fsrs.Card(
        cardId: 1,
        state: fsrs.State.review,
        lastReview: testNow,
        due: testNow.add(const Duration(days: 3)),
      ),
    );
    expect(cardStatus(scheduled), (phase: CardPhase.review, label: '3 DAYS'));

    final learning = base.copyWith(
      scheduling: fsrs.Card(
        cardId: 1,
        state: fsrs.State.learning,
        lastReview: testNow,
        due: testNow.add(const Duration(minutes: 10)),
      ),
    );
    expect(cardStatus(learning), (phase: CardPhase.learning, label: '0 DAYS'));
  });

  test('due label', () {
    final c = card('c1', 'd1', 'a', 'b');
    expect(dueLabel(c, testNow), 'Due today');
    expect(
      dueLabel(
        c.copyWith(
          scheduling: fsrs.Card(
            cardId: 1,
            due: testNow.add(const Duration(days: 1)),
          ),
        ),
        testNow,
      ),
      'Due tomorrow',
    );
    expect(
      dueLabel(
        c.copyWith(
          scheduling: fsrs.Card(
            cardId: 1,
            due: testNow.add(const Duration(days: 5)),
          ),
        ),
        testNow,
      ),
      'Due in 5 days',
    );
  });
}
