import 'package:anki_core/anki_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/collection_store.dart';
import '../data/seed_data.dart';
import '../sync/sync_service.dart';
import 'providers.dart';

/// Read-only projection of [CollectionStore.view]; mutations become ops.
class DecksNotifier extends AsyncNotifier<List<Deck>> {
  @override
  Future<List<Deck>> build() async {
    final store = await ref.watch(collectionStoreProvider.future);
    if (store.view.isPristine && store.attachedTo == null) {
      final sync = await ref.read(syncSettingsProvider.future);
      if (!sync.enabled) await store.dispatchAll(_seedOps());
    }
    final subscription = store.changes.listen(
      (_) => state = AsyncData(store.view.decks),
    );
    ref.onDispose(subscription.cancel);
    return store.view.decks;
  }

  /// Sync-enabled replicas seed only after the first pull came back empty;
  /// seed ids are deterministic, so racing devices still converge to one copy.
  Future<void> seedIfEmpty() async {
    final store = await _store();
    if (!store.view.isPristine) return;
    await store.dispatchAll(_seedOps());
    ref.read(syncServiceProvider.notifier).schedule();
  }

  Future<Deck> createDeck(String name) async {
    final deckId = _newId();
    final store = await _dispatch(
      DeckCreated(id: _newId(), issuedAt: _now(), deckId: deckId, name: name),
    );
    return store.view.decks.firstWhere((d) => d.id == deckId);
  }

  Future<Flashcard> addCard(String deckId, String front, String back) async {
    final cardId = _newId();
    final store = await _dispatch(
      CardAdded(
        id: _newId(),
        issuedAt: _now(),
        cardId: cardId,
        deckId: deckId,
        front: front,
        back: back,
      ),
    );
    return store.view.card(cardId)!;
  }

  Future<void> rateCard(Flashcard card, Rating rating) async {
    final now = _now();
    await _dispatch(
      CardReviewed(
        id: _newId(),
        issuedAt: now,
        cardId: card.id,
        deckId: card.deckId,
        rating: rating,
        reviewedAt: now,
      ),
    );
  }

  Future<void> updateCard(Flashcard card, String front, String back) =>
      _dispatch(
        CardEdited(
          id: _newId(),
          issuedAt: _now(),
          cardId: card.id,
          front: front,
          back: back,
        ),
      );

  Future<void> deleteCard(Flashcard card) =>
      _dispatch(CardRemoved(id: _newId(), issuedAt: _now(), cardId: card.id));

  Future<CollectionStore> _dispatch(Op op) async {
    final store = await _store();
    await store.dispatch(op);
    ref.read(syncServiceProvider.notifier).schedule();
    return store;
  }

  Future<CollectionStore> _store() => ref.read(collectionStoreProvider.future);

  List<Op> _seedOps() => seedOps(_now(), _newId);

  DateTime _now() => ref.read(clockProvider)();

  String _newId() => ref.read(newIdProvider)();
}
