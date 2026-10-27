import 'package:anki_core/anki_core.dart';

final t0 = DateTime.utc(2026, 9, 1, 8);
DateTime at(int minutes) => t0.add(Duration(minutes: minutes));

var _n = 0;
String nextId() => 'op-${_n++}';

DeckCreated deckCreated(String deckId, {String? name, int t = 0, String? id}) =>
    DeckCreated(
      id: id ?? nextId(),
      issuedAt: at(t),
      deckId: deckId,
      name: name ?? 'Deck $deckId',
    );

CardAdded cardAdded(
  String cardId,
  String deckId, {
  String front = 'front',
  int t = 0,
  String? id,
}) => CardAdded(
  id: id ?? nextId(),
  issuedAt: at(t),
  cardId: cardId,
  deckId: deckId,
  front: front,
  back: 'back',
);

CardEdited cardEdited(String cardId, String front, {int t = 1, String? id}) =>
    CardEdited(
      id: id ?? nextId(),
      issuedAt: at(t),
      cardId: cardId,
      front: front,
      back: 'back',
    );

CardRemoved cardRemoved(String cardId, {int t = 2, String? id}) =>
    CardRemoved(id: id ?? nextId(), issuedAt: at(t), cardId: cardId);

CardReviewed reviewed(
  String cardId, {
  required int minutes,
  Rating rating = Rating.good,
  String deckId = 'd1',
  String? id,
}) => CardReviewed(
  id: id ?? nextId(),
  issuedAt: at(minutes),
  cardId: cardId,
  deckId: deckId,
  rating: rating,
  reviewedAt: at(minutes),
);

Collection reduce(Iterable<Op> ops, {CardScheduler? scheduler}) {
  final c = Collection(scheduler: scheduler ?? CardScheduler());
  for (final op in ops) {
    c.apply(op);
  }
  return c;
}

/// Rows plus derived scheduling, so equality covers what the UI renders.
Map<String, dynamic> fingerprint(Collection c) => {
  ...c.toJson(),
  'view': [
    for (final d in c.decks)
      {
        'id': d.id,
        'name': d.name,
        'cards': [
          for (final card in d.cards)
            {'id': card.id, 'front': card.front, ...card.scheduling.toMap()},
        ],
      },
  ],
};
