// Feature 017 / FR-005 — Region-filter wiring guard.
//
// Every BranchWarehouseFilterBar usage under lib/presentation/screens/reports/
// MUST also pass `selectedRegionId:` (and the matching `onRegionChanged:`).
// The treasury bug (Issue 8 → 014) was: the filter bar was rendered with no
// `selectedRegionId`, so the dropdown looked wired but the screen state never
// captured the value → silent no-op → wrong report scope. Feature 017 swept
// the report screens; this test prevents the regression coming back in any
// future report screen the team adds.
//
// Feature 058 / FR-013, FR-014 — Active-branch initializer guard (second
// group below). Every in-scope launcher-destination report screen MUST seed
// _selectedBranchId (or the documented field-name variant) from
// activeBranchIdProvider inside its initState. Fields-only changes that drop
// the seed are caught by the inline-list assertion.
//
// Both tests are purely lexical (file scan) — no app state needed.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Report screens wire region filter (Feature 017 / FR-005)', () {
    final reportsDir = Directory('lib/presentation/screens/reports');

    test('reports directory exists', () {
      expect(reportsDir.existsSync(), isTrue,
          reason: 'expected reports/ directory at ${reportsDir.path}');
    });

    final dartFiles = reportsDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    for (final file in dartFiles) {
      final source = file.readAsStringSync();

      // Skip files that don't use the shared filter bar at all.
      if (!source.contains('BranchWarehouseFilterBar(')) continue;

      // Each constructor invocation must include selectedRegionId AND
      // onRegionChanged. We scan the source per invocation block — the
      // simplest robust approach is: count call sites and assert that
      // the parameter names appear at least that many times each.
      final callSites = RegExp(r'BranchWarehouseFilterBar\(')
          .allMatches(source)
          .length;
      final selectedRegionHits = RegExp(r'selectedRegionId\s*:')
          .allMatches(source)
          .length;
      final onRegionChangedHits = RegExp(r'onRegionChanged\s*:')
          .allMatches(source)
          .length;

      test('${file.path}: every BranchWarehouseFilterBar passes selectedRegionId',
          () {
        expect(
          selectedRegionHits,
          greaterThanOrEqualTo(callSites),
          reason: '${file.path} has $callSites BranchWarehouseFilterBar '
              'invocation(s) but only $selectedRegionHits selectedRegionId: '
              'param(s). The treasury bug (Feature 014 / Issue 8) was a '
              'BranchWarehouseFilterBar without selectedRegionId — a silent '
              'no-op that produces wrong-scope financials. Add the '
              'selectedRegionId + onRegionChanged wiring.',
        );
      });

      test('${file.path}: every BranchWarehouseFilterBar wires onRegionChanged',
          () {
        expect(
          onRegionChangedHits,
          greaterThanOrEqualTo(callSites),
          reason: '${file.path} has $callSites BranchWarehouseFilterBar '
              'invocation(s) but only $onRegionChangedHits onRegionChanged: '
              'callback(s). Without the callback the dropdown updates the '
              'UI but never the state field, so the filter is a no-op.',
        );
      });
    }
  });

  group('Report screens seed active-branch default (Feature 058 / FR-013, FR-014)',
      () {
    // The 17 in-scope launcher-destination screens that MUST seed the
    // device's active branch in initState BEFORE the first data fetch.
    // Adding a new launcher-destination report screen with a branch filter
    // field MUST be added here AND wired with the active-branch initializer.
    const inScopeScreens = <String>[
      'lib/presentation/screens/reports/sales_report_screen.dart',
      'lib/presentation/screens/reports/purchases_report_screen.dart',
      'lib/presentation/screens/reports/sales_returns_report_screen.dart',
      'lib/presentation/screens/reports/purchase_returns_report_screen.dart',
      'lib/presentation/screens/reports/inventory_report_screen.dart',
      'lib/presentation/screens/stock_movements_screen.dart',
      'lib/presentation/screens/reports/top_products_report_screen.dart',
      'lib/presentation/screens/reports/category_profit_report_screen.dart',
      'lib/presentation/screens/reports/consumption_report_screen.dart',
      'lib/presentation/screens/reports/treasury_report_screen.dart',
      'lib/presentation/screens/reports/shifts_report_screen.dart',
      'lib/presentation/screens/reports/delivery_report_screen.dart',
      'lib/presentation/screens/reports/expenses_report_screen.dart',
      'lib/presentation/screens/reports/tax_report_screen.dart',
      'lib/presentation/screens/reports/sales_by_classification_report.dart',
      'lib/presentation/screens/reports/financial_statements_screen.dart',
      'lib/presentation/screens/analytics_dashboard_screen.dart',
    ];
    // The 5 exempt screens (FR-009). Listed here so a future contributor
    // sees them; the test does NOT iterate this list.
    // ignore: unused_local_variable
    const exemptScreens = <String>[
      'lib/presentation/screens/branch_performance_screen.dart',
      'lib/presentation/screens/party_statement_screen.dart',
      'lib/presentation/screens/reports/ar_aging_report_screen.dart',
      'lib/presentation/screens/reports/vat_reconciliation_screen.dart',
      'lib/presentation/screens/stock_audit_screen.dart',
    ];

    // Match the body of the State class's initState (everything between
    // `void initState() {` and the matching closing brace at the same
    // indentation). Cheap heuristic: scan from `void initState()` to the
    // next stand-alone `}` two-space-indented line.
    final initStateBlockRe =
        RegExp(r'void\s+initState\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}', multiLine: true);

    for (final path in inScopeScreens) {
      test('$path: initState seeds activeBranchIdProvider via Future.microtask',
          () {
        final file = File(path);
        expect(file.existsSync(), isTrue,
            reason: 'In-scope screen file missing: $path. Either the file '
                'moved (update the inScopeScreens list above AND '
                'specs/058-reports-branch-scope/contracts/screen-scope-contract.md '
                'in the same commit) or this is the regression we want to catch.');

        final source = file.readAsStringSync();
        final initStateMatch = initStateBlockRe.firstMatch(source);
        expect(initStateMatch, isNotNull,
            reason: '$path: could not locate an initState() block. Feature '
                '058 requires the active-branch seed inside initState.');

        final initStateBody = initStateMatch!.group(0)!;
        expect(
          initStateBody.contains('activeBranchIdProvider'),
          isTrue,
          reason: '$path: initState() body does NOT read '
              'activeBranchIdProvider. Feature 058 / FR-001 requires '
              'seeding the branch filter from the device\'s active branch '
              'before the first data fetch. See '
              'specs/058-reports-branch-scope/spec.md FR-001..FR-004 and the '
              'implementation pattern in specs/058-reports-branch-scope/tasks.md.',
        );
        expect(
          initStateBody.contains('Future.microtask'),
          isTrue,
          reason: '$path: initState() body does NOT contain Future.microtask. '
              'Feature 058 / FR-002 requires the seed to run in an async '
              'block BEFORE the first data fetch (no flash of all-branches '
              'data). The documented pattern uses Future.microtask — see '
              'specs/058-reports-branch-scope/research.md R1.',
        );
      });
    }
  });
}
