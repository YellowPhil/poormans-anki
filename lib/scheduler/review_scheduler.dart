import 'package:anki_core/anki_core.dart';
import 'package:fsrs/fsrs.dart' as fsrs;

class ReviewScheduler {
  ReviewScheduler([fsrs.Scheduler? scheduler])
    : _scheduler = scheduler ?? fsrs.Scheduler();

  final fsrs.Scheduler _scheduler;

  fsrs.Card newScheduling(DateTime now) =>
      fsrs.Card(cardId: now.millisecondsSinceEpoch, due: now);

  /// [now] must be UTC.
  ({Flashcard card, ReviewEntry entry}) rate(
    Flashcard card,
    Rating rating,
    DateTime now,
  ) {
    final result = _scheduler.reviewCard(
      card.scheduling,
      fsrs.Rating.fromValue(rating.value),
      reviewDateTime: now,
    );
    return (
      card: card.copyWith(scheduling: result.card, updatedAt: now),
      entry: ReviewEntry(
        cardId: card.id,
        deckId: card.deckId,
        rating: rating,
        reviewedAt: now,
      ),
    );
  }
}
