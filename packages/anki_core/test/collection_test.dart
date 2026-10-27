import 'dart:convert';
import 'dart:math';

import 'package:anki_core/anki_core.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('reducer semantics', () {
    test('deck and card creation project into decks', () {
      final c = reduce([
        deckCreated('d1', name: 'Spanish'),
        cardAdded('c1', 'd1'),
      ]);
      expect(c.decks.single.name, 'Spanish');
      expect(c.decks.single.cards.single.front, 'front');
      expect(c.decks.single.cards.single.scheduling.state, fsrs.State.learning);
    });

    test('creating an existing deck or card is a no-op', () {
      final c = reduce([
        deckCreated('d1', name: 'first'),
        cardAdded('c1', 'd1', front: 'first'),
      ]);
      expect(c.apply(deckCreated('d1', name: 'second')), isFalse);
      expect(c.apply(cardAdded('c1', 'd1', front: 'second')), isFalse);
      expect(c.decks.single.name, 'first');
      expect(c.decks.single.cards.single.front, 'first');
    });

    test('card added to a missing or deleted deck is dropped', () {
      final c = reduce([
        deckCreated('d1'),
        DeckDeleted(id: 'x', issuedAt: at(1), deckId: 'd1'),
        cardAdded('c1', 'd1'),
        cardAdded('c2', 'missing'),
      ]);
      expect(c.cardRow('c1'), isNull);
      expect(c.cardRow('c2'), isNull);
    });

    test('rename changes the name; later rename in sequence wins', () {
      final c = reduce([
        deckCreated('d1'),
        DeckRenamed(id: 'a', issuedAt: at(5), deckId: 'd1', name: 'A'),
        DeckRenamed(id: 'b', issuedAt: at(1), deckId: 'd1', name: 'B'),
      ]);
      expect(c.decks.single.name, 'B');
    });

    test('deck deletion is terminal and cascades to its cards', () {
      final c = reduce([
        deckCreated('d1'),
        cardAdded('c1', 'd1'),
        DeckDeleted(id: 'x', issuedAt: at(1), deckId: 'd1'),
        deckCreated('d1', name: 'again'),
        DeckRenamed(id: 'r', issuedAt: at(3), deckId: 'd1', name: 'again'),
      ]);
      expect(c.decks, isEmpty);
      expect(c.cardRow('c1')!.removed, isTrue);
      expect(c.isPristine, isFalse);
    });

    test('edit applies in sequence order regardless of issuedAt', () {
      final c = reduce([
        deckCreated('d1'),
        cardAdded('c1', 'd1'),
        cardEdited('c1', 'late clock', t: 50),
        cardEdited('c1', 'early clock', t: 5),
      ]);
      expect(c.card('c1')!.front, 'early clock');
    });

    test('removal is terminal: later edits and re-adds are dropped', () {
      final c = reduce([
        deckCreated('d1'),
        cardAdded('c1', 'd1'),
        cardRemoved('c1'),
        cardEdited('c1', 'ghost', t: 9),
        cardAdded('c1', 'd1', front: 'ghost'),
      ]);
      expect(c.decks.single.cards, isEmpty);
      expect(c.cardRow('c1')!.front, 'front');
    });

    test('removing an unknown card leaves a tombstone that blocks the add', () {
      final c = reduce([
        deckCreated('d1'),
        cardRemoved('c1'),
        cardAdded('c1', 'd1'),
      ]);
      expect(c.decks.single.cards, isEmpty);
    });

    test('review of a removed card is kept for statistics', () {
      final c = reduce([
        deckCreated('d1'),
        cardAdded('c1', 'd1'),
        cardRemoved('c1'),
        reviewed('c1', minutes: 10),
      ]);
      expect(c.reviews, hasLength(1));
      expect(c.decks.single.cards, isEmpty);
    });

    test('reviews before the card arrives are folded when it does', () {
      final review = reviewed('c1', minutes: 10, rating: Rating.easy);
      final early = reduce([deckCreated('d1'), review, cardAdded('c1', 'd1')]);
      final late = reduce([deckCreated('d1'), cardAdded('c1', 'd1'), review]);
      expect(fingerprint(early), fingerprint(late));
      expect(late.card('c1')!.scheduling.state, fsrs.State.review);
    });

    test('rating a card moves its due date and updatedAt', () {
      final c = reduce([
        deckCreated('d1'),
        cardAdded('c1', 'd1'),
        reviewed('c1', minutes: 30, rating: Rating.easy),
      ]);
      final card = c.card('c1')!;
      expect(card.due.isAfter(at(30)), isTrue);
      expect(card.updatedAt, at(30));
    });
  });

  group('laws', () {
    final ops = <Op>[
      deckCreated('d1'),
      deckCreated('d2'),
      DeckRenamed(id: 'r', issuedAt: at(3), deckId: 'd1', name: 'renamed'),
      cardAdded('c1', 'd1'),
      cardAdded('c2', 'd1'),
      cardAdded('c3', 'd2'),
      cardEdited('c1', 'edited'),
      reviewed('c1', minutes: 10),
      reviewed('c1', minutes: 2000, rating: Rating.easy),
      reviewed('c2', minutes: 20, rating: Rating.again),
      cardRemoved('c2'),
      DeckDeleted(id: 'dd', issuedAt: at(9), deckId: 'd2'),
    ];

    test('every op is idempotent', () {
      for (var i = 0; i < ops.length; i++) {
        final once = reduce(ops);
        final twice = reduce([...ops.take(i + 1), ops[i], ...ops.skip(i + 1)]);
        expect(fingerprint(twice), fingerprint(once), reason: ops[i].type);
      }
    });

    test('replaying the whole log again changes nothing', () {
      expect(fingerprint(reduce([...ops, ...ops])), fingerprint(reduce(ops)));
    });

    test('concurrent reviews converge in either arrival order', () {
      final a = reviewed('c1', minutes: 100, rating: Rating.hard, id: 'ra');
      final b = reviewed('c1', minutes: 60, rating: Rating.easy, id: 'rb');
      final base = [deckCreated('d1'), cardAdded('c1', 'd1')];
      final ab = reduce([...base, a, b]);
      final ba = reduce([...base, b, a]);
      expect(fingerprint(ab), fingerprint(ba));
      expect(ab.reviewsOf('c1').map((r) => r.id), ['rb', 'ra']);
    });

    test('JSON round trip preserves rows and derived scheduling', () {
      final c = reduce(ops);
      final wire = jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>;
      final back = Collection.fromJson(wire, scheduler: CardScheduler());
      expect(fingerprint(back), fingerprint(c));
    });

    test('export rebuilds the identical state from empty', () {
      var n = 0;
      final c = reduce(ops);
      final rebuilt = reduce(c.export(() => 'x${n++}'));
      expect(fingerprint(rebuilt), fingerprint(c));
    });

    test('export keeps review ids so a server holding them de-duplicates', () {
      final exported = reduce(ops).export(() => 'x').whereType<CardReviewed>();
      expect(
        exported.map((o) => o.id).toSet(),
        ops.whereType<CardReviewed>().map((o) => o.id).toSet(),
      );
    });

    test('rescheduled derives the same scheduling as a scheduled fold', () {
      final serverRows = Collection();
      for (final op in ops) {
        serverRows.apply(op);
      }
      expect(
        fingerprint(serverRows.rescheduled(CardScheduler())),
        fingerprint(reduce(ops)),
      );
    });

    test('copy is independent of the original', () {
      final c = reduce(ops.take(4));
      final copy = c.copy()..apply(cardAdded('c9', 'd1'));
      expect(c.cardRow('c9'), isNull);
      expect(copy.cardRow('c9'), isNotNull);
    });

    test('re-delivering a shuffled log never loses or duplicates reviews', () {
      final random = Random(7);
      for (var round = 0; round < 50; round++) {
        final shuffled = [...ops]..shuffle(random);
        final x = reduce(shuffled);
        final y = reduce([...shuffled, ...shuffled.reversed]);
        expect(fingerprint(y)['reviews'], fingerprint(x)['reviews']);
      }
    });

    test('server collection without a scheduler keeps the same rows', () {
      final server = Collection();
      for (final op in ops) {
        server.apply(op);
      }
      expect(server.toJson(), reduce(ops).toJson());
    });
  });
}
