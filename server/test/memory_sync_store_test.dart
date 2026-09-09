import 'package:anki_server/memory_sync_store.dart';

import 'store_contract.dart';

void main() => syncStoreContract(() async => MemorySyncStore());
