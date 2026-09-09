import 'package:flutter/material.dart';

/// Tints from the ambient [DefaultTextStyle] so it reads on both light and
/// dark buttons.
class KeyCap extends StatelessWidget {
  const KeyCap(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ink =
        DefaultTextStyle.of(context).style.color ??
        Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: 0.08),
        border: Border.all(color: ink.withValues(alpha: 0.18)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontFamily: 'Menlo',
          fontFamilyFallback: const ['Monaco', 'Courier New', 'monospace'],
          color: ink.withValues(alpha: 0.75),
        ),
      ),
    );
  }
}
