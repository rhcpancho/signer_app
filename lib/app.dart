import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/core/theme.dart';
import 'src/core/theme_provider.dart';
import 'src/ui/home/home_screen.dart';

class SignerApp extends ConsumerWidget {
  const SignerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeMode themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'Signer App',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: themeMode,
      home: const HomeScreen(),
    );
  }
}
