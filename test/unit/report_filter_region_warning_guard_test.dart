// Spec 079 / Batch 5 — Grep guard for FR-003 diagnostic warning.
// Extended by Spec 079b — covers 5 Group B screens that don't use the
// `_regionWarehouseIds` shape but were FILTER-WARN-instrumented anyway.
//
// Walks all report screens that declare `_regionWarehouseIds` and
// asserts each one fires the FILTER-WARN DiagnosticLogger line
// when the region selection yields zero warehouses. Without this
// guard, a future region-callback edit could silently drop the
// observability and operators lose the data-integrity signal.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/library_source.dart';

void main() {
  test('every report screen with _regionWarehouseIds fires FILTER-WARN', () {
    final reportsDir = Directory('lib/presentation/screens/reports');
    expect(reportsDir.existsSync(), isTrue);

    final missing = <String>[];
    final checked = <String>[];

    for (final entity in reportsDir.listSync()) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      // Part files are checked through their library entrypoint.
      if (RegExp(r'^\s*part\s+of\b', multiLine: true)
          .hasMatch(entity.readAsStringSync())) continue;
      final src = readLibrarySource(entity.path);
      // Group A — screens that cache region → warehouse ids client-side.
      // These are the ones FR-003 covers; other patterns (e.g. pass
      // regionId directly to repo) are Group B and out of scope here.
      if (!src.contains('_regionWarehouseIds')) continue;
      checked.add(entity.uri.pathSegments.last);
      // Must reference the FILTER-WARN log line OR opt-out via comment.
      final hasWarn = src.contains("'FILTER-WARN'") ||
          src.contains('// FILTER-WARN-OPTOUT:');
      if (!hasWarn) {
        missing.add(entity.uri.pathSegments.last);
      }
    }

    expect(checked, isNotEmpty,
        reason: 'No report screens with _regionWarehouseIds parsed — '
            'either the directory moved or the test regex broke');
    expect(missing, isEmpty,
        reason: 'These report screens cache _regionWarehouseIds but '
            'do NOT fire the FILTER-WARN diagnostic — operators '
            'lose data-integrity signal when region has 0 warehouses:\n'
            '${missing.join('\n')}\n\n'
            'Add this in the onRegionChanged callback:\n'
            "  if (regionIdsCheck != null && regionIdsCheck.isEmpty) {\n"
            "    unawaited(DiagnosticLogger.log('FILTER-WARN',\n"
            "      'Region selected but no warehouses linked...'));\n"
            "  }\n"
            'OR add `// FILTER-WARN-OPTOUT: <reason>` near the callback '
            'to explicitly waive (e.g. screen has no local-filter path).');
  });

  test('Spec 079b — Group B report screens all fire FILTER-WARN', () {
    // Group B screens don't share the `_regionWarehouseIds` shape, so they
    // are listed explicitly. If you add a new report screen with a region
    // dropdown that follows one of these patterns, add it here too.
    const groupBFiles = <String>[
      'lib/presentation/screens/reports/expenses_report_screen.dart',
      'lib/presentation/screens/reports/purchases_report_screen.dart',
      'lib/presentation/screens/reports/treasury_report_screen.dart',
      'lib/presentation/screens/reports/shifts_report_screen.dart',
      'lib/presentation/screens/reports/inventory_report_screen.dart',
    ];

    final missing = <String>[];
    for (final path in groupBFiles) {
      final f = File(path);
      expect(f.existsSync(), isTrue,
          reason: 'Group B file moved or renamed: $path');
      final src = readLibrarySource(path);
      final hasWarn = src.contains("'FILTER-WARN'") ||
          src.contains('// FILTER-WARN-OPTOUT:');
      if (!hasWarn) missing.add(path);
    }

    expect(missing, isEmpty,
        reason: 'Spec 079b Group B screens missing FILTER-WARN '
            'diagnostic:\n${missing.join('\n')}');
  });
}
