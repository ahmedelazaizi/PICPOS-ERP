import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/domain/printing/print_test_scenarios.dart';
import 'package:picpos_erp/domain/printing/print_probe.dart';
import 'package:picpos_erp/services/printing/layout_engine.dart';
import 'package:picpos_erp/services/printing/paint_plan.dart';
import 'package:picpos_erp/services/printing/template_render_pipeline.dart';
import 'package:picpos_erp/services/templated_invoice_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'every seeded 80mm items table keeps each column at least 12mm',
    () async {
      final db = AppDatabase.forTesting();
      try {
        final failures = <String>[];
        final files =
            Directory('assets/invoice_templates')
                .listSync()
                .whereType<File>()
                .where((file) => file.path.endsWith('.json'))
                .toList()
              ..sort((a, b) => a.path.compareTo(b.path));

        for (final file in files) {
          final raw = await file.readAsString();
          final json = jsonDecode(raw) as Map<String, dynamic>;
          if ((json['paperWidth'] as num?)?.toDouble() != 80) continue;
          final id = await db.importTemplateFromJson(raw);
          final data = (await db.getTemplateWithData(id))!;
          final document = TemplateRenderPipeline.buildDocument(
            template: data.template,
            orderedElements: TemplatedInvoiceService.orderElementsForPrint(
              data.elements,
            ),
            tableSettings: data.tableSettings,
          );
          final columns = document.table?.visibleColumns ?? const [];
          if (columns.isEmpty) continue;
          final totalFlex = columns.fold<double>(0, (sum, c) => sum + c.flex);
          for (final column in columns) {
            final width =
                document.paper.contentWidthMm * column.flex / totalFlex;
            if (width < 12) {
              failures.add(
                '${file.uri.pathSegments.last}: ${column.key} '
                '${width.toStringAsFixed(1)}mm',
              );
            }
          }
        }

        expect(failures, isEmpty, reason: failures.join('\n'));
      } finally {
        await db.close();
      }
    },
  );

  test('every seeded 80mm template passes blocking print checks', () async {
    final db = AppDatabase.forTesting();
    try {
      final failures = <String>[];
      final scenarios = buildPrintScenarios();
      final files = Directory('assets/invoice_templates')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'));

      for (final file in files) {
        final raw = await file.readAsString();
        final json = jsonDecode(raw) as Map<String, dynamic>;
        if ((json['paperWidth'] as num?)?.toDouble() != 80) continue;
        final id = await db.importTemplateFromJson(raw);
        final data = (await db.getTemplateWithData(id))!;
        final ordered = TemplatedInvoiceService.orderElementsForPrint(
          data.elements,
        );
        final document = TemplateRenderPipeline.buildDocument(
          template: data.template,
          orderedElements: ordered,
          tableSettings: data.tableSettings,
        );
        for (final scenario in scenarios) {
          final positioned = LayoutEngine.paginate(
            document: document,
            rows: TemplateRenderPipeline.buildRows(
              scenario.items,
              document.table,
              scenario.payload.decimals,
            ),
            values: TemplateRenderPipeline.buildValues(
              document,
              scenario.payload,
            ),
          );
          final pages = [
            for (final page in positioned) ProbedPage(page, planPage(page)),
          ];
          final checks = probePrintout(
            pages: pages,
            document: document,
            printerWidthMm: 80,
          );
          for (final check in checks.where((c) => c.level == ProbeLevel.fail)) {
            failures.add(
              '${file.uri.pathSegments.last} / ${scenario.id}: '
              '${check.title} — ${check.note}',
            );
          }
        }
      }

      expect(failures, isEmpty, reason: failures.join('\n'));
    } finally {
      await db.close();
    }
  });
}
