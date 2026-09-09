import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:poormans_anki/storage/file_store.dart';
import 'package:poormans_anki/storage/local_file_store.dart';
import 'package:poormans_anki/storage/memory_file_store.dart';

void main() {
  group('LocalFileStore', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('pa_'));
    tearDown(() => root.deleteSync(recursive: true));

    fileStoreContract(() => LocalFileStore(root));

    test('write leaves no temp files behind', () async {
      final store = LocalFileStore(root);
      await store.write('decks/a.json', '{}');
      await store.write('decks/a.json', '{"x":1}');

      final names = root
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .toList();
      expect(names, ['a.json']);
    });
  });

  group('MemoryFileStore', () {
    fileStoreContract(MemoryFileStore.new);
  });
}

void fileStoreContract(FileStore Function() create) {
  test('read of a missing file is null', () async {
    expect(await create().read('nope.json'), isNull);
  });

  test('write then read returns contents', () async {
    final store = create();
    await store.write('decks/a.json', '{"a":1}');
    expect(await store.read('decks/a.json'), '{"a":1}');
  });

  test('write replaces existing contents', () async {
    final store = create();
    await store.write('decks/a.json', 'one');
    await store.write('decks/a.json', 'two');
    expect(await store.read('decks/a.json'), 'two');
  });

  test('list of a missing directory is empty', () async {
    expect(await create().list('decks'), isEmpty);
  });

  test('list returns direct children with directory prefix', () async {
    final store = create();
    await store.write('decks/a.json', '');
    await store.write('decks/b.json', '');
    await store.write('decks/sub/c.json', '');
    await store.write('other.txt', '');

    final listed = await store.list('decks');
    expect(listed..sort(), ['decks/a.json', 'decks/b.json']);
  });

  test('append adds newline-terminated lines', () async {
    final store = create();
    await store.append('reviews.jsonl', '{"r":1}');
    await store.append('reviews.jsonl', '{"r":2}');
    expect(await store.read('reviews.jsonl'), '{"r":1}\n{"r":2}\n');
  });

  test('delete removes the file and tolerates a missing one', () async {
    final store = create();
    await store.write('decks/a.json', 'x');
    await store.delete('decks/a.json');
    await store.delete('decks/a.json');
    expect(await store.read('decks/a.json'), isNull);
  });
}
