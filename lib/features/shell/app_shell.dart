import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/deck.dart';
import '../../state/navigation.dart';
import '../../state/providers.dart';
import '../add/add_tab.dart';
import '../deck/deck_view.dart';
import '../inbox/inbox_tab.dart';
import '../inbox/mobile_review.dart';
import '../search/search_view.dart';
import '../statistics/statistics_tab.dart';
import 'mobile_tab_bar.dart';
import 'sidebar.dart';
import 'top_bar.dart';

const sidebarBreakpoint = 880.0;

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= sidebarBreakpoint;
    if (!wide) {
      return const NavigationShortcuts(
        child: Scaffold(
          drawer: Drawer(
            width: 300,
            child: SafeArea(bottom: false, child: Sidebar(compact: true)),
          ),
          body: SafeArea(bottom: false, child: _Pane(compact: true)),
          bottomNavigationBar: MobileTabBar(),
        ),
      );
    }
    return const NavigationShortcuts(
      child: Scaffold(
        body: Row(
          children: [
            SizedBox(width: 248, child: Sidebar()),
            VerticalDivider(width: 1, thickness: 1),
            Expanded(child: _Pane(compact: false)),
          ],
        ),
      ),
    );
  }
}

/// Cmd/Ctrl+1 Dashboard, +2 Inbox, +3.. decks in sidebar order.
/// Listens on [HardwareKeyboard] so it works regardless of focus; ignored
/// while a dialog covers the shell.
class NavigationShortcuts extends ConsumerStatefulWidget {
  const NavigationShortcuts({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<NavigationShortcuts> createState() =>
      _NavigationShortcutsState();
}

class _NavigationShortcutsState extends ConsumerState<NavigationShortcuts> {
  static const _digits = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final keyboard = HardwareKeyboard.instance;
    if (!keyboard.isMetaPressed && !keyboard.isControlPressed) return false;
    final index = _digits.indexOf(event.logicalKey);
    if (index < 0) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    final target = switch (index) {
      0 => const DashboardDestination(),
      1 => const InboxDestination(),
      _ => switch (ref.read(decksProvider).value?.elementAtOrNull(index - 2)) {
        null => null,
        final deck => DeckDestination(deck.id),
      },
    };
    if (target == null) return false;
    ref.read(destinationProvider.notifier).go(target);
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Pane extends ConsumerWidget {
  const _Pane({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decks = ref.watch(decksProvider);
    if (decks.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (decks.hasError) {
      return Center(child: Text('Failed to load decks: ${decks.error}'));
    }
    final destination = ref.watch(destinationProvider);
    final child = _viewFor(destination, decks.value ?? const []);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) =>
          Stack(fit: StackFit.expand, children: [...previous, ?current]),
      transitionBuilder: (child, t) => FadeTransition(
        opacity: t,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.01),
            end: Offset.zero,
          ).animate(t),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(destination), child: child),
    );
  }

  Widget _viewFor(Destination destination, List<Deck> all) {
    Deck? deckById(String? id) => all.where((d) => d.id == id).firstOrNull;
    return switch (destination) {
      DashboardDestination() => const Column(
        children: [
          TopBar(
            crumbs: [Crumb(icon: Icons.insights_rounded, label: 'Dashboard')],
          ),
          Expanded(child: StatisticsTab()),
        ],
      ),
      InboxDestination(:final deckId) when compact => MobileReview(
        deckId: deckId,
      ),
      InboxDestination(:final deckId) => Column(
        children: [
          TopBar(
            crumbs: [
              Crumb(
                icon: Icons.inbox_rounded,
                label: deckById(deckId)?.name ?? 'Inbox',
              ),
            ],
          ),
          Expanded(child: InboxTab(deckId: deckId)),
        ],
      ),
      DeckDestination(:final deckId) => DeckView(deckId: deckId),
      SearchDestination() => const SearchView(),
      AddDestination(:final deckId) => Column(
        children: [
          const TopBar(
            crumbs: [Crumb(icon: Icons.add_box_outlined, label: 'New Card')],
          ),
          Expanded(child: AddTab(initialDeckId: deckId)),
        ],
      ),
    };
  }
}
