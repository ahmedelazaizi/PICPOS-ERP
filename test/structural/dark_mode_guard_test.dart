// Structural dark-mode guard for presentation literals.
//
// The audit intentionally checks only literals in surface and text positions:
// white/light fills and backgrounds, plus black/dark TextStyle ink. White
// foregrounds on brand/status surfaces and paper-like preview canvases are
// valid and are documented below or marked inline with `// dark-ok:`.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Intentional white foregrounds or paper-like canvases. These files are
/// reviewed as a unit because their white literals are part of a single
/// colored/status/print visual system, not application surfaces.
const _allowlistedFiles = <String, String>{
  'lib/presentation/kitchen/screens/kitchen_display_screen.dart':
      'KDS cards use status colors with white foregrounds.',
  'lib/presentation/kitchen/screens/kds_stats_screen.dart':
      'KDS statistics use a dark status canvas with white foregrounds.',
  'lib/presentation/treasury_picpos/widgets/treasury_metrics_panel_picpos.dart':
      'Treasury metric cards use status/gradient backgrounds.',
  'lib/presentation/treasury/widgets/treasury_metrics_panel.dart':
      'Treasury metric cards use status/gradient backgrounds.',
  'lib/presentation/sales_invoices_picpos/screens/sales_summary_cards.dart':
      'Sales summary cards use status/gradient backgrounds.',
  'lib/presentation/shell/nav_widgets.dart':
      'Navigation rail uses the brand-colored shell background.',
  'lib/presentation/shell/report_category_nav.dart':
      'Report navigation uses the brand-colored shell background.',
  'lib/presentation/pos/widgets/pos_header.dart':
      'POS header uses the brand-colored header background.',
  'lib/presentation/pos_picpos/widgets/picpos_top_bar.dart':
      'PicPos top bar uses the brand-colored header background.',
  'lib/presentation/pos_picpos/screens/picpos_pos_operations.dart':
      'POS operation actions use brand/status button backgrounds.',
  'lib/presentation/pos/screens/pos_main_operations.dart':
      'POS operation actions use brand/status button backgrounds.',
  'lib/presentation/pos/screens/table_pos_dialogs.dart':
      'Table status dialog uses status-colored surfaces.',
  'lib/presentation/pos/widgets/modifier_selection_dialog.dart':
      'Modifier status cards use colored backgrounds.',
  'lib/presentation/widgets/activity_timeline.dart':
      'Timeline status nodes use status-colored surfaces.',
  'lib/presentation/print_test_picpos/widgets/sheet_preview_view.dart':
      'Preview canvas intentionally represents printed paper.',
  'lib/presentation/template_library_picpos/widgets/template_thumbnail_view.dart':
      'Template thumbnail intentionally represents printed paper.',
  'lib/presentation/activity_log_picpos/screens/activity_log_filters_picpos.dart':
      'Selected filter controls sit on the colored activity toolbar.',
  'lib/presentation/purchases_picpos/screens/purchases_picpos_screen.dart':
      'Batch action controls use an intentionally inverted colored toolbar.',
  'lib/presentation/sales_invoices_picpos/screens/sales_batch_action_bar.dart':
      'Batch action controls use an intentionally inverted colored toolbar.',
  'lib/presentation/screens/account_mapping_settings_screen.dart':
      'Header count and controls sit on the brand-colored header.',
  'lib/presentation/screens/activity_log/activity_log_filters.dart':
      'Selected filter controls sit on the colored activity toolbar.',
  'lib/presentation/screens/invoice_designer/invoice_designer_canvas.dart':
      'Designer canvas represents printable paper.',
  'lib/presentation/screens/invoice_designer/invoice_designer_templates.dart':
      'Template thumbnails represent printable paper.',
  'lib/presentation/screens/invoice_designer/invoice_preview_dialog.dart':
      'Preview dialog represents printable paper.',
  'lib/presentation/settings_picpos/widgets/quick_sale_cashier_preview.dart':
      'Cashier preview intentionally models the POS display surface.',
  'lib/presentation/settings_picpos/widgets/quick_sale_display_preview.dart':
      'Customer display preview intentionally models its display surface.',
  'lib/presentation/screens/login_screen.dart':
      'Login branding intentionally uses white logo and action surfaces.',
  'lib/presentation/shell/app_shell.dart':
      'Application shell uses the brand-colored navigation surfaces.',
  'lib/presentation/template_editor_picpos/widgets/editor_canvas.dart':
      'Template editor canvas intentionally represents printable paper.',
  'lib/presentation/treasury/widgets/safe_management_dialog.dart':
      'Safe-management actions use semantic colored button surfaces.',
  'lib/presentation/widgets/invoice_safety_guards.dart':
      'Confirmation action uses a semantic warning button surface.',
  'lib/presentation/widgets/notifications/notification_bell.dart':
      'Notification count is white foreground on an error badge.',
  'lib/presentation/widgets/settings/company_info_widget_web.dart':
      'Logo picker canvas intentionally represents an image/paper surface.',
  'lib/presentation/screens/dashboard_screen.dart':
      'Branch-scope badge is a semantic warning/status surface.',
  'lib/presentation/screens/help_center_screen.dart':
      'Help cards use intentionally branded informational surfaces.',
  'lib/presentation/screens/invoice_designer/invoice_designer_toolbar.dart':
      'Designer toolbar contains printable-paper controls and swatches.',
  'lib/presentation/screens/invoice_designer/invoice_designer_ui.dart':
      'Designer controls render printable-paper previews.',
  'lib/presentation/screens/invoice_designer/invoice_section_editor.dart':
      'Section editor contains printable-paper preview surfaces.',
  'lib/presentation/screens/journal_entries_screen.dart':
      'Journal action/table controls use semantic status surfaces.',
  'lib/presentation/screens/journal_entry_widgets.dart':
      'Journal autocomplete/table surfaces are semantic controls.',
  'lib/presentation/screens/manufacturing_screen.dart':
      'Manufacturing status controls use semantic action surfaces.',
  'lib/presentation/screens/opex_categories_tab.dart':
      'Operating-expense status controls use semantic action surfaces.',
  'lib/presentation/screens/opex_expenses_tab.dart':
      'Operating-expense status controls use semantic action surfaces.',
  'lib/presentation/screens/purchase_returns/return_details_panel.dart':
      'Return detail status/table controls use semantic surfaces.',
  'lib/presentation/screens/reports/ar_aging_report_screen.dart':
      'Aging report status cells use semantic status surfaces.',
  'lib/presentation/screens/reports/inventory_report_screen.dart':
      'Inventory report status cells use semantic status surfaces.',
  'lib/presentation/screens/reports/top_products_report_screen.dart':
      'Report ranking/status cells use semantic status surfaces.',
  'lib/presentation/screens/reports/vat_reconciliation_screen.dart':
      'VAT reconciliation status cells use semantic status surfaces.',
  'lib/presentation/screens/sales_returns/return_details_panel.dart':
      'Return detail status/table controls use semantic surfaces.',
  'lib/presentation/screens/scale_plu/scale_panels.dart':
      'Scale CSV/table panel is a data-preview surface.',
  'lib/presentation/screens/settings/widgets/add_user_dialog.dart':
      'User-management action controls use semantic surfaces.',
  'lib/presentation/screens/settings/widgets/reset_password_dialog.dart':
      'Password-reset action controls use semantic surfaces.',
  'lib/presentation/screens/settings/widgets/security_alerts_panel.dart':
      'Security alerts use semantic status surfaces.',
  'lib/presentation/screens/settings_screen.dart':
      'Settings action controls use semantic status surfaces.',
  'lib/presentation/screens/tables/split_table_dialog.dart':
      'Table split status controls use semantic surfaces.',
  'lib/presentation/screens/widgets/manufacturing/bom_tab.dart':
      'BOM status/table controls use semantic surfaces.',
  'lib/presentation/screens/widgets/manufacturing/production_orders_tab.dart':
      'Production status/table controls use semantic surfaces.',
  'lib/presentation/settings_picpos/screens/settings_picpos_screen.dart':
      'Settings preview/action controls use semantic surfaces.',
  'lib/presentation/settings_picpos/screens/settings_picpos_about.dart':
      'Settings preview/action controls use semantic surfaces.',
};

final _lightLiteral = RegExp(
  r'(?:Colors\.white(?!\.)\b|Color\(0xFFFFFFFF\)|Colors\.grey\.shade(?:50|100|200)\b)',
);
final _hexLiteral = RegExp(r'Color\(0xFF([0-9A-Fa-f]{6})\)');
final _surfaceProperty = RegExp(
  r'\b(?:backgroundColor|fillColor|tileColor)\s*:',
);
final _surfaceWidget = RegExp(
  r'\b(?:Container|Card|Material|Dialog|DataTable|InputDecoration|BoxDecoration|DecoratedBox|ColoredBox)\b',
);
final _textStyleStart = RegExp(r'\b(?:TextStyle|GoogleFonts\.\w+)\s*\(');

Iterable<File> _dartFilesUnder(String root) sync* {
  final directory = Directory(root);
  if (!directory.existsSync()) return;
  for (final entity in directory.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) yield entity;
  }
}

String _relativePath(File file) =>
    file.path.replaceAll(r'\', '/').replaceFirst(RegExp(r'^\.*/'), '');

bool _hasLightLiteral(String line) {
  if (_lightLiteral.hasMatch(line)) return true;
  for (final match in _hexLiteral.allMatches(line)) {
    final rgb = int.parse(match.group(1)!, radix: 16);
    final red = (rgb >> 16) & 0xFF;
    final green = (rgb >> 8) & 0xFF;
    final blue = rgb & 0xFF;
    if (red >= 0xD8 && green >= 0xD8 && blue >= 0xD8) return true;
  }
  return false;
}

bool _hasMarker(List<String> lines, int index) {
  final start = index > 2 ? index - 2 : 0;
  final end = index + 1 < lines.length ? index + 1 : lines.length;
  return lines.sublist(start, end).any((line) => line.contains('dark-ok:'));
}

bool _isSurfaceLiteral(List<String> lines, int index) {
  final line = lines[index];
  if (line.contains('.withValues')) return false;
  if (line.contains('isDark ?') || line.contains('brightness ==')) return false;
  final start = index > 7 ? index - 7 : 0;
  final end = index + 5 < lines.length ? index + 5 : lines.length;
  final context = lines.sublist(start, end).join('\n');
  if (_surfaceProperty.hasMatch(line) &&
      context.contains('foregroundColor:') &&
      RegExp(r'\b(?:Button|Chip|styleFrom)\b').hasMatch(context)) {
    return false;
  }
  if (_surfaceProperty.hasMatch(line)) return true;
  if (!line.contains('color:') || line.contains('border:')) return false;
  final isDecoration = context.contains('BoxDecoration(') ||
      RegExp(r'\b(?:Container|Card|Material|TableRow)\s*\([^\n]*color:')
          .hasMatch(line);
  if (!isDecoration || !_surfaceWidget.hasMatch(context)) return false;
  return !RegExp(r'\b(?:TextStyle|Icon|CircularProgressIndicator|AlwaysStoppedAnimation)\b')
      .hasMatch(context);
}

bool _hasDarkTextLiteral(String line) {
  if (RegExp(r'Colors\.(?:black|black87|black54)\b').hasMatch(line)) {
    return true;
  }
  for (final match in _hexLiteral.allMatches(line)) {
    final rgb = int.parse(match.group(1)!, radix: 16);
    final red = (rgb >> 16) & 0xFF;
    final green = (rgb >> 8) & 0xFF;
    final blue = rgb & 0xFF;
    if (red <= 0x80 && green <= 0x80 && blue <= 0x80) return true;
  }
  return false;
}

bool _isDarkTextLiteral(List<String> lines, int index) {
  final start = index > 8 ? index - 8 : 0;
  final end = index + 5 < lines.length ? index + 5 : lines.length;
  final context = lines.sublist(start, end).join('\n');
  return _hasDarkTextLiteral(lines[index]) &&
      _textStyleStart.hasMatch(context) &&
      lines[index].contains('color:');
}

void main() {
  test('presentation surfaces and text use theme-aware colors', () {
    final offenders = <String>[];
    var scannedSites = 0;

    for (final file in _dartFilesUnder('lib/presentation')) {
      final relative = _relativePath(file);
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index];
        if (!_hasLightLiteral(line) && !_hasDarkTextLiteral(line)) {
          continue;
        }
        if (_hasMarker(lines, index)) continue;
        if (_allowlistedFiles.containsKey(relative)) continue;

        final isSurface = _hasLightLiteral(line) &&
            _isSurfaceLiteral(lines, index);
        final isDarkText =
            _hasDarkTextLiteral(line) && _isDarkTextLiteral(lines, index);
        if (isSurface || isDarkText) {
          scannedSites++;
          offenders.add('$relative:${index + 1}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Found $scannedSites unallowlisted dark-mode sites. Replace the '
          'literal with a ColorScheme/picpos surface or text role. Intentional '
          'colored foregrounds need a documented file allowlist entry or a '
          'nearby `// dark-ok: <reason>` marker. Sites:\n'
          '${offenders.join('\n')}',
    );
  });

  test('allowlist entries document an intentional reason', () {
    expect(_allowlistedFiles, isNotEmpty);
    for (final entry in _allowlistedFiles.entries) {
      expect(entry.key, startsWith('lib/presentation/'));
      expect(File(entry.key).existsSync(), isTrue,
          reason: 'Allowlist file disappeared: ${entry.key}');
      expect(entry.value.trim(), isNotEmpty);
    }
  });
}
