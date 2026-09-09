import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/flashcard.dart';
import '../../domain/rating.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/card_face.dart';
import '../../widgets/dashed_divider.dart';
import '../deck/card_menu.dart';
import 'inbox_tab.dart';

/// Phone review flow: tap the card to flip, four rating buttons below.
/// [deckId] null reviews every deck.
class MobileReview extends ConsumerStatefulWidget {
  const MobileReview({super.key, this.deckId});

  final String? deckId;

  @override
  ConsumerState<MobileReview> createState() => _MobileReviewState();
}

class _MobileReviewState extends ConsumerState<MobileReview> {
  /// Progress counts distinct cards touched this session; a card rated Again
  /// stays due but is not counted twice.
  final _rated = <String>{};

  Future<void> _rate(Flashcard card, Rating rating) async {
    await ref.read(decksProvider.notifier).rateCard(card, rating);
    if (mounted) setState(() => _rated.add(card.id));
  }

  @override
  Widget build(BuildContext context) {
    final decks = ref.watch(decksProvider);
    final due = [
      for (final c in ref.watch(dueCardsProvider))
        if (widget.deckId == null || c.deckId == widget.deckId) c,
    ];
    final done = _rated.length;
    final total = {..._rated, for (final c in due) c.id}.length;
    final deckNames = {for (final d in decks.value ?? const []) d.id: d.name};
    final card = due.firstOrNull;
    return Column(
      children: [
        _ReviewTopBar(done: done, total: total, card: card),
        Expanded(
          child: decks.isLoading
              ? const Center(child: CircularProgressIndicator())
              : card == null
              ? const EmptyInbox()
              : _Session(
                  key: ValueKey(card.id),
                  card: card,
                  deckName: deckNames[card.deckId] ?? '',
                  onRate: (r) => _rate(card, r),
                ),
        ),
      ],
    );
  }
}

class _ReviewTopBar extends StatelessWidget {
  const _ReviewTopBar({
    required this.done,
    required this.total,
    required this.card,
  });

  final int done;
  final int total;
  final Flashcard? card;

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold.maybeOf(context);
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Menu',
            onPressed: scaffold?.hasDrawer ?? false
                ? scaffold!.openDrawer
                : null,
            icon: const Icon(Icons.menu_rounded, size: 22),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.inbox_outlined, size: 18),
                const SizedBox(width: 10),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '$done',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                      const TextSpan(
                        text: ' / ',
                        style: TextStyle(color: AppColors.textFaint),
                      ),
                      TextSpan(text: '$total'),
                    ],
                  ),
                  style: const TextStyle(
                    fontSize: 17,
                    color: AppColors.textMuted,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 44,
            child: card == null
                ? null
                : Center(child: CardMenuButton(card: card!, size: 22)),
          ),
        ],
      ),
    );
  }
}

class _Session extends StatefulWidget {
  const _Session({
    super.key,
    required this.card,
    required this.deckName,
    required this.onRate,
  });

  final Flashcard card;
  final String deckName;
  final ValueChanged<Rating> onRate;

  @override
  State<_Session> createState() => _SessionState();
}

class _SessionState extends State<_Session> {
  late bool _revealed = widget.card.back.isEmpty;

  void _reveal() {
    if (!_revealed) setState(() => _revealed = true);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
                  child: Row(
                    children: [
                      const Icon(Icons.style_rounded, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        widget.deckName,
                        style: text.bodyMedium?.copyWith(fontSize: 15),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  key: const Key('review-card'),
                  onTap: _reveal,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceRaised,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                            child: CardFace(
                              widget.card.front,
                              style: text.headlineSmall,
                            ),
                          ),
                          if (_revealed && widget.card.back.isNotEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: DashedDivider(),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                24,
                                32,
                                24,
                                32,
                              ),
                              child: CardFace(
                                widget.card.back,
                                style: text.headlineSmall,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _revealed ? 0 : 1,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.touch_app_outlined,
                        size: 20,
                        color: AppColors.textFaint,
                      ),
                      SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Tap to reveal next side',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            color: AppColors.textFaint,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final rating in Rating.values)
                _RateButton(
                  key: Key('rate-${rating.name}'),
                  rating: rating,
                  onTap: () => widget.onRate(rating),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RateButton extends StatefulWidget {
  const _RateButton({super.key, required this.rating, required this.onTap});

  final Rating rating;
  final VoidCallback onTap;

  @override
  State<_RateButton> createState() => _RateButtonState();
}

class _RateButtonState extends State<_RateButton> {
  bool _down = false;

  static (IconData, String, Color) _spec(Rating r) => switch (r) {
    Rating.again => (Icons.close_rounded, 'Again', AppColors.danger),
    Rating.hard => (Icons.remove_rounded, 'Hard', AppColors.warm),
    Rating.good => (Icons.check_rounded, 'Good', AppColors.cool),
    Rating.easy => (Icons.done_all_rounded, 'Easy', AppColors.success),
  };

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = _spec(widget.rating);
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.92 : 1,
        duration: const Duration(milliseconds: 110),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.surfaceRaised,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28, color: color),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
