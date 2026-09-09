import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class TopBar extends StatelessWidget {
  const TopBar({super.key, required this.crumbs, this.actions = const []});

  final List<Widget> crumbs;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold.maybeOf(context);
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (scaffold?.hasDrawer ?? false)
            IconButton(
              tooltip: 'Menu',
              onPressed: scaffold!.openDrawer,
              icon: const Icon(Icons.menu_rounded),
            ),
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [for (final c in crumbs) Flexible(child: c)],
            ),
          ),
          const Spacer(),
          ...actions,
        ],
      ),
    );
  }
}

class Crumb extends StatelessWidget {
  const Crumb({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
      ),
    ],
  );
}

class ToolbarButton extends StatefulWidget {
  const ToolbarButton({
    super.key,
    required this.child,
    required this.onPressed,
  });

  final Widget child;
  final VoidCallback? onPressed;

  @override
  State<ToolbarButton> createState() => _ToolbarButtonState();
}

class _ToolbarButtonState extends State<ToolbarButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _hover && enabled
                ? AppColors.surfaceHover
                : AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _hover && enabled
                  ? AppColors.borderStrong
                  : AppColors.border,
            ),
          ),
          child: DefaultTextStyle(
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: enabled ? AppColors.text : AppColors.textFaint,
            ),
            child: IconTheme(
              data: IconThemeData(
                size: 16,
                color: enabled ? AppColors.text : AppColors.textFaint,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [widget.child],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CountBadge extends StatelessWidget {
  const CountBadge(this.count, {super.key});

  final int count;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 180),
    transitionBuilder: (child, t) => FadeTransition(
      opacity: t,
      child: ScaleTransition(scale: t, child: child),
    ),
    child: Container(
      key: ValueKey(count),
      constraints: const BoxConstraints(minWidth: 22),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceHover,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.textMuted,
        ),
      ),
    ),
  );
}
