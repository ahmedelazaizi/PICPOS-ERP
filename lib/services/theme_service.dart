import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to persist and retrieve theme preferences
class ThemeService {
  static const String _themeModeKey = 'app_theme_mode';

  /// Save theme mode to SharedPreferences
  Future<void> saveThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, mode.name);
  }

  /// Load theme mode from SharedPreferences
  /// Defaults to [ThemeMode.system] if no value is found or on error
  Future<ThemeMode> getThemeMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final themeString = prefs.getString(_themeModeKey);

      if (themeString == null) return ThemeMode.system;

      return ThemeMode.values.firstWhere(
        (e) => e.name == themeString,
        orElse: () => ThemeMode.system,
      );
    } catch (e) {
      return ThemeMode.system;
    }
  }
}
