// تباين أدوار الثيم في شاشات البند 14 (الجولة 6، دفعة B: بقية screens/**)
// + حارس بنيوي. استُبدلت ثوابت AppColors.text*/surface/border بأدوار
// context.picpos* وfontSize ≤ 10 ← 11 في الملفات أدناه.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/theme/app_colors.dart';
import 'package:picpos_erp/core/theme/picpos_theme.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_surface.dart';

import 'settings_picpos_theme_contrast_test.dart' show contrastRatio;

const _files = <String>[
  'lib/presentation/screens/invoice_designer/invoice_section_editor.dart',
  'lib/presentation/screens/fixed_assets_screen.dart',
  'lib/presentation/screens/account_mapping_settings_screen.dart',
  'lib/presentation/screens/exchange_rate_screen.dart',
  'lib/presentation/screens/coa/coa_tree_node.dart',
  'lib/presentation/screens/stock_audit_screen.dart',
  'lib/presentation/screens/reports/expenses_report_screen.dart',
  'lib/presentation/screens/treasury_screen.dart',
  'lib/presentation/screens/reports/ar_aging_report_screen.dart',
  'lib/presentation/screens/purchase_returns_screen.dart',
  'lib/presentation/screens/role_management_screen.dart',
  'lib/presentation/screens/reports/sales_by_classification_report.dart',
  'lib/presentation/screens/party_statement_screen.dart',
  'lib/presentation/screens/reports/financial_statements_screen.dart',
  'lib/presentation/screens/analytics_dashboard_screen.dart',
  'lib/presentation/screens/activity_log/activity_log_filters.dart',
  'lib/presentation/screens/activity_log/activity_log_items.dart',
  'lib/presentation/screens/role_management/widgets/permission_category_card.dart',
  'lib/presentation/screens/plu_manager/plu_scale_upload_mixin.dart',
  'lib/presentation/screens/widgets/manufacturing/production_orders_tab.dart',
  'lib/presentation/screens/pos_terminals_screen.dart',
  'lib/presentation/screens/region_management_screen.dart',
  'lib/presentation/screens/widgets/sales_invoices/sales_invoices_table.dart',
  'lib/presentation/screens/products/widgets/product_search_header.dart',
  'lib/presentation/screens/opex_expenses_tab.dart',
  'lib/presentation/screens/sales_invoices/widgets/sales_items_table.dart',
  'lib/presentation/screens/reports/tax_report_screen.dart',
  'lib/presentation/screens/tables/widgets/table_card.dart',
  'lib/presentation/screens/opex_categories_tab.dart',
  'lib/presentation/screens/stock_movements_screen_rows.dart',
  'lib/presentation/screens/widgets/sales_invoices/sales_filter_bar.dart',
  'lib/presentation/screens/invoice_designer/invoice_designer_canvas.dart',
];

// ملفات الأب لمكتبات part استلزمت استيراد picpos_surface.
const _parents = <String>[
  'lib/presentation/screens/activity_log_screen.dart',
  'lib/presentation/screens/plu_manager_screen.dart',
  'lib/presentation/screens/manufacturing_screen.dart',
  'lib/presentation/screens/sales_invoices_screen.dart',
  'lib/presentation/screens/operational_expenses_screen.dart',
  'lib/presentation/screens/stock_movements_screen.dart',
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
}
