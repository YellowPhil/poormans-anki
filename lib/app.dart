import 'package:flutter/material.dart';

import 'features/shell/app_shell.dart';
import 'theme/app_theme.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Poormans Anki',
    theme: buildAppTheme(),
    darkTheme: buildAppTheme(),
    themeMode: ThemeMode.dark,
    debugShowCheckedModeBanner: false,
    home: const AppShell(),
  );
}
