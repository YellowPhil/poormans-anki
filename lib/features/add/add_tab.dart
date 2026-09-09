import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/deck.dart';
import '../../state/providers.dart';
import '../../widgets/key_cap.dart';
import 'card_text.dart';
import 'new_deck_dialog.dart';

const _newDeckMenuValue = '__new_deck__';

const editorTextStyle = TextStyle(
  fontFamily: 'Menlo',
  fontFamilyFallback: ['Monaco', 'Courier New', 'monospace'],
  fontSize: 20,
  height: 1.6,
);

class AddTab extends ConsumerStatefulWidget {
  const AddTab({super.key, this.initialDeckId});

  final String? initialDeckId;

  @override
  ConsumerState<AddTab> createState() => _AddTabState();
}

class _AddTabState extends ConsumerState<AddTab> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  late String? _deckId = widget.initialDeckId;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _canSave => _deckId != null && _text.text.trim().isNotEmpty;

  Future<void> _save() async {
    if (!_canSave) return;
    final (:front, :back) = splitCardText(_text.text);
    if (front.isEmpty) return;
    await ref.read(decksProvider.notifier).addCard(_deckId!, front, back);
    _text.clear();
    _focus.requestFocus();
  }

  void _addHiddenSide() {
    final (:text, :cursor) = insertSeparator(_text.text, _text.selection.end);
    _text.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: cursor),
    );
    _focus.requestFocus();
  }

  Future<void> _onDeckMenu(String value) async {
    if (value != _newDeckMenuValue) {
      setState(() => _deckId = value);
      return;
    }
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const NewDeckDialog(),
    );
    if (name == null || name.trim().isEmpty) return;
    final deck = await ref.read(decksProvider.notifier).createDeck(name.trim());
    setState(() => _deckId = deck.id);
  }

  @override
  Widget build(BuildContext context) {
    final decks = ref.watch(decksProvider).value;
    if (decks == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!decks.any((d) => d.id == _deckId)) {
      _deckId = decks.isEmpty ? null : decks.first.id;
    }
    final selected = decks.where((d) => d.id == _deckId).firstOrNull;
    final scheme = Theme.of(context).colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 600;
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                        _save,
                    const SingleActivator(
                      LogicalKeyboardKey.enter,
                      control: true,
                    ): _save,
                  },
                  child: TextField(
                    key: const Key('editor-field'),
                    controller: _text,
                    focusNode: _focus,
                    autofocus: true,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: editorTextStyle,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.fromLTRB(32, 40, 72, 24),
                      hintText: 'Front\n---\nBack',
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    key: const Key('clear-button'),
                    tooltip: 'Clear',
                    onPressed: _text.text.isEmpty ? null : _text.clear,
                    icon: const Icon(Icons.close),
                  ),
                ),
              ],
            ),
          ),
          Material(
            color: scheme.surfaceContainer,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  if (!hasSeparator(_text.text))
                    if (compact)
                      IconButton(
                        key: const Key('add-hidden-side'),
                        tooltip: 'Add hidden side',
                        onPressed: _addHiddenSide,
                        icon: const Icon(Icons.add),
                      )
                    else
                      TextButton.icon(
                        key: const Key('add-hidden-side'),
                        onPressed: _addHiddenSide,
                        icon: const Icon(Icons.add),
                        label: const Text('Add hidden side'),
                      ),
                  const Spacer(),
                  Flexible(
                    child: PopupMenuButton<String>(
                      key: const Key('deck-chip'),
                      tooltip: 'Deck',
                      onSelected: _onDeckMenu,
                      itemBuilder: (_) => [
                        for (final Deck d in decks)
                          PopupMenuItem(value: d.id, child: Text(d.name)),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: _newDeckMenuValue,
                          child: Text('New deck…'),
                        ),
                      ],
                      child: Chip(
                        avatar: const Icon(Icons.folder_outlined, size: 18),
                        label: Text(
                          selected?.name ?? 'No deck',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    key: const Key('save-button'),
                    onPressed: _canSave ? _save : null,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Save'),
                        if (!compact) ...const [
                          SizedBox(width: 10),
                          KeyCap('⌘'),
                          SizedBox(width: 4),
                          KeyCap('⏎'),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
