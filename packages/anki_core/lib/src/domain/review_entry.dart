import 'rating.dart';

/// [id] is the `CardReviewed` op id; reviews imported from v1 sync, which had
/// no ids, use [legacyId] so every replica derives the same identity.
class ReviewEntry {
  const ReviewEntry({
    required this.id,
    required this.cardId,
    required this.deckId,
    required this.rating,
    required this.reviewedAt,
  });

  factory ReviewEntry.fromJson(Map<String, dynamic> json) {
    final cardId = json['cardId'] as String;
    final reviewedAt = DateTime.parse(json['reviewedAt'] as String).toUtc();
    return ReviewEntry(
      id: json['id'] as String? ?? legacyId(cardId, reviewedAt),
      cardId: cardId,
      deckId: json['deckId'] as String,
      rating: Rating.fromValue(json['rating'] as int),
      reviewedAt: reviewedAt,
    );
  }

  final String id;
  final String cardId;
  final String deckId;
  final Rating rating;
  final DateTime reviewedAt;

  static String legacyId(String cardId, DateTime reviewedAt) =>
      'v1:$cardId@${reviewedAt.toUtc().toIso8601String()}';

  Map<String, dynamic> toJson() => {
    'id': id,
    'cardId': cardId,
    'deckId': deckId,
    'rating': rating.value,
    'reviewedAt': reviewedAt.toUtc().toIso8601String(),
  };
}
