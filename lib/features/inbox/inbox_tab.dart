import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/flashcard.dart';
import '../../domain/rating.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/card_face.dart';
import '../../widgets/key_cap.dart';
import '../deck/card_menu.dart';

/// [deckId] null reviews every deck.
class InboxTab extends ConsumerWidget {
  const InboxTab({super.key, this.deckId});

  final String? deckId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decks = ref.watch(decksProvider);
    if (decks.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (decks.hasError) {
      return Center(child: Text('Failed to load decks: ${decks.error}'));
    }
    final due = [
      for (final c in ref.watch(dueCardsProvider))
        if (deckId == null || c.deckId == deckId) c,
    ];
    if (due.isEmpty) {
      return const EmptyInbox();
    }
    final card = due.first;
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                child: Text(
                  '${due.length} due',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              Expanded(
                child: _CardReview(
                  key: ValueKey(card.id),
                  card: card,
                  onRate: (rating) =>
                      ref.read(decksProvider.notifier).rateCard(card, rating),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EmptyInbox extends StatelessWidget {
  const EmptyInbox({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.check_circle_outline,
          size: 64,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 12),
        Text('All caught up', style: Theme.of(context).textTheme.titleLarge),
      ],
    ),
  );
}

class _CardReview extends StatefulWidget {
  const _CardReview({super.key, required this.card, required this.onRate});

  final Flashcard card;
  final ValueChanged<Rating> onRate;

  @override
  State<_CardReview> createState() => _CardReviewState();
}

class _CardReviewState extends State<_CardReview> {
  late bool _revealed = widget.card.back.isEmpty;

  void _reveal() {
    if (!_revealed) setState(() => _revealed = true);
  }

  void _rate(Rating rating) {
    if (_revealed) widget.onRate(rating);
  }

  static const _digits = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
  ];

  @override
  Widget build(BuildContext context) {
    final hasBack = widget.card.back.isNotEmpty;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): _reveal,
        const SingleActivator(LogicalKeyboardKey.enter): _reveal,
        for (final (i, key) in _digits.indexed)
          SingleActivator(key): () => _rate(Rating.values[i]),
      },
      child: Focus(
        autofocus: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: _ReviewCard(
                  card: widget.card,
                  revealed: _revealed,
                  showNextSide: !_revealed && hasBack,
                  onNextSide: _reveal,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                transitionBuilder: (child, t) => FadeTransition(
                  opacity: t,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(0, 0.3),
                      end: Offset.zero,
                    ).animate(t),
                    child: child,
                  ),
                ),
                child: _revealed
                    ? Wrap(
                        key: const ValueKey('ratings'),
                        alignment: WrapAlignment.center,
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final (i, rating) in Rating.values.indexed)
                            _RateButton(
                              rating: rating,
                              index: i,
                              onPressed: () => _rate(rating),
                            ),
                        ],
                      )
                    : const SizedBox(key: ValueKey('none'), height: 48),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.card,
    required this.revealed,
    required this.showNextSide,
    required this.onNextSide,
  });

  final Flashcard card;
  final bool revealed;
  final bool showNextSide;
  final VoidCallback onNextSide;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(40, 44, 72, 40),
                  child: CardFace(card.front, style: text.headlineSmall),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: CardMenuButton(card: card),
                ),
              ],
            ),
            if (revealed && card.back.isNotEmpty) ...[
              const Divider(indent: 40, endIndent: 40),
              Padding(
                padding: const EdgeInsets.fromLTRB(40, 40, 40, 44),
                child: CardFace(card.back, style: text.headlineSmall),
              ),
            ],
            if (showNextSide)
              InkWell(
                onTap: onNextSide,
                child: Container(
                  height: 56,
                  decoration: const BoxDecoration(
                    color: AppColors.surfaceRaised,
                    border: Border(top: BorderSide(color: AppColors.border)),
                  ),
                  child: const DefaultTextStyle(
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.arrow_downward_rounded,
                          size: 18,
                          color: AppColors.textMuted,
                        ),
                        SizedBox(width: 10),
                        Text('Next side'),
                        SizedBox(width: 10),
                        KeyCap('SPACE'),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RateButton extends StatelessWidget {
  const _RateButton({
    required this.rating,
    required this.index,
    required this.onPressed,
  });

  final Rating rating;
  final int index;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
    style: FilledButton.styleFrom(
      backgroundColor: AppColors.surfaceRaised,
      foregroundColor: _color(rating),
      side: const BorderSide(color: AppColors.border),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      shape: const StadiumBorder(),
    ),
    onPressed: onPressed,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_icon(rating), size: 16),
        const SizedBox(width: 8),
        Text(_label(rating)),
        const SizedBox(width: 10),
        KeyCap('${index + 1}'),
      ],
    ),
  );

  static IconData _icon(Rating r) => switch (r) {
    Rating.again => Icons.close_rounded,
    Rating.hard => Icons.remove_rounded,
    Rating.good => Icons.check_rounded,
    Rating.easy => Icons.done_all_rounded,
  };

  static String _label(Rating r) => switch (r) {
    Rating.again => 'Again',
    Rating.hard => 'Hard',
    Rating.good => 'Good',
    Rating.easy => 'Easy',
  };

  static Color _color(Rating r) => switch (r) {
    Rating.again => AppColors.danger,
    Rating.hard => AppColors.warm,
    Rating.good => AppColors.cool,
    Rating.easy => AppColors.success,
  };
}
