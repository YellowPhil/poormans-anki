import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poormans_anki/data/deck_repository.dart';
import 'package:poormans_anki/features/add/add_tab.dart';

import 'test_harness.dart';

const editor = Key('editor-field');
const deckChip = Key('deck-chip');
const saveButton = Key('save-button');
const addHiddenSide = Key('add-hidden-side');
const clearButton = Key('clear-button');

String editorText(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(editor)).controller!.text;

bool saveEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(saveButton)).onPressed != null;

void main() {
  testWidgets(
    'saves front/back split at --- into the chosen deck and clears the editor',
    (tester) async {
      final store = await storeWith([
        deck('d1', 'Alpha', []),
        deck('d2', 'Beta', []),
      ]);
      await tester.pumpWidget(harness(store, const AddTab()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(deckChip));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(editor), "l'eau\n---\nwater");
      await tester.pump();
      await tester.tap(find.byKey(saveButton));
      await tester.pumpAndSettle();

      final decks = await DeckRepository(store).loadDecks();
      final beta = decks.firstWhere((d) => d.name == 'Beta');
      expect(beta.cards.single.front, "l'eau");
      expect(beta.cards.single.back, 'water');
      expect(decks.firstWhere((d) => d.name == 'Alpha').cards, isEmpty);
      expect(editorText(tester), isEmpty);
    },
  );

  testWidgets('Save is disabled on blank text and enabled with a front only', (
    tester,
  ) async {
    final store = await storeWith([deck('d1', 'Alpha', [])]);
    await tester.pumpWidget(harness(store, const AddTab()));
    await tester.pumpAndSettle();

    expect(saveEnabled(tester), isFalse);

    await tester.enterText(find.byKey(editor), '   \n ');
    await tester.pump();
    expect(saveEnabled(tester), isFalse);

    await tester.enterText(find.byKey(editor), 'a lone note');
    await tester.pump();
    expect(saveEnabled(tester), isTrue);

    await tester.tap(find.byKey(saveButton));
    await tester.pumpAndSettle();
    final card = (await DeckRepository(store).loadDecks()).single.cards.single;
    expect(card.front, 'a lone note');
    expect(card.back, '');
  });

  testWidgets('Add hidden side appends a separator once and then disappears', (
    tester,
  ) async {
    final store = await storeWith([deck('d1', 'Alpha', [])]);
    await tester.pumpWidget(harness(store, const AddTab()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(editor), 'front');
    await tester.pump();
    await tester.tap(find.byKey(addHiddenSide));
    await tester.pump();

    expect(editorText(tester), 'front\n---\n');
    expect(find.byKey(addHiddenSide), findsNothing);
  });

  testWidgets('Cmd+Enter saves the card', (tester) async {
    final store = await storeWith([deck('d1', 'Alpha', [])]);
    await tester.pumpWidget(harness(store, const AddTab()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(editor), 'q\n---\na');
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    final cards = (await DeckRepository(store).loadDecks()).single.cards;
    expect(cards.single.front, 'q');
    expect(editorText(tester), isEmpty);
  });

  testWidgets('close button clears the editor without saving', (tester) async {
    final store = await storeWith([deck('d1', 'Alpha', [])]);
    await tester.pumpWidget(harness(store, const AddTab()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(editor), 'draft');
    await tester.pump();
    await tester.tap(find.byKey(clearButton));
    await tester.pumpAndSettle();

    expect(editorText(tester), isEmpty);
    expect((await DeckRepository(store).loadDecks()).single.cards, isEmpty);
  });

  testWidgets('New deck from the chip menu creates and selects the deck', (
    tester,
  ) async {
    final store = await storeWith([deck('d1', 'Alpha', [])]);
    await tester.pumpWidget(harness(store, const AddTab()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(deckChip));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New deck…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('deck-name-field')), 'Gamma');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: find.byKey(deckChip), matching: find.text('Gamma')),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(editor), 'q');
    await tester.pump();
    await tester.tap(find.byKey(saveButton));
    await tester.pumpAndSettle();
    final gamma = (await DeckRepository(
      store,
    ).loadDecks()).firstWhere((d) => d.name == 'Gamma');
    expect(gamma.cards, hasLength(1));
  });
}
