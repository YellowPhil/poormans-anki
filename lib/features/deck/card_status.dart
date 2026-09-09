import 'package:anki_core/anki_core.dart';
import 'package:fsrs/fsrs.dart' as fsrs;

enum CardPhase { fresh, learning, review }

/// Interval label mirrors the scheduler: distance from last review to due.
({CardPhase phase, String label}) cardStatus(Flashcard card) {
  final last = card.scheduling.lastReview;
  if (last == null) return (phase: CardPhase.fresh, label: 'NEW');
  final days = card.due.difference(last).inDays;
  final phase = card.scheduling.state == fsrs.State.review
      ? CardPhase.review
      : CardPhase.learning;
  return (phase: phase, label: days == 1 ? '1 DAY' : '$days DAYS');
}

String dueLabel(Flashcard card, DateTime now) {
  final diff = card.due.difference(now);
  if (diff.isNegative || diff.inDays == 0) return 'Due today';
  if (diff.inDays == 1) return 'Due tomorrow';
  return 'Due in ${diff.inDays} days';
}
