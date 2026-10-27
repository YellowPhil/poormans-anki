// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:math' as math;

import 'package:fsrs/fsrs.dart' as fsrs;

import '../domain/review_entry.dart';

/// Scheduling is a pure function of a card's reviews, so FSRS fuzz is seeded
/// from the review id instead of an unseeded `Random()`: every replica that
/// folds the same reviews derives the same due dates.
class CardScheduler {
  CardScheduler({this.fuzz = true});

  final bool fuzz;

  fsrs.Card initial(DateTime createdAt) =>
      fsrs.Card(cardId: createdAt.millisecondsSinceEpoch, due: createdAt);

  fsrs.Card review(fsrs.Card card, ReviewEntry entry) =>
      fsrs.Scheduler.customRandom(
            SeededRandom(fnv1a(entry.id)),
            enableFuzzing: fuzz,
          )
          .reviewCard(
            card,
            fsrs.Rating.fromValue(entry.rating.value),
            reviewDateTime: entry.reviewedAt.toUtc(),
          )
          .card;

  fsrs.Card fold(DateTime createdAt, Iterable<ReviewEntry> ordered) =>
      ordered.fold(initial(createdAt), review);

  /// 32-bit FNV-1a over UTF-16 code units; `String.hashCode` differs between
  /// the VM and the web.
  static int fnv1a(String input) {
    var hash = 0x811c9dc5;
    for (final unit in input.codeUnits) {
      hash = _mul32(hash ^ unit, 0x01000193);
    }
    return hash;
  }
}

/// Mulberry32 restricted to arithmetic that stays below 2^53, so the VM and
/// dart2js produce the same sequence; `math.Random(seed)` promises neither.
class SeededRandom implements math.Random {
  SeededRandom(int seed) : _state = seed & _mask;

  int _state;

  int _next() {
    _state = (_state + 0x6d2b79f5) & _mask;
    var t = _mul32(_state ^ (_state >>> 15), _state | 1);
    t = (t ^ ((t + _mul32(t ^ (t >>> 7), t | 61)) & _mask)) & _mask;
    return (t ^ (t >>> 14)) & _mask;
  }

  @override
  double nextDouble() => _next() / 4294967296;

  @override
  int nextInt(int max) => (nextDouble() * max).floor();

  @override
  bool nextBool() => _next() & 1 == 1;
}

const _mask = 0xffffffff;

int _mul32(int a, int b) =>
    (((a & 0xffff) * b) + ((((a >>> 16) * b) & 0xffff) * 65536)) & _mask;
