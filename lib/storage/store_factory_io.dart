import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'file_store.dart';
import 'local_file_store.dart';

Future<FileStore> createFileStore() async {
  final support = await getApplicationSupportDirectory();
  final dir = await Directory('${support.path}/poormans_anki')
      .create(recursive: true);
  return LocalFileStore(dir);
}

String describeFileStore(FileStore store) =>
    'data directory: ${(store as LocalFileStore).root.path}';
