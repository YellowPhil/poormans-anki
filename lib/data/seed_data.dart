import 'package:anki_core/anki_core.dart';
import 'package:uuid/uuid.dart';

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

/// Entity ids are name-derived (UUIDv5), so devices that seed independently
/// create the same decks and cards and the reducer collapses the copies.
String seedId(String path) =>
    const Uuid().v5(Namespace.url.value, 'poormans-anki/seed/$path');

List<Op> seedOps(DateTime now, String Function() newId) => [
  for (final MapEntry(key: name, value: pairs) in _seed.entries) ...[
    DeckCreated(id: newId(), issuedAt: now, deckId: seedId(name), name: name),
    for (final (i, (front, back)) in pairs.indexed)
      CardAdded(
        id: newId(),
        issuedAt: now.add(Duration(microseconds: i)),
        cardId: seedId('$name/$front'),
        deckId: seedId(name),
        front: front,
        back: back,
      ),
  ],
];
