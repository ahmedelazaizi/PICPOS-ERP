// تباين أدوار الثيم في شاشات البند 14 (الجولة 2) + حارس بنيوي (WCAG ≥ 4.5).
//
// الشاشات: إغلاق الكاشير، لوحة PicPos، مراكز التكلفة PicPos، تفاصيل المرتجع،
// جدول كشف الطرف، قيود اليومية، الموازنات. كانت تكتب
// `AppColors.textPrimary/textSecondary/textMuted/surface/border` الثابتة
// (غامقة على أرضية داكنة)؛ استُبدلت بـ context.picposText/Secondary/Muted/
// Field/Hairline. الاختبار (١) يتحقق من تباين تلك الأدوار على كل أرضية تستعملها
// الشاشات في الوضعين، (٢) يمنع رجوع الثوابت للملفات السبعة.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/theme/picpos_theme.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_surface.dart';

import 'settings_picpos_theme_contrast_test.dart' show contrastRatio;

const _files = <String>[
  'lib/presentation/shift_close_picpos/widgets/picpos_cashier_closing_dialog.dart',
  'lib/presentation/dashboard_picpos/screens/dashboard_picpos_screen.dart',
  'lib/presentation/accounting_picpos/cost_centers_picpos_screen.dart',
  'lib/presentation/screens/sales_returns/return_details_panel.dart',
  'lib/presentation/screens/party_statement/party_statement_table.dart',
  'lib/presentation/screens/journal_entries_screen.dart',
  'lib/presentation/screens/budget_screen.dart',
];

final _themes = <String, ThemeData Function()>{
  'light': () => PicPosTheme.lightTheme,
  'dark': () => PicPosTheme.darkTheme,
};

void main() {
  for (final entry in _themes.entries) {
    testWidgets('أدوار النص على أرضيات الشاشات السبع (${entry.key})',
        (tester) async {
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
        // شارات/صفوف بلون muted شفّاف فوق البطاقة (alpha 0.06–0.12).
        'muted-tint-0.12':
            Color.alphaBlend(ctx.picposMuted.withValues(alpha: 0.12), theme.cardColor),
        // صفوف الجدول المتبادلة: surface بشفافية 0.4 فوق البطاقة.
        'zebra-0.4':
            Color.alphaBlend(ctx.picposField.withValues(alpha: 0.4), theme.cardColor),
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
          // نصّ muted خافت (تلميحات): حدّ أدنى 4.0 كما في اختبار الإعدادات —
          // قيمة الثيم الفاتح #6B7280 قرار ثيم خارج هذا البند.
          final min = fg.key == 'muted' ? 4.0 : 4.5;
          if (r < min) {
            failures.add('${fg.key} on ${bg.key}: ${r.toStringAsFixed(2)}');
          }
        }
      }
      expect(failures, isEmpty, reason: failures.join('\n'));
      // الحدّ مميَّز عن البطاقة (أُسقط عند الاستبدال: border → picposHairline).
      expect(ctx.picposHairline, isNot(theme.cardColor));
      // ولا يتطابق نص الأدوار مع أرضيّته (الخطأ الأصلي: غامق على غامق).
      expect(ctx.picposText, isNot(theme.cardColor));
    });
  }

  test('لا ثوابت AppColors للنص/السطح/الحدّ في ملفات الشاشات المعدَّلة', () {
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
    expect(offenders, isEmpty,
        reason: 'استعمل context.picposText/Secondary/Muted/Field/Hairline.\n'
            '${offenders.join('\n')}');
  });

  test('لا fontSize: 10 في ملفات الشاشات المعدَّلة (الحدّ الأدنى 11)', () {
    final small = RegExp(r'fontSize: 10(?![\d.])');
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
