import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/flashcard.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/card_face.dart';
import '../../widgets/dashed_divider.dart';
import 'card_menu.dart';
import 'card_status.dart';
import 'status_glyph.dart';

Future<void> showCardDetail(
  BuildContext context, {
  required Flashcard card,
  required String deckName,
}) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Close',
  barrierColor: Colors.black.withValues(alpha: 0.55),
  transitionDuration: const Duration(milliseconds: 220),
  transitionBuilder: (_, animation, _, child) {
    final t = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: t,
      child: ScaleTransition(
        scale: Tween(begin: 0.96, end: 1.0).animate(t),
        child: child,
      ),
    );
  },
  pageBuilder: (_, _, _) => Center(
    child: CardDetail(card: card, deckName: deckName),
  ),
);

class CardDetail extends ConsumerWidget {
  const CardDetail({super.key, required this.card, required this.deckName});

  final Flashcard card;
  final String deckName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final status = cardStatus(card);
    final now = ref.watch(clockProvider)();
    return Padding(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
        child: Material(
          color: AppColors.surfaceRaised,
          clipBehavior: Clip.antiAlias,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            side: BorderSide(color: AppColors.borderStrong),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.topRight,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(0, 10, 10, 0),
                          child: CardMenuButton(
                            card: card,
                            onRemoved: Navigator.of(context).pop,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(36, 8, 36, 36),
                        child: CardFace(card.front, style: text.headlineSmall),
                      ),
                      if (card.back.isNotEmpty) ...[
                        const DashedDivider(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(36, 36, 36, 44),
                          child: CardFace(card.back, style: text.headlineSmall),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.style_rounded, size: 16),
                        const SizedBox(width: 10),
                        Text(deckName, style: text.bodyMedium),
                        const Spacer(),
                        StatusGlyph(status.phase),
                        const SizedBox(width: 10),
                        Text(status.label, style: text.labelSmall),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Divider(),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.check_rounded, size: 16),
                        const SizedBox(width: 10),
                        Text(
                          dueLabel(card, now),
                          style: text.bodyMedium?.copyWith(
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
