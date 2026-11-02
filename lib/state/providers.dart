import 'dart:async';

import 'package:anki_core/anki_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:uuid/uuid.dart';

import '../data/collection_store.dart';
import '../storage/file_store.dart';
import 'decks_notifier.dart';
import 'study_day.dart';

/// Must be overridden at the root `ProviderScope`; there is no default backend.
final fileStoreProvider = Provider<FileStore>(
  (_) => throw UnimplementedError('fileStoreProvider must be overridden'),
);

final clockProvider = Provider<DateTime Function()>(
  (_) =>
      () => DateTime.now().toUtc(),
);

final schedulerProvider = Provider<CardScheduler>((_) => CardScheduler());

final newIdProvider = Provider<String Function()>((_) => const Uuid().v4);

final collectionStoreProvider = FutureProvider<CollectionStore>((ref) async {
  final store = CollectionStore(
    ref.watch(fileStoreProvider),
    scheduler: ref.watch(schedulerProvider),
    newId: ref.watch(newIdProvider),
  );
  ref.onDispose(store.dispose);
  await store.open();
  return store;
});

final decksProvider = AsyncNotifierProvider<DecksNotifier, List<Deck>>(
  DecksNotifier.new,
);

/// Recomputed on every collection change via [decksProvider].
final reviewsProvider = Provider<List<ReviewEntry>>((ref) {
  ref.watch(decksProvider);
  return ref.watch(collectionStoreProvider).value?.view.reviews ?? const [];
});

final allCardsProvider = Provider<List<Flashcard>>((ref) {
  final decks = ref.watch(decksProvider).value ?? const [];
  return [for (final d in decks) ...d.cards];
});

const learnAheadWindow = Duration(minutes: 20);

/// Wall time for due-ness, re-read every [tick] and on [refresh]: derived
/// providers otherwise recompute only on collection changes and go stale.
class NowNotifier extends Notifier<DateTime> {
  static const tick = Duration(minutes: 1);

  @override
  DateTime build() {
    final clock = ref.watch(clockProvider);
    final timer = Timer.periodic(tick, (_) => state = clock());
    ref.onDispose(timer.cancel);
    return clock();
  }

  void refresh() => state = ref.read(clockProvider)();
}

final nowProvider = NotifierProvider<NowNotifier, DateTime>(NowNotifier.new);

/// Review cards due before the current study day ends ([studyDayEnd]), plus
/// learning/relearning cards due within [learnAheadWindow] so a card rated
/// Again stays in the session. Cards due now come first, learn-ahead last.
final dueCardsProvider = Provider<List<Flashcard>>((ref) {
  final now = ref.watch(nowProvider);
  final horizon = now.add(learnAheadWindow);
  final dayEnd = studyDayEnd(now);
  int rank(Flashcard c) => !c.due.isAfter(now)
      ? 0
      : c.scheduling.state == fsrs.State.review
      ? 1
      : 2;
  final due = [
    for (final c in ref.watch(allCardsProvider))
      if (c.scheduling.state == fsrs.State.review
          ? c.due.isBefore(dayEnd)
          : !c.due.isAfter(horizon))
        c,
  ];
  due.sort((a, b) {
    final byRank = rank(a).compareTo(rank(b));
    return byRank != 0 ? byRank : a.due.compareTo(b.due);
  });
  return due;
});

final dueCountByDeckProvider = Provider<Map<String, int>>((ref) {
  final counts = <String, int>{};
  for (final c in ref.watch(dueCardsProvider)) {
    counts.update(c.deckId, (n) => n + 1, ifAbsent: () => 1);
  }
  return counts;
});
