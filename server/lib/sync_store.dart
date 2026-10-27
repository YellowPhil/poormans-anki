import 'package:anki_core/anki_core.dart';

/// Implementations serialize calls per user, so sequence numbers are dense
/// and a pull never misses an op committed concurrently.
abstract interface class SyncStore {
  /// Throws [CursorExpired] when `push.since` is outside `[floor, head]`.
  Future<SyncPull> sync(String user, SyncPush push);

  Future<CollectionSnapshot> collection(String user);

  /// Drops op bodies up to [throughSeq]; clients behind it must re-snapshot.
  Future<void> compact(String user, int throughSeq);

  Future<bool> healthy();

  Future<void> close();
}
