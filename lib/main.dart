import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'state/providers.dart';
import 'storage/store_factory.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await createFileStore();
  debugPrint(describeFileStore(store));
  runApp(
    ProviderScope(
      overrides: [fileStoreProvider.overrideWithValue(store)],
      child: const App(),
    ),
  );
}
