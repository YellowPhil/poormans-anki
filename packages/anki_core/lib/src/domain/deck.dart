import 'flashcard.dart';

/// [removedCards] are deletion tombstones (card id → deleted at) so a delete
/// survives a merge with a replica that still holds the card.
class Deck {
  const Deck({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.cards = const [],
    this.removedCards = const {},
  });

  factory Deck.fromJson(Map<String, dynamic> json) => Deck(
    id: json['id'] as String,
    name: json['name'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
    updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
    cards: [
      for (final c in json['cards'] as List<dynamic>)
        Flashcard.fromJson(c as Map<String, dynamic>),
    ],
    removedCards: {
      for (final MapEntry(:key, :value)
          in ((json['removedCards'] as Map<String, dynamic>?) ?? const {})
              .entries)
        key: DateTime.parse(value as String).toUtc(),
    },
  );

  static const schemaVersion = 1;

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<Flashcard> cards;
  final Map<String, DateTime> removedCards;

  Map<String, dynamic> toJson() => {
    'version': schemaVersion,
    'id': id,
    'name': name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'cards': [for (final c in cards) c.toJson()],
    if (removedCards.isNotEmpty)
      'removedCards': {
        for (final MapEntry(:key, :value) in removedCards.entries)
          key: value.toUtc().toIso8601String(),
      },
  };

  Deck copyWith({
    String? name,
    DateTime? updatedAt,
    List<Flashcard>? cards,
    Map<String, DateTime>? removedCards,
  }) => Deck(
    id: id,
    name: name ?? this.name,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    cards: cards ?? this.cards,
    removedCards: removedCards ?? this.removedCards,
  );
}
