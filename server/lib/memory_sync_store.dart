import 'package:anki_core/anki_core.dart';

import 'sync_store.dart';

/// Development backend (`DATABASE_URL=memory`); state is lost on restart.
class MemorySyncStore implements SyncStore {
  final _server = MemorySyncServer();

  @override
  Future<SyncPull> sync(String user, SyncPush push) => _server.sync(user, push);

  @override
  Future<CollectionSnapshot> collection(String user) =>
      _server.collection(user);

  @override
  Future<void> compact(String user, int throughSeq) =>
      _server.compact(user, throughSeq);

  @override
  Future<bool> healthy() async => true;

  @override
  Future<void> close() async {}
}
