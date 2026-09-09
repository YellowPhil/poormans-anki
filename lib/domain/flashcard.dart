import 'package:fsrs/fsrs.dart' as fsrs;

/// The `fsrs` JSON object is `fsrs.Card.toMap()` verbatim; its keys belong to
/// the package and `fsrs.Card.cardId` is not this card's identity.
class Flashcard {
  const Flashcard({
    required this.id,
    required this.deckId,
    required this.front,
    required this.back,
    required this.createdAt,
    required this.updatedAt,
    required this.scheduling,
  });

  factory Flashcard.fromJson(Map<String, dynamic> json) => Flashcard(
    id: json['id'] as String,
    deckId: json['deckId'] as String,
    front: json['front'] as String,
    back: json['back'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
    updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
    scheduling: fsrs.Card.fromMap(json['fsrs'] as Map<String, dynamic>),
  );

  final String id;
  final String deckId;
  final String front;
  final String back;
  final DateTime createdAt;
  final DateTime updatedAt;
  final fsrs.Card scheduling;

  DateTime get due => scheduling.due;

  Map<String, dynamic> toJson() => {
    'id': id,
    'deckId': deckId,
    'front': front,
    'back': back,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'fsrs': scheduling.toMap(),
  };

  Flashcard copyWith({
    String? front,
    String? back,
    DateTime? updatedAt,
    fsrs.Card? scheduling,
  }) => Flashcard(
    id: id,
    deckId: deckId,
    front: front ?? this.front,
    back: back ?? this.back,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    scheduling: scheduling ?? this.scheduling,
  );
}
