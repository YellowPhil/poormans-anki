import 'package:fsrs/fsrs.dart' as fsrs;

import '../domain/deck.dart';
import '../domain/flashcard.dart';
import '../domain/review_entry.dart';
import 'card_scheduler.dart';
import 'op.dart';

class DeckRow {
  const DeckRow({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.deleted = false,
  });

  factory DeckRow.fromJson(Map<String, dynamic> json) => DeckRow(
    id: json['id'] as String,
    name: json['name'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
    updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
    deleted: json['deleted'] as bool? ?? false,
  );

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool deleted;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'deleted': deleted,
  };
}

class CardRow {
  const CardRow({
    required this.id,
    required this.deckId,
    required this.front,
    required this.back,
    required this.createdAt,
    required this.updatedAt,
    this.removed = false,
  });

  factory CardRow.fromJson(Map<String, dynamic> json) => CardRow(
    id: json['id'] as String,
    deckId: json['deckId'] as String,
    front: json['front'] as String,
    back: json['back'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
    updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
    removed: json['removed'] as bool? ?? false,
  );

  final String id;
  final String deckId;
  final String front;
  final String back;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool removed;

  CardRow copyWith({
    String? front,
    String? back,
    DateTime? updatedAt,
    bool? removed,
  }) => CardRow(
    id: id,
    deckId: deckId,
    front: front ?? this.front,
    back: back ?? this.back,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    removed: removed ?? this.removed,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'deckId': deckId,
    'front': front,
    'back': back,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'removed': removed,
  };
}

/// The reducer every replica runs. [apply] must stay idempotent per op:
/// resends, snapshot + outbox overlap and at-least-once delivery rely on it.
/// Deleted decks and removed cards are terminal tombstones.
///
/// Without a [scheduler] (the server) scheduling is not derived.
class Collection {
  Collection({this.scheduler});

  factory Collection.fromJson(
    Map<String, dynamic> json, {
    CardScheduler? scheduler,
  }) {
    final c = Collection(scheduler: scheduler);
    for (final raw in _rows(json['decks'])) {
      final row = DeckRow.fromJson(raw);
      c._decks[row.id] = row;
    }
    for (final raw in _rows(json['cards'])) {
      final row = CardRow.fromJson(raw);
      c._cards[row.id] = row;
    }
    for (final raw in _rows(json['reviews'])) {
      c._insertReview(ReviewEntry.fromJson(raw));
    }
    for (final row in c._cards.values) {
      if (!row.removed) c._reschedule(row);
    }
    return c;
  }

  final CardScheduler? scheduler;
  final _decks = <String, DeckRow>{};
  final _cards = <String, CardRow>{};
  final _reviews = <String, ReviewEntry>{};
  final _byCard = <String, List<ReviewEntry>>{};
  final _scheduling = <String, fsrs.Card>{};

  bool get isPristine => _decks.isEmpty;

  Iterable<DeckRow> get deckRows => _decks.values;

  Iterable<CardRow> get cardRows => _cards.values;

  DeckRow? deckRow(String id) => _decks[id];

  CardRow? cardRow(String id) => _cards[id];

  bool hasReview(String id) => _reviews.containsKey(id);

  Collection copy() {
    final c = Collection(scheduler: scheduler);
    c._decks.addAll(_decks);
    c._cards.addAll(_cards);
    c._reviews.addAll(_reviews);
    for (final MapEntry(:key, :value) in _byCard.entries) {
      c._byCard[key] = [...value];
    }
    c._scheduling.addAll(_scheduling);
    return c;
  }

  /// Same rows, scheduling re-derived with [scheduler].
  Collection rescheduled(CardScheduler? scheduler) {
    final c = Collection(scheduler: scheduler);
    c._decks.addAll(_decks);
    c._cards.addAll(_cards);
    c._reviews.addAll(_reviews);
    for (final MapEntry(:key, :value) in _byCard.entries) {
      c._byCard[key] = [...value];
    }
    for (final row in c._cards.values) {
      if (!row.removed) c._reschedule(row);
    }
    return c;
  }

  /// Returns whether the state changed.
  bool apply(Op op) => switch (op) {
    DeckCreated() => _createDeck(op),
    DeckRenamed() => _renameDeck(op),
    DeckDeleted() => _deleteDeck(op),
    CardAdded() => _addCard(op),
    CardEdited() => _editCard(op),
    CardRemoved() => _removeCard(op),
    CardReviewed() => _review(op),
  };

  bool _createDeck(DeckCreated op) {
    if (_decks.containsKey(op.deckId)) return false;
    _decks[op.deckId] = DeckRow(
      id: op.deckId,
      name: op.name,
      createdAt: op.issuedAt,
      updatedAt: op.issuedAt,
    );
    return true;
  }

  bool _renameDeck(DeckRenamed op) {
    final row = _decks[op.deckId];
    if (row == null || row.deleted) return false;
    if (row.name == op.name && row.updatedAt == op.issuedAt) return false;
    _decks[op.deckId] = DeckRow(
      id: row.id,
      name: op.name,
      createdAt: row.createdAt,
      updatedAt: op.issuedAt,
    );
    return true;
  }

  bool _deleteDeck(DeckDeleted op) {
    final row = _decks[op.deckId];
    if (row != null && row.deleted) return false;
    _decks[op.deckId] = DeckRow(
      id: op.deckId,
      name: row?.name ?? '',
      createdAt: row?.createdAt ?? op.issuedAt,
      updatedAt: op.issuedAt,
      deleted: true,
    );
    for (final card in [..._cards.values]) {
      if (card.deckId == op.deckId && !card.removed) {
        _cards[card.id] = card.copyWith(removed: true);
        _scheduling.remove(card.id);
      }
    }
    return true;
  }

  bool _addCard(CardAdded op) {
    if (_cards.containsKey(op.cardId)) return false;
    final deck = _decks[op.deckId];
    if (deck == null || deck.deleted) return false;
    final row = CardRow(
      id: op.cardId,
      deckId: op.deckId,
      front: op.front,
      back: op.back,
      createdAt: op.issuedAt,
      updatedAt: op.issuedAt,
    );
    _cards[row.id] = row;
    _reschedule(row);
    return true;
  }

  bool _editCard(CardEdited op) {
    final row = _cards[op.cardId];
    if (row == null || row.removed) return false;
    if (row.front == op.front &&
        row.back == op.back &&
        row.updatedAt == op.issuedAt) {
      return false;
    }
    _cards[row.id] = row.copyWith(
      front: op.front,
      back: op.back,
      updatedAt: op.issuedAt,
    );
    return true;
  }

  bool _removeCard(CardRemoved op) {
    final row = _cards[op.cardId];
    if (row != null && row.removed) return false;
    _cards[op.cardId] =
        row?.copyWith(removed: true, updatedAt: op.issuedAt) ??
        CardRow(
          id: op.cardId,
          deckId: '',
          front: '',
          back: '',
          createdAt: op.issuedAt,
          updatedAt: op.issuedAt,
          removed: true,
        );
    _scheduling.remove(op.cardId);
    return true;
  }

  bool _review(CardReviewed op) {
    if (_reviews.containsKey(op.id)) return false;
    final row = _cards[op.cardId];
    final entry = ReviewEntry(
      id: op.id,
      cardId: op.cardId,
      deckId: row == null || row.deckId.isEmpty ? op.deckId : row.deckId,
      rating: op.rating,
      reviewedAt: op.reviewedAt,
    );
    final last = _insertReview(entry);
    final scheduler = this.scheduler;
    if (row == null || row.removed || scheduler == null) return true;
    final current = _scheduling[row.id];
    _scheduling[row.id] = last && current != null
        ? scheduler.review(current, entry)
        : scheduler.fold(row.createdAt, _byCard[row.id]!);
    return true;
  }

  /// Returns whether [entry] landed at the end of its card's ordered reviews.
  bool _insertReview(ReviewEntry entry) {
    _reviews[entry.id] = entry;
    final list = _byCard.putIfAbsent(entry.cardId, () => []);
    var i = list.length;
    while (i > 0 && _compareReviews(list[i - 1], entry) > 0) {
      i--;
    }
    list.insert(i, entry);
    return i == list.length - 1;
  }

  void _reschedule(CardRow row) {
    final scheduler = this.scheduler;
    if (scheduler == null) return;
    _scheduling[row.id] = scheduler.fold(
      row.createdAt,
      _byCard[row.id] ?? const [],
    );
  }

  /// Live decks sorted by name, each with its live cards in creation order.
  List<Deck> get decks {
    final cardsByDeck = <String, List<Flashcard>>{};
    for (final row in _cards.values) {
      if (row.removed) continue;
      cardsByDeck.putIfAbsent(row.deckId, () => []).add(_flashcard(row));
    }
    final decks = [
      for (final row in _decks.values)
        if (!row.deleted)
          Deck(
            id: row.id,
            name: row.name,
            createdAt: row.createdAt,
            updatedAt: row.updatedAt,
            cards: (cardsByDeck[row.id] ?? [])..sort(_compareCards),
          ),
    ];
    decks.sort((a, b) {
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return byName != 0 ? byName : a.id.compareTo(b.id);
    });
    return decks;
  }

  Flashcard? card(String id) {
    final row = _cards[id];
    return row == null || row.removed ? null : _flashcard(row);
  }

  /// Ordered by review time, then id.
  List<ReviewEntry> get reviews => [..._reviews.values]..sort(_compareReviews);

  List<ReviewEntry> reviewsOf(String cardId) => [...?_byCard[cardId]];

  Flashcard _flashcard(CardRow row) {
    final lastReview = _byCard[row.id]?.lastOrNull?.reviewedAt;
    return Flashcard(
      id: row.id,
      deckId: row.deckId,
      front: row.front,
      back: row.back,
      createdAt: row.createdAt,
      updatedAt: lastReview != null && lastReview.isAfter(row.updatedAt)
          ? lastReview
          : row.updatedAt,
      scheduling:
          _scheduling[row.id] ??
          fsrs.Card(
            cardId: row.createdAt.millisecondsSinceEpoch,
            due: row.createdAt,
          ),
    );
  }

  /// Ops that rebuild this exact state from an empty collection. Review ops
  /// keep their ids so a server that already holds them de-duplicates.
  List<Op> export(String Function() newId) {
    final decks = [..._decks.values]
      ..sort((a, b) => _byCreation(a.createdAt, a.id, b.createdAt, b.id));
    final cards = [..._cards.values]
      ..sort((a, b) => _byCreation(a.createdAt, a.id, b.createdAt, b.id));
    return [
      for (final d in decks) ...[
        DeckCreated(
          id: newId(),
          issuedAt: d.createdAt,
          deckId: d.id,
          name: d.name,
        ),
        if (!d.deleted && d.updatedAt != d.createdAt)
          DeckRenamed(
            id: newId(),
            issuedAt: d.updatedAt,
            deckId: d.id,
            name: d.name,
          ),
      ],
      for (final c in cards)
        if (c.deckId.isNotEmpty) ...[
          CardAdded(
            id: newId(),
            issuedAt: c.createdAt,
            cardId: c.id,
            deckId: c.deckId,
            front: c.front,
            back: c.back,
          ),
          if (!c.removed && c.updatedAt != c.createdAt)
            CardEdited(
              id: newId(),
              issuedAt: c.updatedAt,
              cardId: c.id,
              front: c.front,
              back: c.back,
            ),
        ],
      for (final r in reviews)
        CardReviewed(
          id: r.id,
          issuedAt: r.reviewedAt,
          cardId: r.cardId,
          deckId: r.deckId,
          rating: r.rating,
          reviewedAt: r.reviewedAt,
        ),
      for (final c in cards)
        if (c.removed)
          CardRemoved(id: newId(), issuedAt: c.updatedAt, cardId: c.id),
      for (final d in decks)
        if (d.deleted)
          DeckDeleted(id: newId(), issuedAt: d.updatedAt, deckId: d.id),
    ];
  }

  /// Rows sorted by id so equal states serialize identically.
  Map<String, dynamic> toJson() => {
    'decks': [
      for (final r in [..._decks.values]..sort((a, b) => a.id.compareTo(b.id)))
        r.toJson(),
    ],
    'cards': [
      for (final r in [..._cards.values]..sort((a, b) => a.id.compareTo(b.id)))
        r.toJson(),
    ],
    'reviews': [
      for (final r in [
        ..._reviews.values,
      ]..sort((a, b) => a.id.compareTo(b.id)))
        r.toJson(),
    ],
  };

  static int _compareReviews(ReviewEntry a, ReviewEntry b) {
    final byTime = a.reviewedAt.compareTo(b.reviewedAt);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  }

  static int _compareCards(Flashcard a, Flashcard b) =>
      _byCreation(a.createdAt, a.id, b.createdAt, b.id);

  static int _byCreation(DateTime at, String a, DateTime bt, String b) {
    final byCreated = at.compareTo(bt);
    return byCreated != 0 ? byCreated : a.compareTo(b);
  }

  static Iterable<Map<String, dynamic>> _rows(Object? raw) =>
      ((raw as List<dynamic>?) ?? const []).cast<Map<String, dynamic>>();
}
