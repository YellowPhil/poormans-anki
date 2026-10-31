import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/navigation.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/key_cap.dart';
import '../../widgets/staggered_entry.dart';
import '../shell/app_shell.dart';
import '../shell/top_bar.dart';
import 'card_detail.dart';
import 'card_tile.dart';
import 'import_dialog.dart';
import 'new_card_dialog.dart';

class DeckView extends ConsumerStatefulWidget {
  const DeckView({super.key, required this.deckId});

  final String deckId;

  @override
  ConsumerState<DeckView> createState() => _DeckViewState();
}

class _DeckViewState extends ConsumerState<DeckView> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _gridFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    _gridFocus.dispose();
    super.dispose();
  }

  void _newCard() {
    if (MediaQuery.sizeOf(context).width < sidebarBreakpoint) {
      ref
          .read(destinationProvider.notifier)
          .go(AddDestination(deckId: widget.deckId));
      return;
    }
    showNewCardDialog(context, deckId: widget.deckId);
  }

  Future<void> _deleteDeck(String name, int cardCount) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete deck?'),
        content: Text(
          cardCount == 0
              ? '"$name" will be deleted.'
              : '"$name" and its $cardCount '
                    '${cardCount == 1 ? 'card' : 'cards'} will be deleted.',
          style: const TextStyle(color: AppColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-delete-deck'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    ref.read(destinationProvider.notifier).go(const DashboardDestination());
    await ref.read(decksProvider.notifier).deleteDeck(widget.deckId);
  }

  Future<void> _import() async {
    final count = await showImportDialog(context, deckId: widget.deckId);
    if (count == null || !mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(count == 1 ? 'Imported 1 card' : 'Imported $count cards'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final deck = ref
        .watch(decksProvider)
        .value
        ?.where((d) => d.id == widget.deckId)
        .firstOrNull;
    if (deck == null) return const Center(child: Text('Deck not found'));
    final compact = MediaQuery.sizeOf(context).width < sidebarBreakpoint;
    final due = ref.watch(dueCountByDeckProvider)[deck.id] ?? 0;
    final needle = _search.text.trim().toLowerCase();
    final cards = [
      for (final c in deck.cards)
        if (needle.isEmpty ||
            c.front.toLowerCase().contains(needle) ||
            c.back.toLowerCase().contains(needle))
          c,
    ];
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            _searchFocus.requestFocus,
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _searchFocus.requestFocus,
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): _newCard,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): _newCard,
      },
      child: Column(
        children: [
          TopBar(
            crumbs: [Crumb(icon: Icons.style_rounded, label: deck.name)],
            actions: [
              ToolbarButton(
                key: const Key('review-button'),
                onPressed: due == 0
                    ? null
                    : () => ref
                          .read(destinationProvider.notifier)
                          .go(InboxDestination(deckId: deck.id)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.inbox_rounded),
                    const SizedBox(width: 8),
                    const Text('Review'),
                    if (due > 0) ...[
                      const SizedBox(width: 10),
                      CountBadge(due),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              ToolbarButton(
                key: const Key('delete-deck-button'),
                onPressed: () => _deleteDeck(deck.name, deck.cards.length),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.delete_outline_rounded,
                      color: AppColors.danger,
                    ),
                    if (!compact) ...const [
                      SizedBox(width: 8),
                      Text('Delete', style: TextStyle(color: AppColors.danger)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          _Toolbar(
            controller: _search,
            focusNode: _searchFocus,
            onNewCard: _newCard,
            onImport: _import,
          ),
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.keyN): _newCard,
              },
              child: Focus(
                focusNode: _gridFocus,
                autofocus: true,
                child: GestureDetector(
                  onTap: _gridFocus.requestFocus,
                  behavior: HitTestBehavior.translucent,
                  child: GridView.builder(
                    padding: const EdgeInsets.all(24),
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: compact ? 600 : 320,
                      mainAxisExtent: 200,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: cards.length + 1,
                    itemBuilder: (_, i) {
                      if (i == 0) {
                        return StaggeredEntry(
                          key: const ValueKey('new-card-tile'),
                          index: 0,
                          child: _NewCardTile(onTap: _newCard),
                        );
                      }
                      final card = cards[i - 1];
                      return StaggeredEntry(
                        key: ValueKey(card.id),
                        index: i,
                        child: CardTile(
                          card: card,
                          onTap: () => showCardDetail(
                            context,
                            card: card,
                            deckName: deck.name,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.controller,
    required this.focusNode,
    required this.onNewCard,
    required this.onImport,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onNewCard;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) => Container(
    height: 52,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.border)),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final search = SizedBox(
          height: 34,
          child: TextField(
            key: const Key('deck-search'),
            controller: controller,
            focusNode: focusNode,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              prefixIcon: const Icon(Icons.search_rounded, size: 16),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 34,
                minHeight: 34,
              ),
              hintText: 'Search',
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      iconSize: 14,
                      onPressed: controller.clear,
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
        );
        return Row(
          children: [
            if (!compact) ...[
              const Icon(Icons.grid_view_rounded, size: 16),
              const SizedBox(width: 8),
              const Text(
                'Grid View',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              SizedBox(width: 220, child: search),
            ] else
              Expanded(child: search),
            const SizedBox(width: 10),
            ToolbarButton(
              key: const Key('import-button'),
              onPressed: onImport,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.file_upload_outlined),
                  if (!compact) ...const [SizedBox(width: 6), Text('Import')],
                ],
              ),
            ),
            const SizedBox(width: 10),
            ToolbarButton(
              key: const Key('new-card-button'),
              onPressed: onNewCard,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add_rounded),
                  const SizedBox(width: 6),
                  const Text('New Card'),
                  if (!compact) ...const [SizedBox(width: 10), KeyCap('N')],
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _NewCardTile extends StatelessWidget {
  const _NewCardTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PressableSurface(
    onTap: onTap,
    dashed: true,
    child: const Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add_rounded, size: 20, color: AppColors.textMuted),
          SizedBox(width: 10),
          Text(
            'New Card',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppColors.textMuted,
            ),
          ),
          SizedBox(width: 12),
          KeyCap('N'),
        ],
      ),
    ),
  );
}
