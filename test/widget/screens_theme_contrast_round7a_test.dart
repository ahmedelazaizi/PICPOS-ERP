// تباين أدوار الثيم في شاشات البند 14 (الجولة 7، دفعة A: ما تبقّى من screens/**)
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
  'lib/presentation/screens/branch_management_dialogs.dart',
  'lib/presentation/screens/branch_management_screen.dart',
  'lib/presentation/screens/budget_screen.dart',
  'lib/presentation/screens/categories_screen.dart',
  'lib/presentation/screens/chart_of_accounts_screen.dart',
  'lib/presentation/screens/commercial_papers_dialogs.dart',
  'lib/presentation/screens/commercial_papers_screen.dart',
  'lib/presentation/screens/customers_screen.dart',
  'lib/presentation/screens/delivery_management_screen.dart',
  'lib/presentation/screens/enhanced_role_management_screen.dart',
  'lib/presentation/screens/fixed_assets_dialogs.dart',
  'lib/presentation/screens/help_center_screen.dart',
  'lib/presentation/screens/invoice_designer/invoice_designer_properties.dart',
  'lib/presentation/screens/invoice_designer/invoice_designer_templates.dart',
  'lib/presentation/screens/invoice_designer/invoice_preview_dialog.dart',
  'lib/presentation/screens/journal_entries_screen.dart',
  'lib/presentation/screens/journal_entry_create_dialog.dart',
  'lib/presentation/screens/loyalty_points_tab.dart',
  'lib/presentation/screens/manufacturing_screen.dart',
  'lib/presentation/screens/offers_screen.dart',
  'lib/presentation/screens/operational_expenses_screen.dart',
  'lib/presentation/screens/party_statement/party_statement_dialogs.dart',
  'lib/presentation/screens/plu_manager_screen.dart',
  'lib/presentation/screens/products/widgets/barcode_label_batch_dialog.dart',
  'lib/presentation/screens/products/widgets/product_edit_dialog.dart',
  'lib/presentation/screens/purchase_invoices/widgets/purchase_invoice_form.dart',
  'lib/presentation/screens/purchase_invoices/widgets/purchase_invoice_items_table.dart',
  'lib/presentation/screens/purchase_returns/return_logic.dart',
  'lib/presentation/screens/quotations/quotations_tab.dart',
  'lib/presentation/screens/reports/consumption_report_screen.dart',
  'lib/presentation/screens/reports/delivery_report_screen.dart',
  'lib/presentation/screens/reports/inventory_report_screen.dart',
  'lib/presentation/screens/reports/purchases_report_screen.dart',
  'lib/presentation/screens/reports/sales_by_classification_report_async.dart',
  'lib/presentation/screens/reports/shifts_report_screen.dart',
  'lib/presentation/screens/reports/tables_report_screen.dart',
  'lib/presentation/screens/reports/top_products_report_screen.dart',
  'lib/presentation/screens/reports/treasury_report_screen.dart',
  'lib/presentation/screens/reports/vat_reconciliation_screen.dart',
  'lib/presentation/screens/reports_screen.dart',
  'lib/presentation/screens/role_management/widgets/role_list_panel.dart',
  'lib/presentation/screens/sales_invoices/widgets/sales_invoices_dashboard.dart',
  'lib/presentation/screens/sales_invoices_screen.dart',
  'lib/presentation/screens/sales_returns/return_logic.dart',
  'lib/presentation/screens/settings/admin_home_settings.dart',
  'lib/presentation/screens/settings/general_settings_widgets.dart',
  'lib/presentation/screens/settings/widgets/add_user_dialog.dart',
  'lib/presentation/screens/settings/widgets/warehouse_access_dialog.dart',
  'lib/presentation/screens/shift_close_screen.dart',
  'lib/presentation/screens/stock_movements_screen.dart',
  'lib/presentation/screens/suppliers_screen.dart',
  'lib/presentation/screens/tables/floor_plan_designer.dart',
  'lib/presentation/screens/tables/merge_table_dialog.dart',
  'lib/presentation/screens/tables/qr_menu_dialog.dart',
  'lib/presentation/screens/tables/split_table_dialog.dart',
  'lib/presentation/screens/tables/table_operations.dart',
  'lib/presentation/screens/tables/table_order_dialog.dart',
  'lib/presentation/screens/tables/table_order_dialogs.dart',
  'lib/presentation/screens/tables/table_reservation_dialog.dart',
  'lib/presentation/screens/tables/widgets/table_order_panel.dart',
  'lib/presentation/screens/tables/widgets/table_section_chip.dart',
  'lib/presentation/screens/tables/widgets/tables_top_bar.dart',
  'lib/presentation/screens/unified_parties_screen.dart',
  'lib/presentation/screens/widgets/manufacturing/bom_tab.dart',
  'lib/presentation/screens/widgets/manufacturing/production_dialog_analytics.dart',
  'lib/presentation/screens/widgets/sales_invoices/sales_invoice_dialogs.dart',
  'lib/presentation/screens/widgets/sales_invoices/sales_invoice_form.dart',
  'lib/presentation/screens/widgets/sales_invoices/sales_invoice_save_edit.dart',
];

// ملفات الأب لمكتبات part استلزمت استيراد picpos_surface.
const _parents = <String>[
  'lib/presentation/screens/branch_management_screen.dart',
  'lib/presentation/screens/journal_entries_screen.dart',
  'lib/presentation/screens/loyalty_screen.dart',
  'lib/presentation/screens/manufacturing_screen.dart',
  'lib/presentation/screens/party_statement_screen.dart',
  'lib/presentation/screens/purchase_returns_screen.dart',
  'lib/presentation/screens/reports/sales_by_classification_report.dart',
  'lib/presentation/screens/sales_invoices_screen.dart',
  'lib/presentation/screens/sales_returns_screen.dart',
  'lib/presentation/screens/settings_screen.dart',
  'lib/presentation/screens/tables_screen.dart',
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
        // pw.TextStyle = PDF مطبوع (qr_menu_dialog) لا واجهة: مستثنى عمداً.
        if (lines[i].contains('pw.')) continue;
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
