import 'package:flutter_test/flutter_test.dart';
import 'package:poormans_anki/storage/key_value_file_store.dart';

void main() {
  late KeyValueFileStore store;

  setUp(() => store = KeyValueFileStore(InMemoryBackend()));

  test('list returns direct children only', () async {
    await store.write('decks/a.json', '{}');
    await store.write('decks/b.json', '{}');
    await store.write('decks/nested/c.json', '{}');
    await store.write('reviews/log.jsonl', '');
    expect(
      await store.list('decks'),
      unorderedEquals(['decks/a.json', 'decks/b.json']),
    );
    expect(await store.list('missing'), isEmpty);
  });

  test('read, write, append, delete round trip', () async {
    expect(await store.read('x.txt'), isNull);
    await store.write('x.txt', 'one');
    expect(await store.read('x.txt'), 'one');
    await store.append('log.jsonl', 'a');
    await store.append('log.jsonl', 'b');
    expect(await store.read('log.jsonl'), 'a\nb\n');
    await store.delete('x.txt');
    expect(await store.read('x.txt'), isNull);
  });

  test('prefix isolates keys from the rest of the backend', () async {
    final backend = InMemoryBackend()..set('other/decks/z.json', '{}');
    final scoped = KeyValueFileStore(backend, prefix: 'app/');
    await scoped.write('decks/a.json', '{}');
    expect(await scoped.list('decks'), ['decks/a.json']);
    expect(backend.get('app/decks/a.json'), '{}');
  });
}
