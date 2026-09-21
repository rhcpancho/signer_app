import 'package:flutter/material.dart';

const Color kSeedColor = Color(0xFF2E5BFF);

ThemeData buildAppTheme(Brightness brightness) {
  final ColorScheme scheme =
      ColorScheme.fromSeed(seedColor: kSeedColor, brightness: brightness);

  final ColorScheme effective = scheme;

  return ThemeData(
    colorScheme: effective,
    useMaterial3: true,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    ),
  );
}