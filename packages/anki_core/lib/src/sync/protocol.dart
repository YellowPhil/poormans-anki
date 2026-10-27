import 'card_scheduler.dart';
import 'collection.dart';
import 'op.dart';

/// Client → server. [since] is the highest sequence the client has applied.
class SyncPush {
  const SyncPush({required this.clientId, this.since = 0, this.ops = const []});

  factory SyncPush.fromJson(Map<String, dynamic> json) {
    final ops = (json['ops'] as List<dynamic>?) ?? const [];
    if (ops.length > maxOps) {
      throw FormatException('at most $maxOps ops per push, got ${ops.length}');
    }
    return SyncPush(
      clientId: json['clientId'] as String,
      since: json['since'] as int? ?? 0,
      ops: [for (final o in ops) Op.fromJson(o as Map<String, dynamic>)],
    );
  }

  static const maxOps = 500;

  final String clientId;
  final int since;
  final List<Op> ops;

  Map<String, dynamic> toJson() => {
    'clientId': clientId,
    'since': since,
    'ops': [for (final o in ops) o.toJson()],
  };
}

class SequencedOp {
  const SequencedOp(this.seq, this.op);

  factory SequencedOp.fromJson(Map<String, dynamic> json) => SequencedOp(
    json['seq'] as int,
    Op.fromJson(json['op'] as Map<String, dynamic>),
  );

  final int seq;
  final Op op;

  Map<String, dynamic> toJson() => {'seq': seq, 'op': op.toJson()};
}

/// Server → client. [acked] lists every pushed op id the server now holds,
/// including duplicates of ops it already had; [ops] are those after the
/// push's `since`, at most [pageSize], with [more] set when the page is full.
class SyncPull {
  const SyncPull({
    required this.head,
    this.acked = const [],
    this.ops = const [],
    this.more = false,
  });

  factory SyncPull.fromJson(Map<String, dynamic> json) => SyncPull(
    head: json['head'] as int,
    acked: [...((json['acked'] as List<dynamic>?) ?? const []).cast<String>()],
    ops: [
      for (final o in (json['ops'] as List<dynamic>?) ?? const [])
        SequencedOp.fromJson(o as Map<String, dynamic>),
    ],
    more: json['more'] as bool? ?? false,
  );

  static const pageSize = 2000;

  final int head;
  final List<String> acked;
  final List<SequencedOp> ops;
  final bool more;

  Map<String, dynamic> toJson() => {
    'head': head,
    'acked': acked,
    'ops': [for (final o in ops) o.toJson()],
    'more': more,
  };
}

class CollectionSnapshot {
  const CollectionSnapshot({required this.seq, required this.collection});

  factory CollectionSnapshot.fromJson(
    Map<String, dynamic> json, {
    CardScheduler? scheduler,
  }) => CollectionSnapshot(
    seq: json['seq'] as int,
    collection: Collection.fromJson(
      json['collection'] as Map<String, dynamic>,
      scheduler: scheduler,
    ),
  );

  final int seq;
  final Collection collection;

  Map<String, dynamic> toJson() => {
    'seq': seq,
    'collection': collection.toJson(),
  };
}

/// The client's `since` no longer identifies a point in the server log: it
/// predates compaction ([floor]) or is ahead of the server's head.
class CursorExpired implements Exception {
  const CursorExpired(this.floor);

  final int floor;

  @override
  String toString() => 'cursor expired (floor $floor)';
}
