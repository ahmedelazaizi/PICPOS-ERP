// تباين أدوار الثيم في شاشات البند 14 (الجولة 5 — دفعة C) + حارس بنيوي.
//
// استُبدلت ثوابت `AppColors.text*/surface/border` بأدوار context.picpos*
// وfontSize ≤ 10 (بما فيه 9.5) ← 11 في الملفات أدناه.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/theme/app_colors.dart';
import 'package:picpos_erp/core/theme/picpos_theme.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_surface.dart';

import 'settings_picpos_theme_contrast_test.dart' show contrastRatio;

const _p = 'lib/presentation/';
const _files = <String>[
  '${_p}widgets/getting_started_checklist.dart',
  '${_p}widgets/category_icon_picker.dart',
  '${_p}widgets/advanced_filter_bar.dart',
  '${_p}widgets/notifications/notification_panel.dart',
  '${_p}screens/inventory/inventory_bonds_screen.dart',
  '${_p}screens/inventory/inventory_screen.dart',
  '${_p}screens/inventory/inventory_summary_card.dart',
  '${_p}screens/inventory/stock_transfer_screen.dart',
  '${_p}screens/inventory/widgets/inventory_filters_bar.dart',
  '${_p}screens/inventory/widgets/inventory_header.dart',
  '${_p}screens/inventory/widgets/inventory_summary_card.dart',
  '${_p}screens/inventory/widgets/stock_balances_table.dart',
  '${_p}screens/inventory/widgets/stock_movements_table.dart',
  '${_p}screens/scale_plu/scale_panels.dart',
  '${_p}screens/plu_manager/plu_table_mixin.dart',
  '${_p}screens/settings_screen.dart',
  '${_p}bookings_picpos/widgets/bookings_simple_views.dart',
  '${_p}bookings_picpos/widgets/booking_catalog_editors.dart',
  '${_p}scale_plu_picpos/screens/scale_panels_picpos.dart',
  '${_p}users_picpos/screens/users_management_picpos_screen.dart',
];

// ملفات part: الاستيراد في الملف الأب.
const _parents = <String, String>{
  '${_p}screens/scale_plu/scale_panels.dart':
      '${_p}screens/scale_plu_export_screen.dart',
  '${_p}screens/plu_manager/plu_table_mixin.dart':
      '${_p}screens/plu_manager_screen.dart',
  '${_p}scale_plu_picpos/screens/scale_panels_picpos.dart':
      '${_p}scale_plu_picpos/screens/scale_plu_picpos_screen.dart',
};

final _themes = <String, ThemeData Function()>{
  'light': () => PicPosTheme.lightTheme,
  'dark': () => PicPosTheme.darkTheme,
};

void main() {
  for (final entry in _themes.entries) {
    testWidgets('أدوار النص على أرضيات الشاشات (${entry.key})', (tester) async {
      final theme = entry.value();
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        }),
      ));
      final backgrounds = <String, Color>{
        'scaffold': theme.scaffoldBackgroundColor,
        'card': theme.cardColor,
        'field': ctx.picposField,
        'muted-tint-0.08': Color.alphaBlend(
            ctx.picposMuted.withValues(alpha: 0.08), theme.cardColor),
      };
      final foregrounds = <String, Color>{
        'text': ctx.picposText,
        'secondary': ctx.picposSecondary,
        'muted': ctx.picposMuted,
      };
      final failures = <String>[];
      for (final bg in backgrounds.entries) {
        for (final fg in foregrounds.entries) {
          final r = contrastRatio(fg.value, bg.value);
          final min = fg.key == 'muted' ? 4.0 : 4.5;
          if (r < min) failures.add('${fg.key} on ${bg.key}: ${r.toStringAsFixed(2)}');
        }
      }
      expect(failures, isEmpty, reason: failures.join('\n'));
      expect(ctx.picposHairline, isNot(theme.cardColor));
      expect(ctx.picposText, isNot(theme.cardColor));
    });
  }

  testWidgets('ألوان الحالة الثابتة مقروءة (≥3:1) على بطاقة الداكن', (tester) async {
    final card = PicPosTheme.darkTheme.cardColor;
    final failures = <String>[];
    for (final e in {
      'success': AppColors.success,
      'warning': AppColors.warning,
      'error': AppColors.error,
    }.entries) {
      final r = contrastRatio(e.value, card);
      if (r < 3.0) failures.add('${e.key}: ${r.toStringAsFixed(2)}');
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test('لا ثوابت AppColors للنص/السطح/الحدّ في الملفات المعدَّلة', () {
    final banned = RegExp(
        r'AppColors\.(textPrimary|textSecondary|textMuted|surface|border)\b');
    final offenders = <String>[];
    for (final f in _files) {
      final lines = File(f).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) continue;
        if (banned.hasMatch(lines[i])) offenders.add('$f:${i + 1}');
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('لا fontSize ≤ 10 (حتى الكسري) في الملفات المعدَّلة (الحدّ الأدنى 11)', () {
    final size = RegExp(r'fontSize: (\d+(?:\.\d+)?)');
    final offenders = <String>[];
    for (final f in _files) {
      final lines = File(f).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final m in size.allMatches(lines[i])) {
          if (double.parse(m.group(1)!) <= 10) offenders.add('$f:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('كل ملف يستخدم context.picpos* يستورد picpos_surface (أو أبوه للـpart)', () {
    final offenders = <String>[];
    for (final f in _files) {
      if (!File(f).readAsStringSync().contains('context.picpos')) continue;
      final host = File(_parents[f] ?? f).readAsStringSync();
      if (!host.contains('picpos_surface.dart')) offenders.add(f);
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
