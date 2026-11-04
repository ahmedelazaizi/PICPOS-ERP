// تباين أدوار الثيم في شاشات البند 14 (الجولة 5 — دفعة A (المحاسبة)) + حارس بنيوي.
//
// استُبدلت ثوابت `AppColors.text*/surface/border` بأدوار context.picpos*
// وfontSize ≤ 10 ← 11 في الملفات أدناه. لا ألوان حالة جديدة: success/warning/
// error الثابتة تتجاوز 3:1 على بطاقة الداكن (يُتحقَّق أدناه).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/theme/app_colors.dart';
import 'package:picpos_erp/core/theme/picpos_theme.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_surface.dart';

import 'settings_picpos_theme_contrast_test.dart' show contrastRatio;

// حارس إضافي: لا ملف في accounting_picpos يستعمل الثوابت المحظورة.
const _files = <String>[
  'lib/presentation/accounting_picpos/account_mapping_picpos_screen.dart',
  'lib/presentation/accounting_picpos/chart_of_accounts_picpos_screen.dart',
  'lib/presentation/accounting_picpos/general_ledger_picpos_screen.dart',
  'lib/presentation/accounting_picpos/journal_entries_picpos_create_dialog.dart',
  'lib/presentation/accounting_picpos/journal_entries_picpos_screen.dart',
  'lib/presentation/accounting_picpos/journal_entries_picpos_widgets.dart',
  'lib/presentation/accounting_picpos/journal_templates_picpos_screen.dart',
  'lib/presentation/accounting_picpos/journal_voucher_picpos_screen.dart',
  'lib/presentation/screens/budget_details_dialog.dart',
  'lib/presentation/screens/create_budget_dialog.dart',
  'lib/presentation/screens/create_journal_template_dialog.dart',
  'lib/presentation/screens/deferred_schedule_screen.dart',
  'lib/presentation/screens/fiscal_year_screen.dart',
  'lib/presentation/screens/journal_entry_widgets.dart',
  'lib/presentation/screens/journal_templates_screen.dart',
  'lib/presentation/screens/coa/coa_dialogs.dart',
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

  test('كل ملفات accounting_picpos خالية من ثوابت النص/السطح/الحدّ', () {
    final banned = RegExp(
        r'AppColors\.(textPrimary|textSecondary|textMuted|surface|border)\b');
    final offenders = <String>[];
    for (final e in Directory('lib/presentation/accounting_picpos').listSync()) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final lines = e.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) continue;
        if (banned.hasMatch(lines[i])) offenders.add('${e.path}:${i + 1}');
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('لا fontSize ≤ 10 في الملفات المعدَّلة (الحدّ الأدنى 11)', () {
    final small = RegExp(r'fontSize: (?:10(?:\.5)?|[0-9])(?![\d.])');
    final offenders = <String>[];
    for (final f in _files) {
      final lines = File(f).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (small.hasMatch(lines[i])) offenders.add('$f:${i + 1}');
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
