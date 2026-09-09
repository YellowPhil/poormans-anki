import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/navigation.dart';
import '../../state/providers.dart';
import '../../sync/sync_service.dart';
import '../../theme/app_theme.dart';
import '../add/new_deck_dialog.dart';
import '../sync/sync_settings_dialog.dart';
import 'top_bar.dart';

class Sidebar extends ConsumerWidget {
  const Sidebar({super.key, this.compact = false});

  /// Swaps the title for a search entry point (phones open search from here).
  final bool compact;

  void _go(BuildContext context, WidgetRef ref, Destination d) {
    ref.read(destinationProvider.notifier).go(d);
    final scaffold = Scaffold.maybeOf(context);
    if (scaffold?.isDrawerOpen ?? false) scaffold!.closeDrawer();
  }

  Future<void> _newDeck(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const NewDeckDialog(),
    );
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    final deck = await ref.read(decksProvider.notifier).createDeck(name.trim());
    if (context.mounted) _go(context, ref, DeckDestination(deck.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decks = ref.watch(decksProvider).value ?? const [];
    final dueByDeck = ref.watch(dueCountByDeckProvider);
    final totalDue = ref.watch(dueCardsProvider).length;
    final current = ref.watch(destinationProvider);
    return Container(
      color: AppColors.sidebar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 20, 12, 20),
        children: [
          if (compact)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
              child: _SearchPill(
                onTap: () => _go(context, ref, const SearchDestination()),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 20),
              child: Text(
                'Poormans Anki',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          NavItem(
            icon: Icons.insights_rounded,
            label: 'Dashboard',
            selected: current is DashboardDestination,
            onTap: () => _go(context, ref, const DashboardDestination()),
          ),
          NavItem(
            icon: Icons.inbox_rounded,
            label: 'Inbox',
            count: totalDue,
            selected: current is InboxDestination && current.deckId == null,
            onTap: () => _go(context, ref, const InboxDestination()),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 28, 12, 8),
            child: Text(
              'DECKS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                color: AppColors.textFaint,
              ),
            ),
          ),
          for (final deck in decks)
            NavItem(
              key: ValueKey('nav-deck-${deck.id}'),
              icon: Icons.style_rounded,
              label: deck.name,
              count: dueByDeck[deck.id] ?? 0,
              selected: switch (current) {
                DeckDestination(:final deckId) => deckId == deck.id,
                InboxDestination(:final deckId) => deckId == deck.id,
                _ => false,
              },
              onTap: () => _go(context, ref, DeckDestination(deck.id)),
            ),
          NavItem(
            icon: Icons.add_rounded,
            label: 'New Deck',
            muted: true,
            onTap: () => _newDeck(context, ref),
          ),
          const SizedBox(height: 20),
          const _SyncItem(),
        ],
      ),
    );
  }
}

class NavItem extends StatefulWidget {
  const NavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.count = 0,
    this.selected = false,
    this.muted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int count;
  final bool selected;
  final bool muted;

  @override
  State<NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.muted ? AppColors.textMuted : AppColors.text;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 34,
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: widget.selected
                ? AppColors.surfaceRaised
                : _hover
                ? AppColors.surface
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 16,
                color: widget.selected ? AppColors.text : AppColors.textMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: widget.selected
                        ? FontWeight.w600
                        : FontWeight.w500,
                    color: color,
                  ),
                ),
              ),
              if (widget.count > 0) CountBadge(widget.count),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchPill extends StatelessWidget {
  const _SearchPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    key: const Key('sidebar-search'),
    onTap: onTap,
    child: Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Row(
        children: [
          Icon(Icons.search_rounded, size: 18),
          SizedBox(width: 10),
          Text(
            'Search',
            style: TextStyle(fontSize: 15, color: AppColors.textMuted),
          ),
        ],
      ),
    ),
  );
}

class _SyncItem extends ConsumerWidget {
  const _SyncItem();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncServiceProvider);
    final (icon, label) = switch (status.phase) {
      SyncPhase.off => (Icons.cloud_off_outlined, 'Sync off'),
      SyncPhase.syncing => (Icons.sync_rounded, 'Syncing…'),
      SyncPhase.idle => (
        Icons.cloud_done_outlined,
        'Synced ${formatClock(status.lastSyncAt)}',
      ),
      SyncPhase.error => (Icons.cloud_off_outlined, 'Sync failed'),
    };
    return NavItem(
      key: const Key('sidebar-sync'),
      icon: icon,
      label: label,
      muted: true,
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => const SyncSettingsDialog(),
      ),
    );
  }
}
