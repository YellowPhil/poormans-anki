import 'flashcard.dart';

class Deck {
  const Deck({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.cards = const [],
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
  );

  static const schemaVersion = 1;

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<Flashcard> cards;

  Map<String, dynamic> toJson() => {
    'version': schemaVersion,
    'id': id,
    'name': name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'cards': [for (final c in cards) c.toJson()],
  };

  Deck copyWith({String? name, DateTime? updatedAt, List<Flashcard>? cards}) =>
      Deck(
        id: id,
        name: name ?? this.name,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        cards: cards ?? this.cards,
      );
}
