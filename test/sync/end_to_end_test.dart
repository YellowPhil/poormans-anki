import 'dart:io';

import 'package:anki_core/anki_core.dart';
import 'package:anki_server/api.dart';
import 'package:anki_server/config.dart';
import 'package:anki_server/memory_sync_store.dart';
import 'package:anki_server/postgres_sync_store.dart';
import 'package:anki_server/sync_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:poormans_anki/data/seed_data.dart';
import 'package:poormans_anki/sync/sync_client.dart';
import 'package:poormans_anki/sync/sync_service.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'devices.dart';

/// App devices talking to the real server handler over HTTP. The Postgres
/// group runs only with `TEST_DATABASE_URL` and wipes that database's public
/// schema, so it must not share a database with a concurrent server suite.
void main() {
  group('memory store', () {
    _suite(open: () async => MemorySyncStore(), durable: false);
  });

  final url = Platform.environment['TEST_DATABASE_URL'];
  group('postgres store', () {
    if (url == null) {
      test('skipped: TEST_DATABASE_URL not set', () {}, skip: true);
      return;
    }
    _suite(
      open: () => PostgresSyncStore.open(url),
      reset: () => _resetSchema(url),
      durable: true,
    );
  });
}

void _suite({
  required Future<SyncStore> Function() open,
  Future<void> Function()? reset,
  required bool durable,
}) {
  late SyncStore store;
  late HttpServer httpServer;
  late World world;
  late String serverUrl;
  final devices = <Device>[];

  setUp(() async {
    await reset?.call();
    store = await open();
    httpServer = await shelf_io.serve(
      (Request r) => buildHandler(store, Config.fromEnv(const {}))(r),
      InternetAddress.loopbackIPv4,
      0,
    );
    serverUrl = 'http://${httpServer.address.address}:${httpServer.port}';
    world = World();
  });

  tearDown(() async {
    for (final d in devices) {
      d.dispose();
    }
    devices.clear();
    await httpServer.close(force: true);
    await store.close();
  });

  Device device({String user = 'me@x.io', Duration skew = Duration.zero}) {
    final d = Device(
      world,
      const {},
      user: user,
      skew: skew,
      clientFactory: (settings) => HttpSyncClient(
        http.Client(),
        settings.serverUrl!,
        email: settings.email,
      ),
    );
    devices.add(d);
    return d;
  }

  Future<Map<String, dynamic>> onServer([String user = 'me@x.io']) async =>
      fingerprint(
        (await store.collection(user)).collection.rescheduled(CardScheduler()),
      );

  Future<void> expectConverged(
    List<Device> ds, [
    String user = 'me@x.io',
  ]) async {
    final expected = await onServer(user);
    for (final d in ds) {
      expect(d.status.phase, SyncPhase.idle, reason: d.status.error);
      expect((await d.store).pendingCount, 0);
      expect(await deviceFingerprint(d), expected);
    }
  }

  test('local collection with history uploads; a new device gets it', () async {
    final a = device();
    await a.boot();
    final cardId = seedId('Capitals/Japan');
    for (final rating in [Rating.good, Rating.again, Rating.good]) {
      world.tick(const Duration(days: 1));
      await a.notifier.rateCard(a.cardById(cardId)!, rating);
    }
    final deck = await a.notifier.createDeck('Mine');
    await a.notifier.addCard(deck.id, 'q', 'a');
    await a.setSync(serverUrl);
    await settle([a]);

    final b = device(skew: const Duration(hours: 3));
    await b.boot(syncUrl: serverUrl);
    await settle([b]);
    expect(b.cards, hasLength(21));
    expect((await b.store).view.reviewsOf(cardId).map((r) => r.rating), [
      Rating.good,
      Rating.again,
      Rating.good,
    ]);
    expect(
      b.cardById(cardId)!.scheduling.toMap(),
      a.cardById(cardId)!.scheduling.toMap(),
    );
    await expectConverged([a, b]);
  });

  test('offline work on two devices merges over HTTP', () async {
    final a = device();
    await a.boot(syncUrl: serverUrl);
    await settle([a]);
    final b = device(skew: const Duration(minutes: -30));
    await b.boot(syncUrl: serverUrl);
    await settle([b]);
    final shared = seedId('Spanish basics/hola');
    final removed = seedId('Spanish basics/casa');
    final edited = seedId('Capitals/Peru');

    final live = store;
    store = _Unavailable();
    world.tick();
    await a.notifier.rateCard(a.cardById(shared)!, Rating.good);
    await a.notifier.updateCard(a.cardById(edited)!, 'Peru?', 'Lima');
    final deck = await a.notifier.createDeck('A only');
    await a.notifier.addCard(deck.id, 'x', 'y');
    await a.sync();
    expect(a.status.phase, SyncPhase.error);
    world.tick();
    await b.notifier.rateCard(b.cardById(shared)!, Rating.easy);
    await b.notifier.deleteCard(b.cardById(removed)!);
    await a.restart();
    await b.restart();
    store = live;

    await settle([a, b]);
    expect(a.cardById(removed), isNull);
    expect(b.cardById(edited)!.front, 'Peru?');
    expect(b.deck('A only').cards.single.front, 'x');
    expect(
      (await store.collection('me@x.io')).collection.reviewsOf(shared),
      hasLength(2),
    );
    await expectConverged([a, b]);
  });

  test('users are isolated', () async {
    final mine = device();
    await mine.boot(syncUrl: serverUrl);
    await settle([mine]);
    await mine.notifier.createDeck('Private');
    await settle([mine]);
    final theirs = device(user: 'you@x.io');
    await theirs.boot(syncUrl: serverUrl);
    await settle([theirs]);
    expect(theirs.decks.map((d) => d.name), ['Capitals', 'Spanish basics']);
    await expectConverged([mine]);
    await expectConverged([theirs], 'you@x.io');
  });

  if (durable) {
    test('server restart keeps every op and cursor', () async {
      final a = device();
      await a.boot(syncUrl: serverUrl);
      await settle([a]);
      final cardId = a.cards.first.id;
      await a.notifier.rateCard(a.cardById(cardId)!, Rating.good);
      await settle([a]);
      final before = await onServer();

      await store.close();
      store = await open();
      expect(await onServer(), before);

      world.tick();
      await a.notifier.rateCard(a.cardById(cardId)!, Rating.hard);
      await settle([a]);
      final b = device();
      await b.boot(syncUrl: serverUrl);
      await settle([b]);
      expect((await b.store).view.reviewsOf(cardId), hasLength(2));
      await expectConverged([a, b]);
    });
  }
}

class _Unavailable implements SyncStore {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<Never>.error(StateError('database unavailable'));
}

Future<void> _resetSchema(String url) async {
  final uri = Uri.parse(url);
  final conn = await Connection.open(
    Endpoint(
      host: uri.host,
      port: uri.port,
      database: uri.pathSegments.first,
      username: uri.userInfo.split(':').first,
      password: uri.userInfo.split(':').last,
    ),
    settings: const ConnectionSettings(sslMode: SslMode.disable),
  );
  await conn.execute('DROP SCHEMA public CASCADE');
  await conn.execute('CREATE SCHEMA public');
  await conn.close();
}
