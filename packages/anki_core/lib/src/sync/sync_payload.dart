import '../domain/deck.dart';
import '../domain/review_entry.dart';

class DeckTombstone {
  const DeckTombstone({required this.id, required this.deletedAt});

  factory DeckTombstone.fromJson(Map<String, dynamic> json) => DeckTombstone(
    id: json['id'] as String,
    deletedAt: DateTime.parse(json['deletedAt'] as String).toUtc(),
  );

  final String id;
  final DateTime deletedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'deletedAt': deletedAt.toUtc().toIso8601String(),
  };
}

/// Client → server. [since] is the cursor from the previous [SyncResponse];
/// null asks for everything.
class SyncRequest {
  const SyncRequest({
    this.since,
    this.decks = const [],
    this.deletedDecks = const [],
    this.reviews = const [],
  });

  factory SyncRequest.fromJson(Map<String, dynamic> json) => SyncRequest(
    since: switch (json['since']) {
      final String s => DateTime.parse(s).toUtc(),
      _ => null,
    },
    decks: _list(json['decks'], Deck.fromJson),
    deletedDecks: _list(json['deletedDecks'], DeckTombstone.fromJson),
    reviews: _list(json['reviews'], ReviewEntry.fromJson),
  );

  final DateTime? since;
  final List<Deck> decks;
  final List<DeckTombstone> deletedDecks;
  final List<ReviewEntry> reviews;

  Map<String, dynamic> toJson() => {
    if (since != null) 'since': since!.toUtc().toIso8601String(),
    'decks': [for (final d in decks) d.toJson()],
    'deletedDecks': [for (final t in deletedDecks) t.toJson()],
    'reviews': [for (final r in reviews) r.toJson()],
  };
}

/// Server → client. Everything that changed after the request's `since`,
/// including the client's own writes; [cursor] feeds the next request.
class SyncResponse {
  const SyncResponse({
    required this.cursor,
    this.decks = const [],
    this.deletedDecks = const [],
    this.reviews = const [],
  });

  factory SyncResponse.fromJson(Map<String, dynamic> json) => SyncResponse(
    cursor: DateTime.parse(json['cursor'] as String).toUtc(),
    decks: _list(json['decks'], Deck.fromJson),
    deletedDecks: _list(json['deletedDecks'], DeckTombstone.fromJson),
    reviews: _list(json['reviews'], ReviewEntry.fromJson),
  );

  final DateTime cursor;
  final List<Deck> decks;
  final List<DeckTombstone> deletedDecks;
  final List<ReviewEntry> reviews;

  Map<String, dynamic> toJson() => {
    'cursor': cursor.toUtc().toIso8601String(),
    'decks': [for (final d in decks) d.toJson()],
    'deletedDecks': [for (final t in deletedDecks) t.toJson()],
    'reviews': [for (final r in reviews) r.toJson()],
  };
}

List<T> _list<T>(Object? raw, T Function(Map<String, dynamic>) parse) => [
  for (final item in (raw as List<dynamic>?) ?? const [])
    parse(item as Map<String, dynamic>),
];
