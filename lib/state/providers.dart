import 'package:anki_core/anki_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fsrs/fsrs.dart' as fsrs;

import '../data/deck_repository.dart';

import '../scheduler/review_scheduler.dart';
import '../storage/file_store.dart';
import 'decks_notifier.dart';

/// Must be overridden at the root `ProviderScope`; there is no default backend.
final fileStoreProvider = Provider<FileStore>(
  (_) => throw UnimplementedError('fileStoreProvider must be overridden'),
);

final clockProvider = Provider<DateTime Function()>(
  (_) =>
      () => DateTime.now().toUtc(),
);

final schedulerProvider = Provider<ReviewScheduler>((_) => ReviewScheduler());

final deckRepositoryProvider = Provider<DeckRepository>(
  (ref) => DeckRepository(ref.watch(fileStoreProvider)),
);

final decksProvider = AsyncNotifierProvider<DecksNotifier, List<Deck>>(
  DecksNotifier.new,
);

final allCardsProvider = Provider<List<Flashcard>>((ref) {
  final decks = ref.watch(decksProvider).value ?? const [];
  return [for (final d in decks) ...d.cards];
});

const learnAheadWindow = Duration(minutes: 20);

/// Cards due now, plus learning/relearning cards due within [learnAheadWindow]
/// so a card rated Again stays in the current session.
final dueCardsProvider = Provider<List<Flashcard>>((ref) {
  final now = ref.watch(clockProvider)();
  final horizon = now.add(learnAheadWindow);
  final due = [
    for (final c in ref.watch(allCardsProvider))
      if (!c.due.isAfter(now) ||
          (c.scheduling.state != fsrs.State.review && !c.due.isAfter(horizon)))
        c,
  ];
  due.sort((a, b) => a.due.compareTo(b.due));
  return due;
});

final dueCountByDeckProvider = Provider<Map<String, int>>((ref) {
  final counts = <String, int>{};
  for (final c in ref.watch(dueCardsProvider)) {
    counts.update(c.deckId, (n) => n + 1, ifAbsent: () => 1);
  }
  return counts;
});
