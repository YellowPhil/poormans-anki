import 'rating.dart';

class ReviewEntry {
  const ReviewEntry({
    required this.cardId,
    required this.deckId,
    required this.rating,
    required this.reviewedAt,
  });

  factory ReviewEntry.fromJson(Map<String, dynamic> json) => ReviewEntry(
    cardId: json['cardId'] as String,
    deckId: json['deckId'] as String,
    rating: Rating.fromValue(json['rating'] as int),
    reviewedAt: DateTime.parse(json['reviewedAt'] as String).toUtc(),
  );

  final String cardId;
  final String deckId;
  final Rating rating;
  final DateTime reviewedAt;

  /// Identity used for de-duplication across replicas.
  String get key => '$cardId@${reviewedAt.toUtc().toIso8601String()}';

  Map<String, dynamic> toJson() => {
    'cardId': cardId,
    'deckId': deckId,
    'rating': rating.value,
    'reviewedAt': reviewedAt.toUtc().toIso8601String(),
  };
}
