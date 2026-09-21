import 'package:flutter/material.dart';

import 'src/core/theme.dart';
import 'src/ui/home/home_screen.dart';

class SignerApp extends StatelessWidget {
  const SignerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Signer App',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
