import 'package:anki_core/anki_core.dart';

/// One call = one atomic push+pull for [user]; implementations serialize
/// concurrent calls for the same user so the returned cursor is exact.
abstract interface class SyncStore {
  Future<SyncResponse> sync(String user, SyncRequest request);

  Future<bool> healthy();

  Future<void> close();
}
