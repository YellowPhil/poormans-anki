import 'package:anki_core/anki_core.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:test/test.dart';

import 'fixtures.dart';

ReviewEntry entry(String id, int days, Rating rating) => ReviewEntry(
  id: id,
  cardId: 'c1',
  deckId: 'd1',
  rating: rating,
  reviewedAt: t0.add(Duration(days: days)),
);

void main() {
  final history = [
    entry('a', 0, Rating.good),
    entry('b', 1, Rating.good),
    entry('c', 5, Rating.easy),
    entry('d', 30, Rating.good),
    entry('e', 90, Rating.hard),
  ];

  test('fuzzed fold is deterministic across scheduler instances', () {
    final one = CardScheduler().fold(t0, history);
    final two = CardScheduler().fold(t0, history);
    expect(one.toMap(), two.toMap());
    expect(one.state, fsrs.State.review);
  });

  test('fuzzed fold is pinned so the VM and dart2js must agree', () {
    final card = CardScheduler().fold(t0, history);
    expect(card.due, DateTime.utc(2027, 4, 11, 8));
    expect(card.stability, closeTo(135.32931650696366, 1e-9));
    expect(card.difficulty, closeTo(5.115708465882704, 1e-9));
  });

  test('fuzz depends on the review id', () {
    final dues = {
      for (var i = 0; i < 20; i++)
        CardScheduler().fold(t0, [
          ...history.take(4),
          entry('e$i', 90, Rating.good),
        ]).due,
    };
    expect(dues.length, greaterThan(1));
  });

  test('fuzz off matches the plain fsrs scheduler', () {
    final plain = fsrs.Scheduler(enableFuzzing: false);
    var card = fsrs.Card(cardId: t0.millisecondsSinceEpoch, due: t0);
    for (final r in history) {
      card = plain
          .reviewCard(
            card,
            fsrs.Rating.fromValue(r.rating.value),
            reviewDateTime: r.reviewedAt,
          )
          .card;
    }
    expect(CardScheduler(fuzz: false).fold(t0, history).toMap(), card.toMap());
  });

  test('fnv1a matches the reference vectors', () {
    expect(CardScheduler.fnv1a(''), 0x811c9dc5);
    expect(CardScheduler.fnv1a('a'), 0xe40c292c);
    expect(CardScheduler.fnv1a('foobar'), 0xbf9cf968);
  });

  test('SeededRandom matches mulberry32 as computed with Math.imul in JS', () {
    final r = SeededRandom(1);
    expect(
      [r.nextDouble(), r.nextDouble(), r.nextDouble()],
      [0.6270739405881613, 0.002735721180215478, 0.5274470399599522],
    );
    expect(SeededRandom(3735928559).nextDouble(), 0.9413696140982211);
  });
}
