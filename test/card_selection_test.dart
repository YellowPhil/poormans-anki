import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poormans_anki/app.dart';
import 'package:poormans_anki/state/providers.dart';
import 'package:poormans_anki/storage/memory_file_store.dart';
import 'package:poormans_anki/widgets/card_face.dart';

void main() {
  testWidgets('double-clicking review card text selects and copies a word', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [fileStoreProvider.overrideWithValue(MemoryFileStore())],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();

    final face = find.byType(CardFace).first;
    final text = find.descendant(of: face, matching: find.byType(RichText));
    final target = tester.getTopLeft(text.first) + const Offset(8, 12);
    final gesture = await tester.startGesture(
      target,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.down(target);
    await gesture.up();
    await tester.pumpAndSettle();

    final modifier = defaultTargetPlatform == TargetPlatform.macOS
        ? LogicalKeyboardKey.meta
        : LogicalKeyboardKey.control;
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(modifier);
    await tester.pump();

    expect(copied, isNotEmpty);
  }, variant: TargetPlatformVariant.desktop());
}
