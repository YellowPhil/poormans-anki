import '../domain/deck.dart';
import '../domain/review_entry.dart';
import 'merge.dart';
import 'sync_payload.dart';

class _DeckRow {
  _DeckRow(this.deck, this.deletedAt, this.syncedAt);

  Deck? deck;
  DateTime? deletedAt;
  DateTime syncedAt;
}

class _UserData {
  final decks = <String, _DeckRow>{};
  final reviews = <String, (ReviewEntry, DateTime)>{};
}

/// Reference semantics of the sync endpoint: card-wise deck merge, deck
/// tombstones, review de-duplication, and a strictly increasing cursor.
class MemorySyncServer {
  MemorySyncServer({DateTime Function()? clock})
    : _clock = clock ?? (() => DateTime.now().toUtc());

  final DateTime Function() _clock;
  final _users = <String, _UserData>{};
  DateTime? _last;

  DateTime _tick() {
    var now = _clock();
    if (_last != null && !now.isAfter(_last!)) {
      now = _last!.add(const Duration(microseconds: 1));
    }
    return _last = now;
  }

  Future<SyncResponse> sync(String user, SyncRequest request) async {
    final data = _users.putIfAbsent(user, _UserData.new);
    final now = _tick();
    for (final incoming in request.decks) {
      final row = data.decks[incoming.id];
      if (row == null) {
        data.decks[incoming.id] = _DeckRow(incoming, null, now);
        continue;
      }
      final deletedAt = row.deletedAt;
      if (deletedAt != null && !incoming.updatedAt.isAfter(deletedAt)) continue;
      final merged = switch (row.deck) {
        null => incoming,
        final existing => mergeDecks(existing, incoming),
      };
      if (row.deck == null ||
          deletedAt != null ||
          !sameDeck(row.deck!, merged)) {
        row
          ..deck = merged
          ..deletedAt = null
          ..syncedAt = now;
      }
    }
    for (final tombstone in request.deletedDecks) {
      final row = data.decks[tombstone.id];
      if (row == null) {
        data.decks[tombstone.id] = _DeckRow(null, tombstone.deletedAt, now);
      } else if (row.deletedAt == null &&
          (row.deck == null ||
              tombstone.deletedAt.isAfter(row.deck!.updatedAt))) {
        row
          ..deletedAt = tombstone.deletedAt
          ..syncedAt = now;
      }
    }
    for (final entry in request.reviews) {
      data.reviews.putIfAbsent(entry.key, () => (entry, now));
    }
    final since = request.since;
    bool changed(DateTime syncedAt) => since == null || syncedAt.isAfter(since);
    return SyncResponse(
      cursor: now,
      decks: [
        for (final row in data.decks.values)
          if (row.deletedAt == null &&
              row.deck != null &&
              changed(row.syncedAt))
            row.deck!,
      ],
      deletedDecks: [
        for (final MapEntry(key: id, value: row) in data.decks.entries)
          if (row.deletedAt != null && changed(row.syncedAt))
            DeckTombstone(id: id, deletedAt: row.deletedAt!),
      ],
      reviews: [
        for (final (entry, syncedAt) in data.reviews.values)
          if (changed(syncedAt)) entry,
      ],
    );
  }
}
