import 'file_store.dart';
import 'key_value_file_store.dart';
import 'local_storage_backend.dart';

Future<FileStore> createFileStore() async =>
    KeyValueFileStore(LocalStorageBackend());

String describeFileStore(FileStore store) => 'data store: localStorage';
