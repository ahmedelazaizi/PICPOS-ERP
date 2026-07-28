// Spec D4-001 phase-1 — grep guard: presentation must not import data/database
// directly (Constitution §IV — layered architecture).
//
// 69 existing offenders are allowlisted as a frozen baseline. The phase-2
// migration that walks each one and replaces with a repository call is its
// own future spec.
//
// This phase-1 guard ONLY prevents new offenders from being introduced. If a
// new file under lib/presentation/ adds `import '...data/database/...'`, this
// test fails in CI with the file path + remediation guidance.
//
// To remove a file from the allowlist (i.e. you migrated it through the
// repository layer), delete its entry from `_allowlist` below and re-run the
// test — the assertion confirms the migration is complete and the test now
// pins it that way going forward.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Presentation → data/database import guard (D4-001 phase-1)', () {
    // FROZEN BASELINE captured 2026-05-15. To remove an entry, complete the
    // repository-layer migration for that file then delete its line.
    //
    // To add new offenders to this list is FORBIDDEN — write the screen/widget
    // against a domain Repository instead and inject via Riverpod provider.
    final allowlist = <String>{
      'lib/presentation/pos/dialogs/edit_cart_item_dialog.dart',
      'lib/presentation/pos/dialogs/unit_selection_dialog.dart',
      'lib/presentation/pos/dialogs/weight_input_dialog.dart',
      'lib/presentation/pos/providers/pos_closing_controller.dart',
      'lib/presentation/pos/providers/pos_search_controller.dart',
      'lib/presentation/pos/widgets/cart/cart_payment_selector.dart',
      'lib/presentation/pos/widgets/modifier_selection_dialog.dart',
      'lib/presentation/pos/widgets/pos_barcode_input.dart',
      'lib/presentation/products/providers/categories_controller.dart',
      'lib/presentation/products/providers/products_controller.dart',
      'lib/presentation/products/widgets/product_card.dart',
      'lib/presentation/products/widgets/product_list_tile.dart',
      'lib/presentation/screens/coa/coa_tree_node.dart',
      'lib/presentation/screens/commercial_papers/widgets/create_paper_dialog.dart',
      'lib/presentation/screens/commercial_papers/widgets/deposit_for_collection_dialog.dart',
      'lib/presentation/screens/commercial_papers/widgets/endorse_paper_dialog.dart',
      'lib/presentation/screens/commercial_papers/widgets/partial_collection_dialog.dart',
      'lib/presentation/screens/commercial_papers/widgets/reissue_paper_dialog.dart',
      'lib/presentation/screens/commercial_papers/widgets/status_change_dialog.dart',
      'lib/presentation/screens/commercial_papers_screen.dart',
      'lib/presentation/screens/cost_centers_screen.dart',
      'lib/presentation/screens/create_journal_template_dialog.dart',
      'lib/presentation/screens/cycle_count/cycle_count_controller.dart',
      'lib/presentation/screens/cycle_count_screen.dart',
      // TODO(D4-001 phase-2): fork mirrors the allowlisted cycle_count_screen.dart;
      // migrate both off data/database together.
      'lib/presentation/cycle_count_picpos/screens/cycle_count_picpos_screen.dart',
      'lib/presentation/screens/enhanced_role_management_screen.dart',
      'lib/presentation/screens/inventory/widgets/inventory_filters_bar.dart',
      'lib/presentation/screens/invoice_designer/invoice_designer_canvas.dart',
      'lib/presentation/screens/invoice_designer/invoice_designer_properties.dart',
      'lib/presentation/screens/invoice_designer/invoice_designer_toolbar.dart',
      'lib/presentation/screens/invoice_designer/invoice_preview_dialog.dart',
      'lib/presentation/screens/invoice_designer/invoice_section_editor.dart',
      'lib/presentation/screens/invoice_designer_screen.dart',
      'lib/presentation/screens/landed_cost/landed_cost_controller.dart',
      'lib/presentation/screens/landed_cost_screen.dart',
      'lib/presentation/screens/parties/party_dialogs.dart',
      'lib/presentation/screens/parties/party_groups_tab.dart',
      'lib/presentation/screens/providers/distribution_controller.dart',
      'lib/presentation/screens/providers/plu_manager_controller.dart',
      'lib/presentation/screens/purchase_invoices/widgets/purchase_invoice_form.dart',
      'lib/presentation/screens/reports/ar_aging_report_screen.dart',
      'lib/presentation/screens/reports/financial_statements_screen.dart',
      'lib/presentation/screens/reports/vat_reconciliation_screen.dart',
      'lib/presentation/screens/role_management/widgets/permissions_panel.dart',
      'lib/presentation/screens/role_management/widgets/role_list_panel.dart',
      // TODO(spec): migrate through a repository
      'lib/presentation/screens/sales_invoices_screen.dart',
      // TODO(D4-001 phase-2): fork mirrors the allowlisted sales_invoices_screen.dart;
      // migrate both off data/database/sync_interceptor together.
      'lib/presentation/sales_invoices_picpos/screens/sales_invoices_picpos_screen.dart',
      'lib/presentation/screens/settings/widgets/add_role_dialog.dart',
      'lib/presentation/screens/settings/widgets/add_user_dialog.dart',
      // TODO(spec): migrate through a repository
      'lib/presentation/screens/settings/widgets/server_perms_toggle_dialog.dart',
      'lib/presentation/screens/setup_wizard_screen.dart',
      'lib/presentation/screens/tables/floor_plan_designer.dart',
      'lib/presentation/screens/tables/merge_table_dialog.dart',
      'lib/presentation/screens/tables/qr_menu_dialog.dart',
      'lib/presentation/screens/tables/split_table_dialog.dart',
      'lib/presentation/screens/tables/table_card_widget.dart',
      'lib/presentation/screens/tables/table_order_dialog.dart',
      'lib/presentation/screens/tables/transfer_dialog.dart',
      'lib/presentation/screens/tables/widgets/table_card.dart',
      'lib/presentation/screens/tables/widgets/table_order_panel.dart',
      'lib/presentation/screens/tables/widgets/tables_top_bar.dart',
      'lib/presentation/screens/widgets/dialogs/opex_category_edit_dialog.dart',
      'lib/presentation/screens/widgets/dialogs/region_edit_dialog.dart',
      'lib/presentation/shell/app_shell.dart',
      'lib/presentation/treasury/widgets/treasury_bank_tab.dart',
      'lib/presentation/treasury/widgets/treasury_cash_tab.dart',
      'lib/presentation/treasury/widgets/treasury_closing_tab.dart',
      'lib/presentation/treasury/widgets/treasury_safe_card.dart',
      'lib/presentation/widgets/activity_timeline.dart',
      'lib/presentation/widgets/category_card.dart',
      'lib/presentation/widgets/field_audit_viewer.dart',
      'lib/presentation/widgets/searchable_unit_selection_dialog.dart',
      'lib/presentation/widgets/settings/branch_scope_admin_dialog.dart',
      'lib/presentation/widgets/settings/database_settings_widget.dart',
    };

    test('no NEW presentation file imports data/database directly', () {
      final dir = Directory('lib/presentation');
      expect(dir.existsSync(), isTrue,
          reason: 'lib/presentation/ must exist (run from repo root)');

      final newOffenders = <String>[];
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.dart')) continue;
        final relPath =
            entity.path.replaceAll('\\', '/').replaceFirst(RegExp(r'^\./'), '');
        final content = entity.readAsStringSync();
        // Match lines like `import '../../data/database/...'`
        final importsDb =
            RegExp(r'''^import\s+['\"](?:\.\.\/)+data\/database\b''',
                multiLine: true);
        if (importsDb.hasMatch(content) && !allowlist.contains(relPath)) {
          newOffenders.add(relPath);
        }
      }

      expect(
        newOffenders,
        isEmpty,
        reason:
            'D4-001 / Constitution §IV: presentation must not import '
            'data/database directly. New offenders MUST go through a '
            'domain Repository (lib/data/repositories/) injected via a '
            'Riverpod provider.\n\nNew offenders:\n'
            '${newOffenders.join("\n")}\n\n'
            'Either: (1) refactor the new file to use a Repository, OR '
            '(2) for an emergency cherry-pick, add the file path to '
            'allowlist in test/unit/presentation_db_import_guard_test.dart '
            'with a TODO comment naming the spec that will migrate it.',
      );
    });

    test('allowlist entries still exist (catches stale entries)', () {
      final missing = <String>[];
      for (final p in allowlist) {
        if (!File(p).existsSync()) missing.add(p);
      }
      expect(
        missing,
        isEmpty,
        reason:
            'These allowlist entries no longer exist on disk — remove them '
            'from the allowlist:\n${missing.join("\n")}',
      );
    });
  });
}
