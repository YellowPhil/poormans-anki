import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poormans_anki/features/deck/card_detail.dart';
import 'package:poormans_anki/features/deck/card_tile.dart';
import 'package:poormans_anki/features/deck/deck_view.dart';

import '../test_harness.dart';

void main() {
  final d = deck('d1', 'Flashcards', [
    card('c1', 'd1', 'la poubelle', 'rubbish bin'),
    card('c2', 'd1', 'la terre', 'earth'),
    card('c3', 'd1', 'lone note', ''),
  ]);

  Future<void> pumpDeck(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = await storeWith([d]);
    await tester.pumpWidget(harness(store, const DeckView(deckId: 'd1')));
    await tester.pumpAndSettle();
  }

  testWidgets('grid shows a tile per card plus the new-card tile', (
    tester,
  ) async {
    await pumpDeck(tester);

    expect(find.byType(CardTile), findsNWidgets(3));
    expect(find.text('la poubelle'), findsOneWidget);
    expect(find.text('rubbish bin'), findsNothing);
    expect(find.text('+ 1 HIDDEN SIDE'), findsNWidgets(2));
    expect(find.text('NEW'), findsNWidgets(3));
    expect(find.text('New Card'), findsNWidgets(2));
  });

  testWidgets('tapping a tile opens the detail with the back side', (
    tester,
  ) async {
    await pumpDeck(tester);

    await tester.tap(find.text('la poubelle'));
    await tester.pumpAndSettle();

    expect(find.byType(CardDetail), findsOneWidget);
    expect(find.text('rubbish bin'), findsOneWidget);
    expect(find.text('Flashcards'), findsNWidgets(2));
    expect(find.text('Due today'), findsOneWidget);
  });

  testWidgets('search filters tiles across front and back', (tester) async {
    await pumpDeck(tester);

    await tester.enterText(find.byKey(const Key('deck-search')), 'EARTH');
    await tester.pumpAndSettle();

    expect(find.byType(CardTile), findsOneWidget);
    expect(find.text('la terre'), findsOneWidget);
  });

  testWidgets('new card button opens the editor for this deck', (tester) async {
    await pumpDeck(tester);

    await tester.tap(find.byKey(const Key('new-card-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('editor-field')), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Flashcards'), findsOneWidget);
  });

  testWidgets('review button shows due count', (tester) async {
    await pumpDeck(tester);

    expect(find.widgetWithText(GestureDetector, 'Review'), findsWidgets);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('tile menu edits the card in place', (tester) async {
    await pumpDeck(tester);

    await tester.tap(find.byKey(const Key('card-menu-c2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    final field = find.byKey(const Key('card-editor-field'));
    expect(
      tester.widget<TextField>(field).controller!.text,
      'la terre\n---\nearth',
    );
    await tester.enterText(field, 'la terre\n---\nthe earth');
    await tester.tap(find.byKey(const Key('card-editor-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('card-editor-field')), findsNothing);
    await tester.tap(find.text('la terre'));
    await tester.pumpAndSettle();
    expect(find.text('the earth'), findsOneWidget);
  });

  testWidgets('tile menu removes the card after confirmation', (tester) async {
    await pumpDeck(tester);

    await tester.tap(find.byKey(const Key('card-menu-c3')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Remove card?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-remove')));
    await tester.pumpAndSettle();

    expect(find.text('lone note'), findsNothing);
    expect(find.byType(CardTile), findsNWidgets(2));
  });
}
