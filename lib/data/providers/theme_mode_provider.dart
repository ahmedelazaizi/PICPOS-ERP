import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/theme_service.dart';

final themeServiceProvider = Provider<ThemeService>((ref) => ThemeService());

/// الوضع المحمَّل قبل `runApp` (يُتجاوَز في `main`) كي يُرسم أول إطار بالوضع
/// المحفوظ بلا وميض فاتح. الافتراضي `system` = نفس افتراض [ThemeService].
final initialThemeModeProvider = Provider<ThemeMode>((ref) => ThemeMode.system);

/// الوضع الفعلي المعروض: `system` يتبع سطوع المنصّة.
bool isEffectivelyDark(ThemeMode mode, Brightness platformBrightness) =>
    mode == ThemeMode.dark ||
    (mode == ThemeMode.system && platformBrightness == Brightness.dark);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  late final ThemeService _service;

  @override
  ThemeMode build() {
    _service = ref.read(themeServiceProvider);
    return ref.read(initialThemeModeProvider);
  }

  /// Load the saved theme mode from persistent storage.
  Future<void> init() async {
    final savedMode = await _service.getThemeMode();
    state = savedMode;
  }

  /// يطبّق الوضع فوراً ثم يحفظه؛ فشل الحفظ لا يرمي ولا يتراجع عن الواجهة
  /// (الوضع يبقى للجلسة).
  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    try {
      await _service.saveThemeMode(mode);
    } catch (e) {
      debugPrint('[Theme] saveThemeMode failed: $e');
    }
  }

  /// يحوّل إلى عكس الوضع الفعلي الحالي.
  Future<void> toggle(Brightness platformBrightness) => setMode(
        isEffectivelyDark(state, platformBrightness)
            ? ThemeMode.light
            : ThemeMode.dark,
      );

  // Backward compatibility for old calls
  void setDarkMode(bool value) {
    setMode(value ? ThemeMode.dark : ThemeMode.light);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);
