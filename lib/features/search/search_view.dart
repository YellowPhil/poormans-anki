import 'package:anki_core/anki_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../deck/card_detail.dart';
import '../shell/top_bar.dart';

class SearchView extends ConsumerStatefulWidget {
  const SearchView({super.key});

  @override
  ConsumerState<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends ConsumerState<SearchView> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final decks = ref.watch(decksProvider).value ?? const [];
    final deckNames = {for (final d in decks) d.id: d.name};
    final needle = _query.trim().toLowerCase();
    final matches = [
      for (final c in ref.watch(allCardsProvider))
        if (needle.isEmpty ||
            c.front.toLowerCase().contains(needle) ||
            c.back.toLowerCase().contains(needle))
          c,
    ];
    return Column(
      children: [
        const TopBar(
          crumbs: [Crumb(icon: Icons.search_rounded, label: 'Search')],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            key: const Key('search-field'),
            autofocus: true,
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded, size: 18),
              hintText: 'Search all cards',
            ),
          ),
        ),
        Expanded(
          child: matches.isEmpty
              ? const Center(
                  child: Text(
                    'No cards match',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: matches.length,
                  separatorBuilder: (_, _) =>
                      const Divider(indent: 16, endIndent: 16),
                  itemBuilder: (_, i) => _ResultRow(
                    card: matches[i],
                    deckName: deckNames[matches[i].deckId] ?? '',
                  ),
                ),
        ),
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.card, required this.deckName});

  final Flashcard card;
  final String deckName;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: () => showCardDetail(context, card: card, deckName: deckName),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.front,
                    style: text.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (card.back.isNotEmpty)
                    Text(
                      card.back,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(deckName, style: text.labelSmall),
          ],
        ),
      ),
    );
  }
}
