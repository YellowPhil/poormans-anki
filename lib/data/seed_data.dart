import 'package:uuid/uuid.dart';

import '../domain/deck.dart';
import '../domain/flashcard.dart';
import '../scheduler/review_scheduler.dart';

const _seed = <String, List<(String, String)>>{
  'Spanish basics': [
    ('hola', 'hello'),
    ('adiós', 'goodbye'),
    ('gracias', 'thank you'),
    ('por favor', 'please'),
    ('sí', 'yes'),
    ('no', 'no'),
    ('agua', 'water'),
    ('comida', 'food'),
    ('casa', 'house'),
    ('libro', 'book'),
  ],
  'Capitals': [
    ('France', 'Paris'),
    ('Japan', 'Tokyo'),
    ('Canada', 'Ottawa'),
    ('Australia', 'Canberra'),
    ('Brazil', 'Brasília'),
    ('Egypt', 'Cairo'),
    ('Kenya', 'Nairobi'),
    ('Norway', 'Oslo'),
    ('Turkey', 'Ankara'),
    ('Peru', 'Lima'),
  ],
};

List<Deck> seedDecks(DateTime now) {
  const uuid = Uuid();
  final scheduler = ReviewScheduler();
  return [
    for (final MapEntry(key: name, value: pairs) in _seed.entries)
      () {
        final deckId = uuid.v4();
        return Deck(
          id: deckId,
          name: name,
          createdAt: now,
          updatedAt: now,
          cards: [
            for (final (front, back) in pairs)
              Flashcard(
                id: uuid.v4(),
                deckId: deckId,
                front: front,
                back: back,
                createdAt: now,
                updatedAt: now,
                scheduling: scheduler.newScheduling(now),
              ),
          ],
        );
      }(),
  ];
}
