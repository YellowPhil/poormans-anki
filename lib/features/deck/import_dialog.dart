import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../add/card_text.dart';

typedef PickedTextFile = ({String name, String content});

final pickMarkdownFileProvider = Provider<Future<PickedTextFile?> Function()>(
  (_) => _pickMarkdownFile,
);

Future<PickedTextFile?> _pickMarkdownFile() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['md', 'markdown'],
  );
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  return (name: file.name, content: utf8.decode(bytes, allowMalformed: true));
}

/// Resolves to the number of imported cards, or null when cancelled.
Future<int?> showImportDialog(BuildContext context, {required String deckId}) =>
    showDialog<int>(
      context: context,
      builder: (_) => ImportDialog(deckId: deckId),
    );

class ImportDialog extends ConsumerStatefulWidget {
  const ImportDialog({super.key, required this.deckId});

  final String deckId;

  @override
  ConsumerState<ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends ConsumerState<ImportDialog> {
  final _separator = TextEditingController(text: ';;;');
  PickedTextFile? _file;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _separator.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _separator.dispose();
    super.dispose();
  }

  List<({String front, String back})> get _cards => _file == null
      ? const []
      : splitImportText(_file!.content, _separator.text);

  Future<void> _pick() async {
    final file = await ref.read(pickMarkdownFileProvider)();
    if (file != null && mounted) setState(() => _file = file);
  }

  Future<void> _import() async {
    final cards = _cards;
    setState(() => _busy = true);
    await ref.read(decksProvider.notifier).importCards(widget.deckId, cards);
    if (mounted) Navigator.of(context).pop(cards.length);
  }

  @override
  Widget build(BuildContext context) {
    final count = _cards.length;
    final canImport =
        !_busy && _file != null && _separator.text.isNotEmpty && count > 0;
    return AlertDialog(
      title: const Text('Import cards'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              key: const Key('import-pick-file'),
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.description_outlined),
              label: Text(
                _file?.name ?? 'Choose .md file',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('import-separator'),
              controller: _separator,
              decoration: const InputDecoration(
                labelText: 'Card separator',
                helperText: 'Front and back are split by a --- line',
              ),
            ),
            if (_file != null) ...[
              const SizedBox(height: 16),
              Text(
                count == 1 ? '1 card found' : '$count cards found',
                key: const Key('import-count'),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('import-confirm'),
          onPressed: canImport ? _import : null,
          child: const Text('Import'),
        ),
      ],
    );
  }
}
