import '../domain/rating.dart';

/// A client intent. [id] is client-generated and globally unique; replicas
/// order ops by server sequence, never by [issuedAt], which only feeds
/// display timestamps.
sealed class Op {
  const Op({required this.id, required this.issuedAt});

  factory Op.fromJson(Map<String, dynamic> json) {
    final id = _id(json, 'id');
    final issuedAt = _date(json, 'issuedAt');
    return switch (json['type']) {
      'deckCreated' => DeckCreated(
        id: id,
        issuedAt: issuedAt,
        deckId: _id(json, 'deckId'),
        name: json['name'] as String,
      ),
      'deckRenamed' => DeckRenamed(
        id: id,
        issuedAt: issuedAt,
        deckId: _id(json, 'deckId'),
        name: json['name'] as String,
      ),
      'deckDeleted' => DeckDeleted(
        id: id,
        issuedAt: issuedAt,
        deckId: _id(json, 'deckId'),
      ),
      'cardAdded' => CardAdded(
        id: id,
        issuedAt: issuedAt,
        cardId: _id(json, 'cardId'),
        deckId: _id(json, 'deckId'),
        front: json['front'] as String,
        back: json['back'] as String,
      ),
      'cardEdited' => CardEdited(
        id: id,
        issuedAt: issuedAt,
        cardId: _id(json, 'cardId'),
        front: json['front'] as String,
        back: json['back'] as String,
      ),
      'cardRemoved' => CardRemoved(
        id: id,
        issuedAt: issuedAt,
        cardId: _id(json, 'cardId'),
      ),
      'cardReviewed' => CardReviewed(
        id: id,
        issuedAt: issuedAt,
        cardId: _id(json, 'cardId'),
        deckId: _id(json, 'deckId'),
        rating: Rating.fromValue(json['rating'] as int),
        reviewedAt: _date(json, 'reviewedAt'),
      ),
      final type => throw FormatException('unknown op type: $type'),
    };
  }

  static const maxIdLength = 200;

  final String id;
  final DateTime issuedAt;

  String get type;

  Map<String, dynamic> get payload;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'issuedAt': issuedAt.toUtc().toIso8601String(),
    ...payload,
  };

  static String _id(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.isEmpty || value.length > maxIdLength) {
      throw FormatException('invalid $key: $value');
    }
    return value;
  }

  static DateTime _date(Map<String, dynamic> json, String key) =>
      DateTime.parse(json[key] as String).toUtc();
}

class DeckCreated extends Op {
  const DeckCreated({
    required super.id,
    required super.issuedAt,
    required this.deckId,
    required this.name,
  });

  final String deckId;
  final String name;

  @override
  String get type => 'deckCreated';

  @override
  Map<String, dynamic> get payload => {'deckId': deckId, 'name': name};
}

class DeckRenamed extends Op {
  const DeckRenamed({
    required super.id,
    required super.issuedAt,
    required this.deckId,
    required this.name,
  });

  final String deckId;
  final String name;

  @override
  String get type => 'deckRenamed';

  @override
  Map<String, dynamic> get payload => {'deckId': deckId, 'name': name};
}

class DeckDeleted extends Op {
  const DeckDeleted({
    required super.id,
    required super.issuedAt,
    required this.deckId,
  });

  final String deckId;

  @override
  String get type => 'deckDeleted';

  @override
  Map<String, dynamic> get payload => {'deckId': deckId};
}

class CardAdded extends Op {
  const CardAdded({
    required super.id,
    required super.issuedAt,
    required this.cardId,
    required this.deckId,
    required this.front,
    required this.back,
  });

  final String cardId;
  final String deckId;
  final String front;
  final String back;

  @override
  String get type => 'cardAdded';

  @override
  Map<String, dynamic> get payload => {
    'cardId': cardId,
    'deckId': deckId,
    'front': front,
    'back': back,
  };
}

class CardEdited extends Op {
  const CardEdited({
    required super.id,
    required super.issuedAt,
    required this.cardId,
    required this.front,
    required this.back,
  });

  final String cardId;
  final String front;
  final String back;

  @override
  String get type => 'cardEdited';

  @override
  Map<String, dynamic> get payload => {
    'cardId': cardId,
    'front': front,
    'back': back,
  };
}

class CardRemoved extends Op {
  const CardRemoved({
    required super.id,
    required super.issuedAt,
    required this.cardId,
  });

  final String cardId;

  @override
  String get type => 'cardRemoved';

  @override
  Map<String, dynamic> get payload => {'cardId': cardId};
}

/// The op [id] doubles as the review's identity.
class CardReviewed extends Op {
  const CardReviewed({
    required super.id,
    required super.issuedAt,
    required this.cardId,
    required this.deckId,
    required this.rating,
    required this.reviewedAt,
  });

  final String cardId;
  final String deckId;
  final Rating rating;
  final DateTime reviewedAt;

  @override
  String get type => 'cardReviewed';

  @override
  Map<String, dynamic> get payload => {
    'cardId': cardId,
    'deckId': deckId,
    'rating': rating.value,
    'reviewedAt': reviewedAt.toUtc().toIso8601String(),
  };
}
