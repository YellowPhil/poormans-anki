import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/flashcard.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/key_cap.dart';
import '../add/add_tab.dart';
import '../add/card_text.dart';
import '../shell/app_shell.dart';

/// Phones push a full-screen editor; wider layouts open it in a dialog.
Future<void> showCardEditor(BuildContext context, Flashcard card) {
  if (MediaQuery.sizeOf(context).width < sidebarBreakpoint) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
          body: SafeArea(child: CardEditor(card: card)),
        ),
      ),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(width: 760, height: 520, child: CardEditor(card: card)),
    ),
  );
}

class CardEditor extends ConsumerStatefulWidget {
  const CardEditor({super.key, required this.card});

  final Flashcard card;

  @override
  ConsumerState<CardEditor> createState() => _CardEditorState();
}

class _CardEditorState extends ConsumerState<CardEditor> {
  late final _text = TextEditingController(
    text: joinCardText(widget.card.front, widget.card.back),
  );

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _canSave {
    final (:front, back: _) = splitCardText(_text.text);
    return front.isNotEmpty;
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final (:front, :back) = splitCardText(_text.text);
    await ref.read(decksProvider.notifier).updateCard(widget.card, front, back);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Column(
      children: [
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Cancel',
                onPressed: Navigator.of(context).pop,
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
              const SizedBox(width: 4),
              const Text(
                'Edit card',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        Expanded(
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                  _save,
              const SingleActivator(LogicalKeyboardKey.enter, control: true):
                  _save,
            },
            child: TextField(
              key: const Key('card-editor-field'),
              controller: _text,
              autofocus: true,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: editorTextStyle,
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.fromLTRB(32, 32, 32, 24),
                hintText: 'Front\n---\nBack',
              ),
            ),
          ),
        ),
        Material(
          color: AppColors.surface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                const Spacer(),
                FilledButton(
                  key: const Key('card-editor-save'),
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
    );
  }
}
