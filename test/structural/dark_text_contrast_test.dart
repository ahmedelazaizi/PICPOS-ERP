// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/theme/app_colors.dart';
import 'package:ural_erp/core/theme/picpos_theme.dart';

const _oldDarkSecondary = Color(0xFF374151);
const _oldDarkMuted = Color(0xFF94A3B8);
const _oldDarkHint = Color(0xFF6B7280);
const _lightCanvas = Color(0xFFF2F5FA);
const _lightCard = Color(0xFFFFFFFF);
const _lightField = Color(0xFFF4F7FC);
const _lightPrimaryInk = Color(0xFF000000);
const _lightSecondaryInk = Color(0xFF374151);
const _lightMutedInk = Color(0xFF6B7280);
const _lightBrandInk = Color(0xFF0250D3);
const _uralBrandInk = Color(0xFF2B737F);

double _contrast(Color first, Color second) {
  final a = first.computeLuminance();
  final b = second.computeLuminance();
  final high = a > b ? a : b;
  final low = a > b ? b : a;
  return (high + 0.05) / (low + 0.05);
}

void _printTable(
  String mode,
  Map<String, Color> inks,
  Map<String, Color> surfaces,
  Map<String, Color>? before,
) {
  print('PicPos $mode WCAG contrast table');
  for (final ink in inks.entries) {
    for (final surface in surfaces.entries) {
      final after = _contrast(ink.value, surface.value);
      final old = before == null
          ? null
          : _contrast(before[ink.key] ?? ink.value, surface.value);
      final oldText = old == null ? '-' : old.toStringAsFixed(2);
      print(
        '${ink.key} on ${surface.key}: before $oldText:1, after ${after.toStringAsFixed(2)}:1',
      );
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('PicPos dark text tokens meet WCAG and light tokens do not regress', () {
    final light = PicPosTheme.lightTheme;
    final dark = PicPosTheme.darkTheme;
    final darkInks = <String, Color>{
      'primary': AppColors.textPrimaryDark,
      'secondary': AppColors.textSecondaryDark,
      'muted': AppColors.textMutedDark,
      'hint': dark.inputDecorationTheme.hintStyle!.color!,
      'label': dark.inputDecorationTheme.labelStyle!.color!,
      'brand': const Color(0xFF7DA6F5),
    };
    final darkSurfaces = <String, Color>{
      'canvas': dark.scaffoldBackgroundColor,
      'card': dark.cardColor,
      'field': dark.inputDecorationTheme.fillColor!,
      'surface': dark.colorScheme.surface,
    };
    final oldDark = <String, Color>{
      'primary': AppColors.textPrimaryDark,
      'secondary': _oldDarkSecondary,
      'muted': _oldDarkMuted,
      'hint': _oldDarkHint,
      'label': Colors.white,
      'brand': const Color(0xFF7DA6F5),
    };
    _printTable('dark', darkInks, darkSurfaces, oldDark);

    for (final ink in darkInks.entries) {
      for (final surface in darkSurfaces.entries) {
        expect(
          _contrast(ink.value, surface.value),
          greaterThanOrEqualTo(4.5),
          reason: '${ink.key} on ${surface.key} must remain readable.',
        );
      }
    }

    final lightInks = <String, Color>{
      'primary': AppColors.textPrimary,
      'secondary': AppColors.textSecondary,
      'muted': AppColors.textMuted,
      'brand': AppColors.primary,
    };
    final lightSurfaces = <String, Color>{
      'canvas': light.scaffoldBackgroundColor,
      'card': light.cardColor,
      'field': light.inputDecorationTheme.fillColor!,
      'surface': light.colorScheme.surface,
    };
    final lightBaselineInks = <String, Color>{
      'primary': _lightPrimaryInk,
      'secondary': _lightSecondaryInk,
      'muted': _lightMutedInk,
      'brand': AppColors.primary == _lightBrandInk
          ? _lightBrandInk
          : _uralBrandInk,
    };
    final lightBaselineSurfaces = <String, Color>{
      'canvas': _lightCanvas,
      'card': _lightCard,
      'field': _lightField,
      'surface': _lightCard,
    };
    _printTable('light', lightInks, lightSurfaces, null);

    expect(light.inputDecorationTheme.hintStyle!.color, _lightMutedInk);
    expect(light.inputDecorationTheme.labelStyle!.color, _lightSecondaryInk);
    for (final ink in lightInks.entries) {
      for (final surface in lightSurfaces.entries) {
        final current = _contrast(ink.value, surface.value);
        final baseline = _contrast(
          lightBaselineInks[ink.key]!,
          lightBaselineSurfaces[surface.key]!,
        );
        expect(current, greaterThanOrEqualTo(baseline));
      }
    }
  });
}
