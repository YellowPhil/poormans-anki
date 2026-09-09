import 'file_store.dart';

abstract interface class KeyValueBackend {
  Iterable<String> keys();

  String? get(String key);

  void set(String key, String value);

  void remove(String key);
}

class InMemoryBackend implements KeyValueBackend {
  final Map<String, String> _map = {};

  @override
  Iterable<String> keys() => _map.keys.toList();

  @override
  String? get(String key) => _map[key];

  @override
  void set(String key, String value) => _map[key] = value;

  @override
  void remove(String key) => _map.remove(key);
}

/// Emulates a directory tree on a flat key space; [prefix] namespaces the app
/// inside a shared backend such as `localStorage`.
class KeyValueFileStore implements FileStore {
  KeyValueFileStore(this.backend, {this.prefix = 'poormans_anki/'});

  final KeyValueBackend backend;
  final String prefix;

  String _key(String path) => '$prefix$path';

  @override
  Future<List<String>> list(String dir) async {
    final head = _key('$dir/');
    return [
      for (final k in backend.keys())
        if (k.startsWith(head) && !k.substring(head.length).contains('/'))
          k.substring(prefix.length),
    ];
  }

  @override
  Future<String?> read(String path) async => backend.get(_key(path));

  @override
  Future<void> write(String path, String contents) async =>
      backend.set(_key(path), contents);

  @override
  Future<void> append(String path, String line) async {
    final existing = backend.get(_key(path)) ?? '';
    backend.set(_key(path), '$existing$line\n');
  }

  @override
  Future<void> delete(String path) async => backend.remove(_key(path));
}
