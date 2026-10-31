import 'package:anki_core/anki_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poormans_anki/features/statistics/statistics_tab.dart';
import 'package:poormans_anki/state/providers.dart';

import '../test_harness.dart';

void main() {
  ReviewEntry review(String id, int daysAgo, Rating rating) => ReviewEntry(
    id: id,
    cardId: 'c1',
    deckId: 'd1',
    rating: rating,
    reviewedAt: testNow.subtract(Duration(days: daysAgo)),
  );

  Future<void> pump(WidgetTester tester, List<ReviewEntry> reviews) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = await storeWith([
      deck('d1', 'French', [
        card('c1', 'd1', 'a', 'b'),
        card('c2', 'd1', 'c', 'd'),
      ]),
    ]);
    await tester.pumpWidget(
      harness(
        store,
        const StatisticsTab(),
        overrides: [reviewsProvider.overrideWithValue(reviews)],
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('summarises reviews, streak, retention and cards', (
    tester,
  ) async {
    await pump(tester, [
      review('r1', 0, Rating.good),
      review('r2', 0, Rating.again),
      review('r3', 1, Rating.easy),
      review('r4', 2, Rating.hard),
    ]);

    String tile(String key) => tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(Key(key)),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data)
        .join('|');

    expect(tile('stat-today'), contains('|2|'));
    expect(tile('stat-streak'), contains('3 days'));
    expect(tile('stat-retention'), contains('75%'));
    expect(tile('stat-cards'), contains('2 new · 0 learning · 0 review'));
    expect(find.text('1 · 25%'), findsNWidgets(4));
    expect(find.text('4 reviews in the last year'), findsOneWidget);
    expect(find.byType(ActivityHeatmap), findsOneWidget);
  });

  testWidgets('renders an empty state without reviews', (tester) async {
    await pump(tester, []);

    expect(find.text('—'), findsOneWidget);
    expect(find.text('0 reviews in the last year'), findsOneWidget);
  });
}
