import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/navigation.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';

class MobileTabBar extends ConsumerWidget {
  const MobileTabBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(destinationProvider);
    final due = ref.watch(dueCardsProvider).length;
    void go(Destination d) => ref.read(destinationProvider.notifier).go(d);
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              _Tab(
                key: const Key('tab-dashboard'),
                icon: Icons.trending_up_rounded,
                selected: current is DashboardDestination,
                onTap: () => go(const DashboardDestination()),
              ),
              _Tab(
                key: const Key('tab-search'),
                icon: Icons.search_rounded,
                selected: current is SearchDestination,
                onTap: () => go(const SearchDestination()),
              ),
              _Tab(
                key: const Key('tab-inbox'),
                icon: Icons.inbox_outlined,
                badge: due,
                selected: current is InboxDestination,
                onTap: () => go(const InboxDestination()),
              ),
              _Tab(
                key: const Key('tab-add'),
                icon: Icons.add_box_outlined,
                selected: current is AddDestination,
                onTap: () => go(const AddDestination()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    super.key,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedScale(
              scale: selected ? 1.08 : 1,
              duration: const Duration(milliseconds: 160),
              child: Icon(
                icon,
                size: 28,
                color: selected ? AppColors.text : AppColors.textMuted,
              ),
            ),
            if (badge > 0)
              Positioned(
                top: -8,
                right: -12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  constraints: const BoxConstraints(minWidth: 20),
                  decoration: BoxDecoration(
                    color: AppColors.badge,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$badge',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.3,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
