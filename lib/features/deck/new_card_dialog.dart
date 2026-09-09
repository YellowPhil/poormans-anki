import 'package:flutter/material.dart';

import '../add/add_tab.dart';

Future<void> showNewCardDialog(
  BuildContext context, {
  required String deckId,
}) => showDialog<void>(
  context: context,
  builder: (_) => Dialog(
    clipBehavior: Clip.antiAlias,
    insetPadding: const EdgeInsets.all(24),
    child: SizedBox(
      width: 760,
      height: 520,
      child: AddTab(initialDeckId: deckId),
    ),
  ),
);
