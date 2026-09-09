import 'package:web/web.dart' as web;

import 'key_value_file_store.dart';

class LocalStorageBackend implements KeyValueBackend {
  web.Storage get _storage => web.window.localStorage;

  @override
  Iterable<String> keys() {
    final storage = _storage;
    return [for (var i = 0; i < storage.length; i++) ?storage.key(i)];
  }

  @override
  String? get(String key) => _storage.getItem(key);

  @override
  void set(String key, String value) => _storage.setItem(key, value);

  @override
  void remove(String key) => _storage.removeItem(key);
}
