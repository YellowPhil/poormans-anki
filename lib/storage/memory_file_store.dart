import 'file_store.dart';

class MemoryFileStore implements FileStore {
  final Map<String, String> files = {};

  @override
  Future<List<String>> list(String dir) async => [
    for (final path in files.keys)
      if (path.startsWith('$dir/') &&
          !path.substring(dir.length + 1).contains('/'))
        path,
  ];

  @override
  Future<String?> read(String path) async => files[path];

  @override
  Future<void> write(String path, String contents) async =>
      files[path] = contents;

  @override
  Future<void> append(String path, String line) async =>
      files[path] = '${files[path] ?? ''}$line\n';

  @override
  Future<void> delete(String path) async => files.remove(path);
}
