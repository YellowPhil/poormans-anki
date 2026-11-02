import 'dart:convert';

import 'package:anki_core/anki_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:poormans_anki/state/providers.dart';
import 'package:poormans_anki/state/study_day.dart';
import 'package:poormans_anki/storage/memory_file_store.dart';

import '../features/test_harness.dart';

void main() {
  late DateTime clock;

  ProviderContainer makeContainer(MemoryFileStore store) {
    final container = ProviderContainer(
      overrides: [
        fileStoreProvider.overrideWithValue(store),
        clockProvider.overrideWithValue(() => clock),
        schedulerProvider.overrideWithValue(CardScheduler(fuzz: false)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<MemoryFileStore> easyReviewed() async {
    final store = await storeWith([
      deck('d1', 'D', [card('c1', 'd1', 'f', 'b')]),
    ]);
    await store.write(
      'reviews.jsonl',
      '${jsonEncode({'cardId': 'c1', 'deckId': 'd1', 'rating': 4, 'reviewedAt': testNow.toIso8601String()})}\n',
    );
    return store;
  }

  setUp(() => clock = testNow);

  test('review card due later in the current study day is due', () async {
    final container = makeContainer(await easyReviewed());
    await container.read(decksProvider.future);
    final due = container.read(allCardsProvider).single.due;
    final dayStart = studyDayOf(due);

    clock = DateTime(
      dayStart.year,
      dayStart.month,
      dayStart.day,
      dayRolloverHour,
    ).subtract(const Duration(minutes: 1));
    container.read(nowProvider.notifier).refresh();
    expect(container.read(dueCardsProvider), isEmpty);

    clock = clock.add(const Duration(minutes: 1));
    container.read(nowProvider.notifier).refresh();
    expect(due.isAfter(clock), isTrue);
    expect(container.read(dueCardsProvider).map((c) => c.id), ['c1']);
  });

  test('due list follows the clock without a collection change', () async {
    final container = makeContainer(await easyReviewed());
    await container.read(decksProvider.future);
    expect(container.read(dueCardsProvider), isEmpty);

    clock = container.read(allCardsProvider).single.due;
    expect(container.read(dueCardsProvider), isEmpty);

    container.read(nowProvider.notifier).refresh();
    expect(container.read(dueCardsProvider).map((c) => c.id), ['c1']);
  });

  test('cards due now precede learn-ahead cards', () async {
    final store = await storeWith([
      deck('d1', 'D', [
        card('ahead', 'd1', 'a', 'b'),
        card('now', 'd1', 'c', 'd'),
      ]),
    ]);
    final container = makeContainer(store);
    await container.read(decksProvider.future);
    final ahead = container
        .read(dueCardsProvider)
        .firstWhere((c) => c.id == 'ahead');
    await container.read(decksProvider.notifier).rateCard(ahead, Rating.again);

    final due = container.read(dueCardsProvider);
    expect(due.map((c) => c.id), ['now', 'ahead']);
    expect(due.last.scheduling.state, fsrs.State.learning);
    expect(due.last.due.isAfter(clock), isTrue);
  });
}
