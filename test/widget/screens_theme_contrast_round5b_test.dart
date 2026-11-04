// تباين أدوار الثيم في شاشات البند 14 (الجولة 5، دفعة B: المبيعات/المشتريات/
// العروض/HR) + حارس بنيوي. استُبدلت ثوابت AppColors.text*/surface/border
// بأدوار context.picpos* وfontSize ≤ 10 ← 11 في الملفات أدناه.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/theme/app_colors.dart';
import 'package:picpos_erp/core/theme/picpos_theme.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_surface.dart';

import 'settings_picpos_theme_contrast_test.dart' show contrastRatio;

const _files = <String>[
  'lib/presentation/screens/offers/offer_dialogs.dart',
  'lib/presentation/screens/offers/offer_cards.dart',
  'lib/presentation/offers_picpos/offer_dialogs_picpos.dart',
  'lib/presentation/offers_picpos/offer_cards_picpos.dart',
  'lib/presentation/screens/sales_returns_screen.dart',
  'lib/presentation/screens/purchase_invoices_screen.dart',
  'lib/presentation/screens/sales_orders_screen.dart',
  'lib/presentation/screens/purchase_orders_screen.dart',
  'lib/presentation/screens/compliance_dashboard_screen.dart',
  'lib/presentation/screens/purchase_returns/return_details_panel.dart',
  'lib/presentation/screens/reports/sales_report_screen.dart',
  'lib/presentation/pos/widgets/pos_previous_invoices_dialog.dart',
  'lib/presentation/screens/hr/widgets/attendance_tab.dart',
  'lib/presentation/screens/hr/widgets/hr_contracts_tab.dart',
  'lib/presentation/screens/hr/widgets/hr_dashboard_tab.dart',
  'lib/presentation/screens/hr/widgets/hr_performance_tab.dart',
  'lib/presentation/screens/hr/widgets/leaves_tab.dart',
  'lib/presentation/screens/hr/widgets/overtime_tab.dart',
  'lib/presentation/screens/hr/widgets/staff_list_tab.dart',
];

// ملفات الأب (part) التي استلزمت استيراد picpos_surface فقط.
const _parents = <String>[
  'lib/presentation/screens/offers_screen.dart',
  'lib/presentation/offers_picpos/offers_picpos_screen.dart',
  'lib/presentation/screens/purchase_returns_screen.dart',
];

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

  test('لا fontSize ≤ 10 في الملفات المعدَّلة (الحدّ الأدنى 11)', () {
    final small = RegExp(r'fontSize: (?:10|[0-9])(?![\d.])');
    final offenders = <String>[];
    for (final f in _files) {
      final lines = File(f).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (small.hasMatch(lines[i])) offenders.add('$f:${i + 1}');
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('الملفات المعدَّلة تستورد picpos_surface (مباشرة أو عبر الأب)', () {
    bool has(String f) =>
        File(f).readAsStringSync().contains('picpos_surface.dart');
    final missing = <String>[];
    for (final f in _files) {
      final src = File(f).readAsStringSync();
      if (src.contains('context.picpos') &&
          !RegExp(r'^part of', multiLine: true).hasMatch(src) &&
          !has(f)) {
        missing.add(f);
      }
    }
    for (final f in _parents) {
      if (!has(f)) missing.add(f);
    }
    expect(missing, isEmpty, reason: missing.join('\n'));
  });

  test('pos_previous_invoices_dialog يحتفظ بـ onReturn', () {
    final src = File('lib/presentation/pos/widgets/pos_previous_invoices_dialog.dart')
        .readAsStringSync();
    expect(src, contains('onReturn'));
  });
}