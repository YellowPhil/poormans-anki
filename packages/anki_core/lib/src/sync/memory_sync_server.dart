import 'collection.dart';
import 'protocol.dart';

class _UserLog {
  final ops = <SequencedOp>[];
  final opIds = <String>{};
  final state = Collection();
  int head = 0;
  int floor = 0;
}

/// Reference semantics of the v2 sync endpoint: op-id de-duplication, a dense
/// per-user sequence, paged pulls and compaction floors.
class MemorySyncServer {
  final _users = <String, _UserLog>{};

  Future<SyncPull> sync(String user, SyncPush push) async {
    if (push.ops.length > SyncPush.maxOps) {
      throw FormatException('at most ${SyncPush.maxOps} ops per push');
    }
    final log = _users.putIfAbsent(user, _UserLog.new);
    if (push.since < log.floor || push.since > log.head) {
      throw CursorExpired(log.floor);
    }
    for (final op in push.ops) {
      if (!log.opIds.add(op.id)) continue;
      log.head++;
      log.ops.add(SequencedOp(log.head, op));
      log.state.apply(op);
    }
    final page = [
      for (final s in log.ops)
        if (s.seq > push.since) s,
    ].take(SyncPull.pageSize).toList();
    return SyncPull(
      head: log.head,
      acked: [for (final op in push.ops) op.id],
      ops: page,
      more: page.isNotEmpty && page.last.seq < log.head,
    );
  }

  Future<CollectionSnapshot> collection(String user) async {
    final log = _users.putIfAbsent(user, _UserLog.new);
    return CollectionSnapshot(seq: log.head, collection: log.state.copy());
  }

  /// Drops ops up to [throughSeq]; clients behind it must re-snapshot.
  Future<void> compact(String user, int throughSeq) async {
    final log = _users.putIfAbsent(user, _UserLog.new);
    final floor = throughSeq.clamp(log.floor, log.head);
    log.ops.removeWhere((s) => s.seq <= floor);
    log.floor = floor;
  }
}
