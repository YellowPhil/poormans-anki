import 'dart:convert';

import 'package:anki_core/anki_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  final ops = <Op>[
    deckCreated('d1'),
    DeckRenamed(id: 'r', issuedAt: at(1), deckId: 'd1', name: 'New'),
    DeckDeleted(id: 'x', issuedAt: at(2), deckId: 'd1'),
    cardAdded('c1', 'd1'),
    cardEdited('c1', 'edited'),
    cardRemoved('c1'),
    reviewed('c1', minutes: 5, rating: Rating.hard),
  ];

  for (final op in ops) {
    test('${op.type} survives a JSON round trip', () {
      final wire = jsonDecode(jsonEncode(op.toJson())) as Map<String, dynamic>;
      final back = Op.fromJson(wire);
      expect(back.runtimeType, op.runtimeType);
      expect(back.toJson(), op.toJson());
    });
  }

  test('unknown type is a FormatException', () {
    expect(
      () => Op.fromJson({'id': 'a', 'type': 'nope', 'issuedAt': '$t0'}),
      throwsFormatException,
    );
  });

  test('empty or oversized ids are rejected', () {
    final json = deckCreated('d1').toJson();
    expect(() => Op.fromJson({...json, 'id': ''}), throwsFormatException);
    expect(
      () => Op.fromJson({...json, 'deckId': 'x' * (Op.maxIdLength + 1)}),
      throwsFormatException,
    );
  });

  test('invalid rating is a FormatException', () {
    final json = reviewed('c1', minutes: 1).toJson();
    expect(() => Op.fromJson({...json, 'rating': 9}), throwsFormatException);
  });
}
