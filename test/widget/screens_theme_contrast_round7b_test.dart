// تباين أدوار الثيم في ملفات البند 14 (الجولة 7 — دفعة B: كل lib/presentation
// ما عدا screens/** والباركود/القوالب/الجرد/المطوّر) + حارس بنيوي.
//
// استُبدلت ثوابت `AppColors.text*/surface/border` بأدوار context.picpos*
// وfontSize ≤ 10 (بما فيه الكسري) ← 11، ولوّنت حالاتٌ معروضة كنصٍّ بـreadableOn.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/theme/app_colors.dart';
import 'package:picpos_erp/core/theme/picpos_theme.dart';
import 'package:picpos_erp/core/theme/readable_colors.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_surface.dart';

import 'settings_picpos_theme_contrast_test.dart' show contrastRatio;

const _p = 'lib/presentation/';
const _files = <String>[
  '${_p}accounting_picpos/bank_reconciliation_picpos_screen.dart',
  '${_p}accounting_picpos/financial_statements_picpos_screen.dart',
  '${_p}activity_log_picpos/screens/activity_log_table_picpos.dart',
  '${_p}analytics_picpos/fin_kpi_card.dart',
  '${_p}analytics_picpos/screens/analytics_picpos_screen.dart',
  '${_p}bookings_picpos/screens/bookings_picpos_screen.dart',
  '${_p}bookings_picpos/widgets/bookings_day_bar.dart',
  '${_p}bookings_picpos/widgets/bookings_destination_tabs.dart',
  '${_p}bookings_picpos/widgets/bookings_settings_view.dart',
  '${_p}bookings_picpos/widgets/bookings_simple_views.dart',
  '${_p}bookings_picpos/widgets/booking_invoice_dialog.dart',
  '${_p}bookings_picpos/widgets/new_booking_panel.dart',
  '${_p}categories_picpos/screens/categories_picpos_screen.dart',
  '${_p}dashboard_picpos/screens/dashboard_picpos_screen.dart',
  '${_p}dashboard_picpos/widgets/picpos_donut.dart',
  '${_p}fixed_assets_picpos/screens/asset_categories_picpos_screen.dart',
  '${_p}fixed_assets_picpos/screens/asset_disposal_request_picpos.dart',
  '${_p}fixed_assets_picpos/screens/asset_locations_picpos_screen.dart',
  '${_p}fixed_assets_picpos/screens/fixed_assets_picpos_create_dialog.dart',
  '${_p}floor_plan_picpos/screens/floor_plan_designer_picpos_screen.dart',
  '${_p}floor_plan_picpos/widgets/floor_plan_canvas_picpos.dart',
  '${_p}hr_picpos/widgets/attendance_month_sheet.dart',
  '${_p}import_purchases_picpos/screens/import_purchases_picpos_screen.dart',
  '${_p}inventory_picpos/widgets/stock_movements_table_picpos.dart',
  '${_p}invoice_form_picpos/picpos_invoice_layout.dart',
  '${_p}invoice_form_picpos/picpos_invoice_one_time_customer.dart',
  '${_p}kitchen/screens/kds_stats_screen.dart',
  '${_p}kitchen/screens/kitchen_display_screen.dart',
  '${_p}offers_picpos/offers_picpos_screen.dart',
  '${_p}opex_picpos/screens/opex_picpos_allocate_dialog.dart',
  '${_p}parties_picpos/system_party_badge.dart',
  '${_p}parties_picpos/dialogs/add_party_dialog_picpos.dart',
  '${_p}parties_picpos/screens/party_route_row.dart',
  '${_p}picpos_shell/picpos_bar_list.dart',
  '${_p}picpos_shell/picpos_data_table.dart',
  '${_p}picpos_shell/picpos_entity_card.dart',
  '${_p}picpos_shell/picpos_hub_kpi.dart',
  '${_p}picpos_shell/picpos_report_tabs.dart',
  '${_p}picpos_shell/picpos_returns_panel.dart',
  '${_p}picpos_shell/picpos_return_form_kit.dart',
  '${_p}picpos_shell/picpos_status_board.dart',
  '${_p}picpos_shell/picpos_stat_tile.dart',
  '${_p}print_test_picpos/screens/print_test_picpos_screen.dart',
  '${_p}print_test_picpos/widgets/sheet_preview_view.dart',
  '${_p}products/widgets/product_card.dart',
  '${_p}products/widgets/product_list_tile.dart',
  '${_p}products_picpos/widgets/products_table_picpos.dart',
  '${_p}purchases_picpos/screens/purchases_filter_bar.dart',
  '${_p}purchases_picpos/screens/purchases_picpos_screen.dart',
  '${_p}purchases_picpos/screens/purchases_totals_bar.dart',
  '${_p}purchase_returns_picpos/screens/purchase_returns_picpos_screen.dart',
  '${_p}reports_picpos/screens/reports_picpos_dialogs.dart',
  '${_p}reports_picpos/screens/report_definitions_picpos.dart',
  '${_p}report_builder_picpos/screens/report_builder_picpos_screen.dart',
  '${_p}sales_invoices_picpos/screens/sales_filter_bar.dart',
  '${_p}sales_invoices_picpos/screens/sales_invoice_save_edit.dart',
  '${_p}sales_invoices_picpos/screens/sales_summary_cards.dart',
  '${_p}settings/widgets/settings_widgets.dart',
  '${_p}settings_picpos/screens/cheques_picpos_screen.dart',
  '${_p}shared_widgets/dashboard_widgets.dart',
  '${_p}shared_widgets/form_components.dart',
  '${_p}shared_widgets/whatsapp_send_dialog.dart',
  '${_p}shift_close_picpos/screens/shift_close_picpos_screen.dart',
  '${_p}shift_close_picpos/widgets/picpos_cashier_closing_dialog.dart',
  '${_p}shift_close_picpos/widgets/picpos_opening_balance_dialog.dart',
  '${_p}tables_picpos/screens/tables_picpos_screen.dart',
  '${_p}tables_picpos/widgets/guest_requests_banner.dart',
  '${_p}tables_picpos/widgets/table_bill_qr_dialog.dart',
  '${_p}tables_picpos/widgets/table_session_pin_card.dart',
  '${_p}treasury/widgets/daily_closing_dialog.dart',
  '${_p}treasury/widgets/receipt_voucher_dialog.dart',
  '${_p}treasury/widgets/treasury_bank_tab.dart',
  '${_p}treasury/widgets/treasury_cash_tab.dart',
  '${_p}treasury/widgets/treasury_closing_tab.dart',
  '${_p}treasury/widgets/treasury_safe_card.dart',
  '${_p}treasury/widgets/treasury_transactions_list.dart',
  '${_p}treasury_picpos/screens/cheque_books_picpos_screen.dart',
  '${_p}treasury_picpos/widgets/payment_voucher_dialog_picpos.dart',
  '${_p}treasury_picpos/widgets/receipt_voucher_dialog_picpos.dart',
  '${_p}treasury_picpos/widgets/treasury_actions_grid_picpos.dart',
  '${_p}treasury_picpos/widgets/treasury_metrics_panel_picpos.dart',
  '${_p}treasury_picpos/widgets/treasury_panes_picpos.dart',
  '${_p}treasury_picpos/widgets/treasury_safe_card_picpos.dart',
  '${_p}treasury_picpos/widgets/treasury_tab_bar_picpos.dart',
  '${_p}users_picpos/screens/users_management_picpos_screen.dart',
  '${_p}widgets/any_permission_masked_text.dart',
  '${_p}widgets/app_empty_state.dart',
  '${_p}widgets/common_widgets.dart',
  '${_p}widgets/field_audit_history_widget.dart',
  '${_p}widgets/fiscal_year_gate_dialog.dart',
  '${_p}widgets/mirror_badge.dart',
  '${_p}widgets/permission_guard.dart',
  '${_p}widgets/searchable_dropdown.dart',
  '${_p}widgets/searchable_unit_selection_dialog.dart',
  '${_p}widgets/summary_card.dart',
  '${_p}widgets/sync_management_dialog.dart',
  '${_p}widgets/sync_status_badge.dart',
  '${_p}widgets/user_language_selector.dart',
  '${_p}widgets/auth/security_gate_wrapper.dart',
  '${_p}widgets/auth/session_timeout_wrapper.dart',
  '${_p}widgets/common/app_data_table.dart',
  '${_p}widgets/dialogs/add_product_dialog.dart',
  '${_p}widgets/dialogs/app_confirm_dialog.dart',
  '${_p}widgets/dialogs/force_change_password_dialog.dart',
  '${_p}widgets/notifications/notification_bell.dart',
  '${_p}widgets/settings/activation_dialog.dart',
  '${_p}widgets/settings/backup_settings_widget.dart',
  '${_p}widgets/settings/cheque_receipt_drift_admin_dialog.dart',
  '${_p}widgets/settings/company_info_widget_io.dart',
  '${_p}widgets/settings/database_settings_widget.dart',
  '${_p}widgets/settings/fingerprint_settings_widget.dart',
  '${_p}widgets/settings/hardware_settings_widget.dart',
  '${_p}widgets/settings/kds_settings_widget.dart',
  '${_p}widgets/settings/lan_transport_section.dart',
  '${_p}widgets/settings/mirror_pairing_dialog.dart',
  '${_p}widgets/settings/modifier_management_widget.dart',
  '${_p}widgets/settings/permissions_management_widget.dart',
  '${_p}widgets/settings/pos_settings_widget_design.dart',
  '${_p}widgets/settings/pos_settings_widget_main_section.dart',
  '${_p}widgets/settings/pos_settings_widget_other_sections.dart',
  '${_p}widgets/settings/receipt_settings_widget.dart',
  '${_p}widgets/settings/settings_permission_tiles.dart',
  '${_p}widgets/settings/user_management_widget.dart',
  '${_p}widgets/touch_keyboard/touch_keyboard_key.dart',
];

// أسطرٌ تبقى بثابت AppColors عمداً (لا context: خرائط/دوال بلا سياق، أو فرع
// داكن/فاتح صريح).
const _allowedConst = <String>[
  'const _idle = AppColors.textMuted;',
  'neutral ?? AppColors.textMuted',
  'isDark ? AppColors.borderDark : AppColors.border',
  'tint: AppColors.textPrimary);',
  "'cancelled': (tr('ملغى'), AppColors.textMuted),",
];

final _themes = <String, ThemeData Function()>{
  'light': () => PicPosTheme.lightTheme,
  'dark': () => PicPosTheme.darkTheme,
};

/// المضيف الذي يستورد ملفاً: هو نفسه، أو أبوه إن كان `part of`.
String _host(String f) {
  final src = File(f).readAsStringSync();
  final m = RegExp(r"^part of '([^']+)';", multiLine: true).firstMatch(src);
  if (m == null) return f;
  final dir = f.substring(0, f.lastIndexOf('/') + 1);
  return '$dir${m.group(1)}';
}

void main() {
  for (final entry in _themes.entries) {
    testWidgets('أدوار النص على أرضيات الملفات (${entry.key})', (tester) async {
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
          if (r < min) {
            failures.add('${fg.key} on ${bg.key}: ${r.toStringAsFixed(2)}');
          }
        }
      }
      expect(failures, isEmpty, reason: failures.join('\n'));
      expect(ctx.picposHairline, isNot(theme.cardColor));
    });

    testWidgets('readableOn لألوان الحالة المعروضة نصاً ≥4.5 (${entry.key})',
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
      final failures = <String>[];
      for (final e in {
        'success': AppColors.success,
        'warning': AppColors.warning,
        'error': AppColors.error,
        'info': AppColors.info,
        'primary': AppColors.primary,
      }.entries) {
        final r = contrastRatio(readableOn(ctx, e.value), theme.cardColor);
        if (r < 4.5) failures.add('${e.key}: ${r.toStringAsFixed(2)}');
      }
      expect(failures, isEmpty, reason: failures.join('\n'));
    });
  }

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

  test('كل ملف يستخدم context.picpos* يستورد picpos_surface (أو أبوه للـpart)',
      () {
    final offenders = <String>[];
    for (final f in _files) {
      if (!File(f).readAsStringSync().contains('context.picpos')) continue;
      if (!File(_host(f)).readAsStringSync().contains('picpos_surface.dart')) {
        offenders.add(f);
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('كل ملف يستخدم readableOn يستورد readable_colors (أو أبوه للـpart)', () {
    final offenders = <String>[];
    for (final f in _files) {
      if (!File(f).readAsStringSync().contains('readableOn(')) continue;
      if (!File(_host(f)).readAsStringSync().contains('readable_colors.dart')) {
        offenders.add(f);
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}