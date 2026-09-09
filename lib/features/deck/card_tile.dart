import 'package:flutter/material.dart';

import '../../domain/flashcard.dart';
import '../../theme/app_theme.dart';
import '../../widgets/card_face.dart';
import '../../widgets/dashed_divider.dart';
import 'card_menu.dart';
import 'card_status.dart';
import 'status_glyph.dart';

class CardTile extends StatelessWidget {
  const CardTile({super.key, required this.card, required this.onTap});

  final Flashcard card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = cardStatus(card);
    return PressableSurface(
      onTap: onTap,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 44, 12),
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: CardFace(
                      card.front,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
              ),
              if (card.back.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: DashedDivider(),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: Text(
                    '+ 1 HIDDEN SIDE',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                child: Row(
                  children: [
                    StatusGlyph(status.phase),
                    const SizedBox(width: 10),
                    Text(
                      status.label,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            top: 8,
            right: 8,
            child: CardMenuButton(card: card, color: AppColors.textFaint),
          ),
        ],
      ),
    );
  }
}

class PressableSurface extends StatefulWidget {
  const PressableSurface({
    super.key,
    required this.child,
    required this.onTap,
    this.dashed = false,
  });

  final Widget child;
  final VoidCallback onTap;
  final bool dashed;

  @override
  State<PressableSurface> createState() => _PressableSurfaceState();
}

class _PressableSurfaceState extends State<PressableSurface> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final border = _hover ? AppColors.borderStrong : AppColors.border;
    final body = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: widget.dashed
            ? Colors.transparent
            : (_hover ? AppColors.surfaceHover : AppColors.surface),
        borderRadius: BorderRadius.circular(10),
        border: widget.dashed ? null : Border.all(color: border),
      ),
      child: widget.child,
    );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.98 : 1,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: widget.dashed
              ? DashedBorder(
                  color: _hover ? AppColors.borderStrong : AppColors.border,
                  child: body,
                )
              : body,
        ),
      ),
    );
  }
}
