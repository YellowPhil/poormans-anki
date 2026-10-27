import 'dart:math';

import 'package:anki_core/anki_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poormans_anki/data/seed_data.dart';
import 'package:poormans_anki/sync/sync_service.dart';

import 'devices.dart';

/// Random interleavings of edits (including edits landing mid-sync), offline
/// periods, restarts and server compaction across three devices of one user; after a final settle every
/// device must render exactly the server's collection, and that collection
/// must hold every intent recorded in [_Intents].
void main() {
  for (var seed = 1; seed <= 16; seed++) {
    test('seed $seed converges', () => _run(seed));
  }
}

Future<void> _run(int seed) async {
  final rng = Random(seed);
  final intents = _Intents();
  final world = World();
  final server = MemorySyncServer();
  final servers = {'http://a': server};
  final devices = [
    for (final skew in const [0, -90, 45])
      Device(world, servers, skew: Duration(minutes: skew)),
  ];
  try {
    for (final (i, d) in devices.indexed) {
      await d.boot(syncUrl: i == 2 ? null : 'http://a');
    }
    await devices[2].setSync('http://a');

    for (var step = 0; step < 80; step++) {
      world.tick(Duration(minutes: rng.nextInt(600)));
      final d = devices[rng.nextInt(devices.length)];
      final roll = rng.nextInt(100);
      if (roll < 62) {
        await _edit(d, rng, intents, '$seed.$step');
      } else if (roll < 80) {
        if (rng.nextBool()) {
          d.client().beforeReply = () =>
              _edit(d, rng, intents, 'mid $seed.$step');
        }
        await d.sync();
      } else if (roll < 88) {
        d.offline = !d.client().offline;
      } else if (roll < 95) {
        await d.restart();
      } else {
        final head = (await server.collection('me@x.io')).seq;
        await server.compact('me@x.io', rng.nextInt(head + 1));
      }
    }

    for (final d in devices) {
      d.offline = false;
    }
    await settle(devices);
    final expected = await serverFingerprint(server);
    intents.check((await server.collection('me@x.io')).collection);
    for (final (i, d) in devices.indexed) {
      expect(d.status.phase, SyncPhase.idle, reason: 'device $i');
      expect((await d.store).pendingCount, 0, reason: 'device $i');
      expect(await deviceFingerprint(d), expected, reason: 'device $i');
    }

    final fresh = Device(world, servers);
    devices.add(fresh);
    await fresh.boot(syncUrl: 'http://a');
    await settle([fresh]);
    expect(await deviceFingerprint(fresh), expected, reason: 'new device');
  } finally {
    for (final d in devices) {
      d.dispose();
    }
  }
}

Future<void> _edit(Device d, Random rng, _Intents intents, String tag) async {
  final cards = d.cards.toList();
  final roll = rng.nextInt(62);
  if (roll < 8 || d.decks.isEmpty) {
    intents.decks.add((await d.notifier.createDeck('deck $tag')).name);
  } else if (roll < 22 || cards.isEmpty) {
    final deck = d.decks[rng.nextInt(d.decks.length)];
    intents.cards.add((await d.notifier.addCard(deck.id, 'q $tag', 'a')).id);
  } else if (roll < 32) {
    final card = cards[rng.nextInt(cards.length)];
    await d.notifier.updateCard(card, 'e $tag', card.back);
  } else if (roll < 37) {
    final card = cards[rng.nextInt(cards.length)];
    intents.removed.add(card.id);
    await d.notifier.deleteCard(card);
  } else {
    final card = cards[rng.nextInt(cards.length)];
    intents.reviews.update(card.id, (n) => n + 1, ifAbsent: () => 1);
    await d.notifier.rateCard(
      card,
      Rating.values[rng.nextInt(Rating.values.length)],
    );
  }
}

/// Lost-write oracle: convergence alone passes when a write vanishes from
/// every replica.
class _Intents {
  final decks = <String>{'Capitals', 'Spanish basics'};
  final cards = <String>{
    for (final op in seedOps(DateTime.utc(2026), () => ''))
      if (op is CardAdded) op.cardId,
  };
  final removed = <String>{};
  final reviews = <String, int>{};

  void check(Collection server) {
    expect(server.decks.map((d) => d.name).toSet(), decks);
    final live = {for (final d in server.decks) ...d.cards.map((c) => c.id)};
    expect(live, cards.difference(removed));
    for (final id in live) {
      expect(server.reviewsOf(id), hasLength(reviews[id] ?? 0), reason: id);
    }
  }
}
