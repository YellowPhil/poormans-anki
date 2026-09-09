import 'package:flutter/material.dart';

class NewDeckDialog extends StatefulWidget {
  const NewDeckDialog({super.key});

  @override
  State<NewDeckDialog> createState() => _NewDeckDialogState();
}

class _NewDeckDialogState extends State<NewDeckDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New deck'),
    content: TextField(
      key: const Key('deck-name-field'),
      controller: _name,
      autofocus: true,
      decoration: const InputDecoration(labelText: 'Name'),
      onSubmitted: (v) => Navigator.of(context).pop(v),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_name.text),
        child: const Text('Create'),
      ),
    ],
  );
}
