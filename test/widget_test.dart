import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poormans_anki/app.dart';
import 'package:poormans_anki/features/deck/deck_view.dart';
import 'package:poormans_anki/features/inbox/inbox_tab.dart';
import 'package:poormans_anki/features/inbox/mobile_review.dart';
import 'package:poormans_anki/features/shell/mobile_tab_bar.dart';
import 'package:poormans_anki/features/shell/sidebar.dart';
import 'package:poormans_anki/state/providers.dart';
import 'package:poormans_anki/storage/memory_file_store.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [fileStoreProvider.overrideWithValue(MemoryFileStore())],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'wide layout shows sidebar with decks and opens Inbox by default',
    (tester) async {
      await pumpApp(tester, const Size(1400, 900));

      expect(find.byType(Sidebar), findsOneWidget);
      expect(find.byType(InboxTab), findsOneWidget);
      expect(find.widgetWithText(NavItem, 'Dashboard'), findsOneWidget);
      expect(find.widgetWithText(NavItem, 'Inbox'), findsOneWidget);
      expect(find.widgetWithText(NavItem, 'Spanish basics'), findsOneWidget);
      expect(find.widgetWithText(NavItem, 'Capitals'), findsOneWidget);

      await tester.tap(find.widgetWithText(NavItem, 'Capitals'));
      await tester.pumpAndSettle();
      expect(find.byType(DeckView), findsOneWidget);
      expect(find.text('France'), findsOneWidget);

      await tester.tap(find.widgetWithText(NavItem, 'Dashboard'));
      await tester.pumpAndSettle();
      expect(find.text('No statistics yet'), findsOneWidget);
    },
  );

  testWidgets('narrow layout uses a tab bar, drawer sidebar and phone review', (
    tester,
  ) async {
    await pumpApp(tester, const Size(390, 844));

    expect(find.byType(MobileTabBar), findsOneWidget);
    expect(find.byType(MobileReview), findsOneWidget);
    expect(find.byType(Sidebar), findsNothing);

    await tester.tap(find.byKey(const Key('tab-search')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('search-field')), findsOneWidget);

    await tester.tap(find.byKey(const Key('tab-add')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('editor-field')), findsOneWidget);

    await tester.tap(find.byKey(const Key('tab-dashboard')));
    await tester.pumpAndSettle();
    expect(find.text('No statistics yet'), findsOneWidget);

    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    expect(find.byType(Sidebar), findsOneWidget);
    await tester.tap(find.widgetWithText(NavItem, 'Capitals'));
    await tester.pumpAndSettle();
    expect(find.byType(DeckView), findsOneWidget);
    expect(find.byType(Sidebar), findsNothing);
  });

  testWidgets('Cmd+digit navigates between dashboard, inbox and decks', (
    tester,
  ) async {
    await pumpApp(tester, const Size(1400, 900));

    Future<void> press(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
    }

    await press(LogicalKeyboardKey.digit1);
    expect(find.text('No statistics yet'), findsOneWidget);

    await press(LogicalKeyboardKey.digit3);
    expect(find.byType(DeckView), findsOneWidget);
    expect(find.text('France'), findsOneWidget);

    await press(LogicalKeyboardKey.digit2);
    expect(find.byType(InboxTab), findsOneWidget);
  });
}
