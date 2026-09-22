import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kThemeModeKey = 'theme_mode';

/// Provider que gestiona el [ThemeMode] de la aplicación.
final StateNotifierProvider<ThemeModeNotifier, ThemeMode> themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
  (StateNotifierProviderRef<ThemeModeNotifier, ThemeMode> ref) =>
      ThemeModeNotifier(),
);

/// Notifier que lee/escribe el tema en [SharedPreferences].
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.system) {
    _load();
  }

  Future<void> _load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? stored = prefs.getString(_kThemeModeKey);
    if (stored == null) return;
    final ThemeMode? mode = _fromString(stored);
    if (mode != null) state = mode;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeModeKey, _toString(mode));
  }

  static ThemeMode? _fromString(String value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
    }
    return null;
  }

  static String _toString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}
