import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/flashcard.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import 'card_editor.dart';

enum CardAction { edit, remove }

/// "..." menu shared by grid tiles, the detail overlay and the review screens.
class CardMenuButton extends ConsumerWidget {
  const CardMenuButton({
    super.key,
    required this.card,
    this.onRemoved,
    this.color = AppColors.textMuted,
    this.size = 20,
  });

  final Flashcard card;
  final VoidCallback? onRemoved;
  final Color color;
  final double size;

  Future<void> _onSelected(
    BuildContext context,
    WidgetRef ref,
    CardAction action,
  ) async {
    switch (action) {
      case CardAction.edit:
        await showCardEditor(context, card);
      case CardAction.remove:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Remove card?'),
            content: Text(
              card.front,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textMuted),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const Key('confirm-remove'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Remove'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        await ref.read(decksProvider.notifier).deleteCard(card);
        onRemoved?.call();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      PopupMenuButton<CardAction>(
        key: Key('card-menu-${card.id}'),
        tooltip: 'Card menu',
        padding: EdgeInsets.zero,
        iconSize: size,
        icon: Icon(Icons.more_horiz_rounded, color: color, size: size),
        onSelected: (a) => _onSelected(context, ref, a),
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: CardAction.edit,
            child: Row(
              children: [
                Icon(Icons.edit_outlined, size: 16),
                SizedBox(width: 10),
                Text('Edit'),
              ],
            ),
          ),
          PopupMenuItem(
            value: CardAction.remove,
            child: Row(
              children: [
                Icon(
                  Icons.delete_outline_rounded,
                  size: 16,
                  color: AppColors.danger,
                ),
                SizedBox(width: 10),
                Text('Remove', style: TextStyle(color: AppColors.danger)),
              ],
            ),
          ),
        ],
      );
}
