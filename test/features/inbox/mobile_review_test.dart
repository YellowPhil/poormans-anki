import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poormans_anki/data/deck_repository.dart';
import 'package:poormans_anki/features/inbox/mobile_review.dart';
import 'package:poormans_anki/storage/memory_file_store.dart';

import '../test_harness.dart';

void main() {
  Future<MemoryFileStore> pumpReview(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = await storeWith([
      deck('d1', 'French', [
        card('c1', 'd1', 'vouloir', 'to want'),
        card('c2', 'd1', 'pouvoir', 'to be able'),
      ]),
    ]);
    await tester.pumpWidget(harness(store, const MobileReview()));
    await tester.pumpAndSettle();
    return store;
  }

  testWidgets('tap flips the card, Easy rates and advances', (tester) async {
    await pumpReview(tester);

    expect(find.text('0 / 2'), findsOneWidget);
    expect(find.text('French'), findsOneWidget);
    expect(find.text('vouloir'), findsOneWidget);
    expect(find.text('to want'), findsNothing);
    for (final label in ['Again', 'Hard', 'Good', 'Easy']) {
      expect(find.text(label), findsOneWidget);
    }

    await tester.tap(find.byKey(const Key('review-card')));
    await tester.pumpAndSettle();
    expect(find.text('to want'), findsOneWidget);

    await tester.tap(find.byKey(const Key('rate-easy')));
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('pouvoir'), findsOneWidget);
    expect(find.text('to be able'), findsNothing);
  });

  testWidgets(
    'Again keeps the card in the session without inflating progress',
    (tester) async {
      final store = await pumpReview(tester);

      await tester.tap(find.byKey(const Key('rate-again')));
      await tester.pumpAndSettle();
      expect(find.text('1 / 2'), findsOneWidget);
      expect(store.files['reviews.jsonl'], contains('"rating":1'));
    },
  );

  testWidgets('top-right menu removes the current card', (tester) async {
    final store = await pumpReview(tester);

    await tester.tap(find.byKey(const Key('card-menu-c1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-remove')));
    await tester.pumpAndSettle();

    expect(find.text('vouloir'), findsNothing);
    expect(find.text('pouvoir'), findsOneWidget);
    final saved = (await DeckRepository(store).loadDecks()).single;
    expect(saved.cards.map((c) => c.id), ['c2']);
  });
}
