// تباين أدوار الثيم في ملفات البند 14 (الجولة 6 — دفعة C: widgets وبقية مجلدات *_picpos) + حارس بنيوي.
//
// استُبدلت ثوابت `AppColors.text*/surface/border` بأدوار context.picpos*
// وfontSize ≤ 10 (بما فيه 10.5) ← 11 في الملفات أدناه.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/theme/app_colors.dart';
import 'package:picpos_erp/core/theme/picpos_theme.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_surface.dart';

import 'settings_picpos_theme_contrast_test.dart' show contrastRatio;

const _p = 'lib/presentation/';
const _files = <String>[
  '${_p}e_invoicing_picpos/screens/e_invoicing_picpos_screen.dart',
  '${_p}purchases_picpos/screens/purchases_invoices_table.dart',
  '${_p}bookings_picpos/widgets/bookings_board_table.dart',
  '${_p}invoice_form_picpos/picpos_invoice_money.dart',
  '${_p}bookings_picpos/widgets/bookings_data_views.dart',
  '${_p}treasury_picpos/widgets/treasury_movements_list_picpos.dart',
  '${_p}widgets/category_card.dart',
  '${_p}landed_cost_picpos/screens/landed_cost_picpos_screen.dart',
  '${_p}sales_invoices_picpos/screens/sales_invoices_table.dart',
  '${_p}widgets/invoice_currency_selector.dart',
  '${_p}widgets/common/app_kpi_card.dart',
  '${_p}widgets/invoice_safety_guards.dart',
  '${_p}widgets/period_close_checklist.dart',
  '${_p}treasury_picpos/screens/voucher_form_picpos.dart',
  '${_p}inventory_picpos/screens/inventory_picpos_screen.dart',
  '${_p}widgets/help_panel_overlay.dart',
  '${_p}reports_picpos/screens/reports_picpos_cards.dart',
  '${_p}activity_log_picpos/screens/activity_log_filters_picpos.dart',
  '${_p}widgets/report_components.dart',
  '${_p}widgets/inventory_aging_report.dart',
  '${_p}activity_log_picpos/screens/activity_log_items_picpos.dart',
  '${_p}parties_picpos/screens/parties_card_grid.dart',
  '${_p}widgets/branch_pl_filter.dart',
  '${_p}widgets/settings/company_info_widget_web.dart',
  '${_p}invoice_form_picpos/picpos_invoice_lines.dart',
  '${_p}treasury/screens/treasury_closing_screen.dart',
  '${_p}products/widgets/product_form.dart',
  '${_p}invoice_form_picpos/picpos_invoice_form.dart',
  '${_p}treasury_picpos/screens/treasury_picpos_screen.dart',
  '${_p}sales_invoices_picpos/screens/sales_invoice_dialogs.dart',
];

// ملفات part: الاستيراد في الملف الأب.
const _parents = <String, String>{
  '${_p}activity_log_picpos/screens/activity_log_filters_picpos.dart':
      '${_p}activity_log_picpos/screens/activity_log_picpos_screen.dart',
  '${_p}activity_log_picpos/screens/activity_log_items_picpos.dart':
      '${_p}activity_log_picpos/screens/activity_log_picpos_screen.dart',
  '${_p}invoice_form_picpos/picpos_invoice_lines.dart':
      '${_p}invoice_form_picpos/picpos_invoice_form.dart',
  '${_p}invoice_form_picpos/picpos_invoice_money.dart':
      '${_p}invoice_form_picpos/picpos_invoice_form.dart',
  '${_p}parties_picpos/screens/parties_card_grid.dart':
      '${_p}parties_picpos/screens/parties_picpos_screen.dart',
  '${_p}purchases_picpos/screens/purchases_invoices_table.dart':
      '${_p}purchases_picpos/screens/purchases_picpos_screen.dart',
  '${_p}reports_picpos/screens/reports_picpos_cards.dart':
      '${_p}reports_picpos/screens/reports_picpos_screen.dart',
  '${_p}sales_invoices_picpos/screens/sales_invoice_dialogs.dart':
      '${_p}sales_invoices_picpos/screens/sales_invoices_picpos_screen.dart',
  '${_p}sales_invoices_picpos/screens/sales_invoices_table.dart':
      '${_p}sales_invoices_picpos/screens/sales_invoices_picpos_screen.dart',
};

// ثابتٌ على مستوى الملف داخل خرائط const لا يملك context — يبقى كما هو عمداً.
const _allowedConst = <String>['const _idle = AppColors.textMuted;'];

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
        if (_allowedConst.any(lines[i].contains)) continue;
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
