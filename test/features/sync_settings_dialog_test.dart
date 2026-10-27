import 'dart:convert';

import 'package:anki_core/anki_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poormans_anki/app.dart';
import 'package:poormans_anki/state/providers.dart';
import 'package:poormans_anki/storage/memory_file_store.dart';
import 'package:poormans_anki/sync/sync_client.dart';
import 'package:poormans_anki/sync/sync_service.dart';

class _RecordingClient implements SyncClient {
  final server = MemorySyncServer();
  int calls = 0;

  @override
  Future<SyncPull> sync(SyncPush push) {
    calls++;
    return server.sync('me@x.io', push);
  }

  @override
  Future<CollectionSnapshot> collection() => server.collection('me@x.io');
}

void main() {
  testWidgets('sidebar sync item opens settings; saving enables sync', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemoryFileStore();
    final client = _RecordingClient();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fileStoreProvider.overrideWithValue(store),
          syncClientFactoryProvider.overrideWithValue((_) => client),
        ],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sync off'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sidebar-sync')));
    await tester.pumpAndSettle();
    expect(find.text('Sync is off.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('sync-url')),
      'http://localhost:8080',
    );
    await tester.enterText(find.byKey(const Key('sync-email')), 'me@x.io');
    await tester.tap(find.byKey(const Key('sync-save')));
    await tester.pumpAndSettle();

    final saved = jsonDecode(store.files['sync/settings.json']!);
    expect(saved, {'serverUrl': 'http://localhost:8080', 'email': 'me@x.io'});
    expect(client.calls, greaterThan(0));
    expect(find.textContaining('Synced'), findsOneWidget);
    final onServer = await client.server.collection('me@x.io');
    expect(onServer.collection.decks.map((d) => d.name), [
      'Capitals',
      'Spanish basics',
    ]);
  });
}
