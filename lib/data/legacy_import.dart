import 'dart:convert';

import 'package:anki_core/anki_core.dart';

import '../storage/file_store.dart';

/// Reads the pre-sync-v2 layout (`decks/*.json`, `reviews.jsonl`) once. The
/// stored FSRS state is discarded and re-derived from the review log; review
/// ids follow [ReviewEntry.legacyId], matching the server's v1 migration.
Future<Collection?> importLegacy(
  FileStore files,
  CardScheduler scheduler,
) async {
  final decks = <Map<String, dynamic>>[];
  final cards = <String, Map<String, dynamic>>{};
  for (final path in await files.list('decks')) {
    if (!path.endsWith('.json')) continue;
    final raw = await files.read(path);
    if (raw == null) continue;
    final deck = jsonDecode(raw) as Map<String, dynamic>;
    final deckId = deck['id'] as String;
    decks.add({
      'id': deckId,
      'name': deck['name'],
      'createdAt': deck['createdAt'],
      'updatedAt': deck['updatedAt'],
    });
    for (final c
        in (deck['cards'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      cards[c['id'] as String] = {
        'id': c['id'],
        'deckId': deckId,
        'front': c['front'],
        'back': c['back'],
        'createdAt': c['createdAt'],
        'updatedAt': c['updatedAt'],
      };
    }
    final removed = (deck['removedCards'] as Map<String, dynamic>?) ?? const {};
    for (final MapEntry(:key, :value) in removed.entries) {
      cards.putIfAbsent(
        key,
        () => {
          'id': key,
          'deckId': deckId,
          'front': '',
          'back': '',
          'createdAt': value,
          'updatedAt': value,
          'removed': true,
        },
      );
    }
  }
  final reviews = <String, Map<String, dynamic>>{};
  final log = await files.read('reviews.jsonl');
  for (final line in const LineSplitter().convert(log ?? '')) {
    if (line.trim().isEmpty) continue;
    final entry = ReviewEntry.fromJson(
      jsonDecode(line) as Map<String, dynamic>,
    );
    reviews[entry.id] = entry.toJson();
  }
  if (decks.isEmpty && reviews.isEmpty) return null;
  return Collection.fromJson({
    'decks': decks,
    'cards': cards.values.toList(),
    'reviews': reviews.values.toList(),
  }, scheduler: scheduler);
}
