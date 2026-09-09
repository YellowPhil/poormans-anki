import 'dart:convert';

import 'package:anki_core/anki_core.dart';

import '../storage/file_store.dart';

class DeckRepository {
  DeckRepository(this._store);

  static const _decksDir = 'decks';
  static const _reviewsFile = 'reviews.jsonl';

  final FileStore _store;

  Future<List<Deck>> loadDecks() async {
    final paths = await _store.list(_decksDir);
    final decks = <Deck>[];
    for (final path in paths.where((p) => p.endsWith('.json'))) {
      final raw = await _store.read(path);
      if (raw == null) continue;
      decks.add(Deck.fromJson(jsonDecode(raw) as Map<String, dynamic>));
    }
    decks.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return decks;
  }

  Future<void> saveDeck(Deck deck) =>
      _store.write(_deckPath(deck.id), jsonEncode(deck.toJson()));

  Future<void> deleteDeck(String id) => _store.delete(_deckPath(id));

  Future<void> appendReview(ReviewEntry entry) =>
      _store.append(_reviewsFile, jsonEncode(entry.toJson()));

  Future<List<ReviewEntry>> loadReviews() async {
    final raw = await _store.read(_reviewsFile);
    if (raw == null) return const [];
    return [
      for (final line in raw.split('\n'))
        if (line.trim().isNotEmpty)
          ReviewEntry.fromJson(jsonDecode(line) as Map<String, dynamic>),
    ];
  }

  String _deckPath(String id) => '$_decksDir/$id.json';
}
