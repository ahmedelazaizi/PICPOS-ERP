// تباين أدوار الثيم في الكاشير والإعدادات والشل (بند 14، الجولة 6، دفعة A) + حارس
// بنيوي: استُبدلت ثوابت AppColors.text*/surface/border بأدوار context.picpos*
// وfontSize ≤ 10 ← 11 في الملفات أدناه.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/theme/app_colors.dart';
import 'package:picpos_erp/core/theme/picpos_theme.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_surface.dart';

import 'settings_picpos_theme_contrast_test.dart' show contrastRatio;

const _files = <String>[
  'lib/presentation/pos/dialogs/invoice_lookup_dialog.dart',
  'lib/presentation/pos/dialogs/unit_selection_dialog.dart',
  'lib/presentation/pos/dialogs/weight_input_dialog.dart',
  'lib/presentation/pos/screens/pos_main_screen.dart',
  'lib/presentation/pos/screens/table_pos_dialogs.dart',
  'lib/presentation/pos/widgets/cart/cart_delivery_panel.dart',
  'lib/presentation/pos/widgets/cart/cart_discount_dialog.dart',
  'lib/presentation/pos/widgets/cart/cart_payment_selector.dart',
  'lib/presentation/pos/widgets/cart/cart_totals_panel.dart',
  'lib/presentation/pos/widgets/cart/total_row.dart',
  'lib/presentation/pos/widgets/cart_auto_scroll.dart',
  'lib/presentation/pos/widgets/cart_item_modifier_panel.dart',
  'lib/presentation/pos/widgets/cart_item_tile.dart',
  'lib/presentation/pos/widgets/cart_view.dart',
  'lib/presentation/pos/widgets/cart_widgets.dart',
  'lib/presentation/pos/widgets/customer_selector_v2.dart',
  'lib/presentation/pos/widgets/header/pos_low_stock_indicator.dart',
  'lib/presentation/pos/widgets/header/pos_notification_bell.dart',
  'lib/presentation/pos/widgets/held_orders_dialog.dart',
  'lib/presentation/pos/widgets/modifier_selection_dialog.dart',
  'lib/presentation/pos/widgets/payment_sheet.dart',
  'lib/presentation/pos/widgets/pos_cart_panel.dart',
  'lib/presentation/pos/widgets/pos_cash_tendering_dialog.dart',
  'lib/presentation/pos/widgets/pos_deleted_items_dialog.dart',
  'lib/presentation/pos/widgets/pos_edit_invoice_dialog.dart',
  'lib/presentation/pos/widgets/pos_header.dart',
  'lib/presentation/pos/widgets/pos_invoice_items_view.dart',
  'lib/presentation/pos/widgets/pos_offers_dialog.dart',
  'lib/presentation/pos/widgets/pos_opening_balance_dialog.dart',
  'lib/presentation/pos/widgets/pos_payment_dialogs.dart',
  'lib/presentation/pos/widgets/pos_previous_expenses_dialog.dart',
  'lib/presentation/pos/widgets/pos_product_search_field.dart',
  'lib/presentation/pos/widgets/pos_scale_input.dart',
  'lib/presentation/pos/widgets/product_card.dart',
  'lib/presentation/pos/widgets/product_card_shimmer.dart',
  'lib/presentation/pos/widgets/product_grid.dart',
  'lib/presentation/pos/widgets/product_pricing_inquiry.dart',
  'lib/presentation/pos/widgets/table_pos/table_pos_cart_item.dart',
  'lib/presentation/pos/widgets/table_pos/table_pos_header.dart',
  'lib/presentation/pos/widgets/table_pos/table_pos_summary.dart',
  'lib/presentation/pos_picpos/screens/picpos_pos_checkout_support.dart',
  'lib/presentation/pos_picpos/screens/picpos_pos_quick_return_lines_editor_dialog.dart',
  'lib/presentation/pos_picpos/screens/picpos_pos_screen.dart',
  'lib/presentation/pos_picpos/widgets/picpos_exchange_mode_banner.dart',
  'lib/presentation/pos_picpos/widgets/picpos_invoice_header.dart',
  'lib/presentation/pos_picpos/widgets/picpos_items_table.dart',
  'lib/presentation/pos_picpos/widgets/picpos_last_invoice_dialog.dart',
  'lib/presentation/pos_picpos/widgets/picpos_one_time_customer.dart',
  'lib/presentation/pos_picpos/widgets/picpos_payment_panel.dart',
  'lib/presentation/pos_picpos/widgets/picpos_pos_text.dart',
  'lib/presentation/pos_picpos/widgets/picpos_return_line_style.dart',
  'lib/presentation/pos_picpos/widgets/picpos_switch_user_dialog.dart',
  'lib/presentation/screens/developer_tools_screen.dart',
  'lib/presentation/settings_picpos/screens/admin_home_settings_picpos.dart',
  'lib/presentation/settings_picpos/screens/branches_picpos_screen.dart',
  'lib/presentation/settings_picpos/screens/cheques_picpos_deposit_dialog.dart',
  'lib/presentation/settings_picpos/screens/cheques_picpos_endorse_dialog.dart',
  'lib/presentation/settings_picpos/screens/cheques_picpos_screen.dart',
  'lib/presentation/settings_picpos/screens/distribution_picpos_screen.dart',
  'lib/presentation/settings_picpos/screens/general_settings_widgets_picpos.dart',
  'lib/presentation/settings_picpos/screens/guest_services_settings_picpos.dart',
  'lib/presentation/settings_picpos/screens/quick_sale_policy_screen_picpos.dart',
  'lib/presentation/settings_picpos/screens/settings_picpos_about.dart',
  'lib/presentation/settings_picpos/screens/settings_picpos_navigation.dart',
  'lib/presentation/settings_picpos/screens/settings_picpos_sections_core.dart',
  'lib/presentation/settings_picpos/screens/settings_picpos_support.dart',
  'lib/presentation/settings_picpos/widgets/permissions_matrix_picpos.dart',
  'lib/presentation/settings_picpos/widgets/quick_sale_cashier_preview.dart',
  'lib/presentation/settings_picpos/widgets/quick_sale_display_preview.dart',
  'lib/presentation/settings_picpos/widgets/quick_sale_settings_chrome.dart',
  'lib/presentation/settings_picpos/widgets/settings_blocks.dart',
  'lib/presentation/settings_picpos/widgets/settings_nav_rail.dart',
  'lib/presentation/settings_picpos/widgets/web_access_settings_panel.dart',
  'lib/presentation/shell/app_shell.dart',
  'lib/presentation/shell/nav_widgets.dart',
  'lib/presentation/shell/screen_breadcrumbs.dart',
  'lib/presentation/shell/screen_tabs_bar.dart',
];

// سطر حالة «ملغى» في خريطة عامة بلا context — يبقى ثابتاً عمداً.
const _allowedStatic = <String>{
  'lib/presentation/settings_picpos/screens/cheques_picpos_screen.dart',
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
        if (_allowedStatic.contains(f) && lines[i].contains("'cancelled'")) {
          continue;
        }
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
      final src = File(f)
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      if (src.contains('context.picpos') &&
          !RegExp(r'^part of', multiLine: true).hasMatch(src) &&
          !has(f)) {
        missing.add(f);
      }
    }
      expect(missing, isEmpty, reason: missing.join('\n'));
  });
}
