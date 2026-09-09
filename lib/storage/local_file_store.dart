import 'dart:io';

import 'file_store.dart';

class LocalFileStore implements FileStore {
  LocalFileStore(this.root);

  final Directory root;

  File _file(String path) => File('${root.path}/$path');

  @override
  Future<List<String>> list(String dir) async {
    final directory = Directory('${root.path}/$dir');
    if (!await directory.exists()) return [];
    return directory
        .list()
        .where((e) => e is File)
        .map((e) => '$dir/${e.uri.pathSegments.last}')
        .toList();
  }

  @override
  Future<String?> read(String path) async {
    final file = _file(path);
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  @override
  Future<void> write(String path, String contents) async {
    final target = _file(path);
    await target.parent.create(recursive: true);
    final tmp = File(
      '${target.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
    );
    await tmp.writeAsString(contents, flush: true);
    await tmp.rename(target.path);
  }

  @override
  Future<void> append(String path, String line) async {
    final file = _file(path);
    await file.parent.create(recursive: true);
    await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
  }

  @override
  Future<void> delete(String path) async {
    final file = _file(path);
    if (await file.exists()) await file.delete();
  }
}
