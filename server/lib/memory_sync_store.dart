import 'package:anki_core/anki_core.dart';

import 'sync_store.dart';

/// Development backend (`DATABASE_URL=memory`); state is lost on restart.
class MemorySyncStore implements SyncStore {
  final _server = MemorySyncServer();

  @override
  Future<SyncResponse> sync(String user, SyncRequest request) =>
      _server.sync(user, request);

  @override
  Future<bool> healthy() async => true;

  @override
  Future<void> close() async {}
}
