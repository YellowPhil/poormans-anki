import 'package:anki_core/anki_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:poormans_anki/features/inbox/inbox_tab.dart';

import 'test_harness.dart';

void main() {
  testWidgets('reveals answer, rates Easy, persists, then shows empty state', (
    tester,
  ) async {
    final store = await storeWith([
      deck('d1', 'Deck', [card('c1', 'd1', 'front text', 'back text')]),
    ]);
    await tester.pumpWidget(harness(store, const InboxTab()));
    await tester.pumpAndSettle();

    expect(find.text('front text'), findsOneWidget);
    expect(find.text('back text'), findsNothing);
    expect(find.text('Next side'), findsOneWidget);
    expect(find.text('Easy'), findsNothing);

    await tester.tap(find.text('Next side'));
    await tester.pumpAndSettle();

    expect(find.text('back text'), findsOneWidget);
    for (final label in ['Again', 'Hard', 'Good', 'Easy']) {
      expect(find.widgetWithText(FilledButton, label), findsOneWidget);
    }

    await tester.tap(find.widgetWithText(FilledButton, 'Easy'));
    await tester.pumpAndSettle();

    expect(find.text('All caught up'), findsOneWidget);
    expect(await persistedRatings(store), [Rating.easy]);
    final saved = (await persistedDecks(store)).single.cards.single;
    expect(saved.due.isAfter(testNow), isTrue);
  });

  testWidgets('next card starts hidden after rating the previous one', (
    tester,
  ) async {
    final store = await storeWith([
      deck('d1', 'Deck', [
        card('c1', 'd1', 'first', 'first back'),
        card('c2', 'd1', 'second', 'second back'),
      ]),
    ]);
    await tester.pumpWidget(harness(store, const InboxTab()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Next side'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Easy'));
    await tester.pumpAndSettle();

    expect(find.text('second'), findsOneWidget);
    expect(find.text('second back'), findsNothing);
    expect(find.text('Next side'), findsOneWidget);
  });

  testWidgets('shows remaining due count', (tester) async {
    final store = await storeWith([
      deck('d1', 'Deck', [
        card('c1', 'd1', 'a', 'b'),
        card('c2', 'd1', 'c', 'd'),
      ]),
    ]);
    await tester.pumpWidget(harness(store, const InboxTab()));
    await tester.pumpAndSettle();

    expect(find.text('2 due'), findsOneWidget);
  });

  testWidgets('renders front and back as markdown', (tester) async {
    final store = await storeWith([
      deck('d1', 'Deck', [
        card('c1', 'd1', '**bold** front', '- item one\n- item two'),
      ]),
    ]);
    await tester.pumpWidget(harness(store, const InboxTab()));
    await tester.pumpAndSettle();

    final front = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
    expect(front.data, '**bold** front');

    await tester.tap(find.text('Next side'));
    await tester.pumpAndSettle();

    final bodies = tester
        .widgetList<MarkdownBody>(find.byType(MarkdownBody))
        .toList();
    expect(bodies.map((b) => b.data), [
      '**bold** front',
      '- item one\n- item two',
    ]);
  });

  testWidgets('a card without a back shows rating buttons immediately', (
    tester,
  ) async {
    final store = await storeWith([
      deck('d1', 'Deck', [card('c1', 'd1', 'lone note', '')]),
    ]);
    await tester.pumpWidget(harness(store, const InboxTab()));
    await tester.pumpAndSettle();

    expect(find.text('Next side'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Good'), findsOneWidget);
  });

  testWidgets('space reveals the answer and 1-4 rate the card', (tester) async {
    final store = await storeWith([
      deck('d1', 'Deck', [
        card('c1', 'd1', 'first', 'first back'),
        card('c2', 'd1', 'second', 'second back'),
      ]),
    ]);
    await tester.pumpWidget(harness(store, const InboxTab()));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
    await tester.pumpAndSettle();
    expect(find.text('first'), findsOneWidget);
    expect(find.text('first back'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('first back'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
    await tester.pumpAndSettle();
    expect(find.text('second'), findsOneWidget);
    expect(find.text('second back'), findsNothing);
    expect(await persistedRatings(store), [Rating.easy]);
  });
}
