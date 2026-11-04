import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/printing/paper_compatibility.dart';
import 'package:picpos_erp/services/printing/template_resolver.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  test('standard and custom paper sizes survive database write/read', () async {
    const papers = <({String size, double width})>[
      (size: '58mm', width: 58),
      (size: '80mm', width: 80),
      (size: 'A5', width: 148),
      (size: 'A4', width: 210),
      (size: '78mm', width: 78),
    ];
    for (final paper in papers) {
      final id = await db
          .into(db.invoiceTemplates)
          .insert(
            InvoiceTemplatesCompanion.insert(
              name: 'audit-${paper.size}',
              type: Value(paper.width < 100 ? 'thermal' : 'a4'),
              templateCategory: const Value('receipt'),
              paperSize: Value(paper.size),
              paperWidth: Value(paper.width),
            ),
          );
      final saved = await db.getTemplateById(id);
      expect(saved!.paperSize, paper.size);
      expect(saved.paperWidth, paper.width);
    }
  });

  test('fit matrix classifies template × printer widths including 78mm', () {
    const templateWidths = <double>[58, 78, 80, 148, 210];
    const printerWidths = <double>[48, 58, 72, 78, 80, 210];
    const expected = <List<PaperFit>>[
      [
        PaperFit.tooWide,
        PaperFit.ok,
        PaperFit.narrower,
        PaperFit.narrower,
        PaperFit.narrower,
        PaperFit.narrower,
      ],
      [
        PaperFit.tooWide,
        PaperFit.tooWide,
        PaperFit.tooWide,
        PaperFit.ok,
        PaperFit.ok,
        PaperFit.narrower,
      ],
      [
        PaperFit.tooWide,
        PaperFit.tooWide,
        PaperFit.tooWide,
        PaperFit.ok,
        PaperFit.ok,
        PaperFit.narrower,
      ],
      [
        PaperFit.tooWide,
        PaperFit.tooWide,
        PaperFit.tooWide,
        PaperFit.tooWide,
        PaperFit.tooWide,
        PaperFit.narrower,
      ],
      [
        PaperFit.tooWide,
        PaperFit.tooWide,
        PaperFit.tooWide,
        PaperFit.tooWide,
        PaperFit.tooWide,
        PaperFit.ok,
      ],
    ];

    for (var row = 0; row < templateWidths.length; row++) {
      for (var column = 0; column < printerWidths.length; column++) {
        expect(
          checkPaperFit(
            templateWidthMm: templateWidths[row],
            printerWidthMm: printerWidths[column],
          ).fit,
          expected[row][column],
          reason:
              '${templateWidths[row]} mm template / ${printerWidths[column]} mm printer',
        );
      }
    }
  });

  test(
    'new owner-approved templates import as v2 and resolve by type/paper',
    () async {
      const cases =
          <
            ({
              String file,
              String documentType,
              String category,
              String type,
              double width,
            })
          >[
            (
              file: 'thermal58_sales_return.json',
              documentType: 'sales_return',
              category: 'sales_return',
              type: 'thermal',
              width: 58,
            ),
            (
              file: 'thermal58_kitchen.json',
              documentType: 'kitchen_order',
              category: 'kitchen',
              type: 'kitchen',
              width: 58,
            ),
            (
              file: 'thermal58_shift_closing.json',
              documentType: 'shift_closing',
              category: 'shift_closing',
              type: 'shift_closing',
              width: 58,
            ),
            (
              file: 'thermal58_purchase_invoice.json',
              documentType: 'purchase_invoice',
              category: 'purchase',
              type: 'thermal',
              width: 58,
            ),
            (
              file: 'a5_sales_return.json',
              documentType: 'sales_return',
              category: 'sales_return',
              type: 'a4',
              width: 148,
            ),
            (
              file: 'a5_purchase_invoice.json',
              documentType: 'purchase_invoice',
              category: 'purchase',
              type: 'a4',
              width: 148,
            ),
          ];

      for (var i = 0; i < cases.length; i++) {
        final item = cases[i];
        final id = await db.importTemplateFromJson(
          await File('assets/invoice_templates/${item.file}').readAsString(),
        );
        expect(
          (await db.getTemplateById(id))?.layoutVersion,
          2,
          reason: '${item.file} must preserve its v2 layout when imported',
        );
        final printerWidth = item.width < 100 ? 72.0 : 210.0;
        expect(
          checkPaperFit(
            templateWidthMm: item.width,
            printerWidthMm: printerWidth,
          ).fit,
          isNot(PaperFit.tooWide),
          reason: '${item.file} must fit its intended printer width',
        );
        await db.activateBinding(
          documentType: item.documentType,
          templateId: id,
          branchId: i + 1,
          locale: 'ar',
          printerWidthMm: printerWidth,
        );
        final resolved = await db.resolveTemplateFor(
          documentType: item.documentType,
          category: item.category,
          branchId: i + 1,
          locale: 'ar',
          paperType: item.type,
        );
        expect(
          resolved.templateId,
          id,
          reason: '${item.file} resolver selection',
        );
      }
    },
  );

  test('binding rejects too-wide template before inserting a row', () async {
    final id = await _template(db, width: 80);
    await expectLater(
      db.activateBinding(
        documentType: 'sales_invoice',
        templateId: id,
        printerId: 5,
        printerWidthMm: 72,
      ),
      throwsA(isA<PaperMismatchException>()),
    );
    expect(await db.getAllBindings(), isEmpty);
  });

  test(
    'same-key activation returns cancelled binding and guarded delete',
    () async {
      final first = await _template(db, width: 80);
      final second = await _template(db, width: 58);
      await db.activateBinding(
        documentType: 'sales_invoice',
        templateId: first,
      );

      await expectLater(
        db.deleteTemplateGuarded(first),
        throwsA(isA<TemplateBoundException>()),
      );
      final cancelled = await db.activateBinding(
        documentType: 'sales_invoice',
        templateId: second,
      );
      expect(cancelled.map((b) => b.templateId), [first]);
      await db.deleteTemplateGuarded(first);
      expect(await db.getTemplateById(first), isNull);
    },
  );

  // كان printWithTemplate لا يمرّر printerId للحاسم، فيُسقط هذا المستوى
  // ويُطبع الاثنان بالقالب العام؛ الاختبار يثبت اختياراً مستقلاً لكل طابعة.
  test('printerId selects the matching template for each printer', () async {
    final first = await _template(db, width: 58);
    final second = await _template(db, width: 80);
    await db.activateBinding(
      documentType: 'sales_receipt',
      templateId: first,
      branchId: 9,
      printerId: 11,
      locale: 'en',
    );
    await db.activateBinding(
      documentType: 'sales_receipt',
      templateId: second,
      branchId: 9,
      printerId: 22,
      locale: 'en',
    );

    final firstResult = await db.resolveTemplateFor(
      documentType: 'sales_receipt',
      category: 'receipt',
      branchId: 9,
      printerId: 11,
      locale: 'en',
      paperType: 'thermal',
    );
    final secondResult = await db.resolveTemplateFor(
      documentType: 'sales_receipt',
      category: 'receipt',
      branchId: 9,
      printerId: 22,
      locale: 'en',
      paperType: 'thermal',
    );
    expect(firstResult.templateId, first);
    expect(secondResult.templateId, second);
  });

  test(
    'v197 adds printer width without dropping existing printer rows',
    () async {
      final id = await db.insertPrinter(name: 'legacy printer');
      await db.customStatement(
        'ALTER TABLE printers DROP COLUMN paper_width_mm',
      );

      await db.runOnUpgrade(Migrator(db), 196, 197);

      final columns = await db
          .customSelect('PRAGMA table_info(printers)')
          .get();
      expect(
        columns.map((row) => row.data['name']),
        contains('paper_width_mm'),
      );
      expect((await db.getPrinterById(id))?.name, 'legacy printer');
      expect((await db.getPrinterById(id))?.paperWidthMm, isNull);
    },
  );

  test(
    'stored printer width guards binding when width is not supplied',
    () async {
      final printerId = await db.insertPrinter(
        name: '58mm audit printer',
        paperWidthMm: 58,
      );
      expect((await db.getPrinterById(printerId))?.paperWidthMm, 58);
      await db.updatePrinter(id: printerId, name: 'renamed printer');
      expect(
        (await db.getPrinterById(printerId))?.paperWidthMm,
        58,
        reason: 'تعديل الطابعة دون تمرير العرض يجب ألا يمحو القيمة المحفوظة',
      );
      final wideTemplate = await _template(db, width: 80);

      await expectLater(
        db.activateBinding(
          documentType: 'sales_invoice',
          templateId: wideTemplate,
          printerId: printerId,
        ),
        throwsA(isA<PaperMismatchException>()),
      );
      expect(await db.getAllBindings(), isEmpty);
    },
  );

  test(
    'database resolution prefers four-scope binding over generic binding',
    () async {
      final general = await _template(db, width: 80);
      final specific = await _template(db, width: 58);
      await db.activateBinding(
        documentType: 'sales_invoice',
        templateId: general,
      );
      await db.activateBinding(
        documentType: 'sales_invoice',
        templateId: specific,
        branchId: 9,
        printerId: 4,
        locale: 'en',
      );

      final resolution = await db.resolveTemplateFor(
        documentType: 'sales_invoice',
        category: 'receipt',
        branchId: 9,
        printerId: 4,
        locale: 'en',
      );
      expect(resolution.templateId, specific);
      expect(resolution.level, 1);
    },
  );

  test(
    'fresh database seeding is repeatable with at most one default per type/category',
    () async {
      await db.seedDefaultTemplates();
      await db.seedDefaultTemplates();
      final templates = await db.getAllTemplates();
      expect(templates, isNotEmpty);

      final defaultGroups = <String, int>{};
      for (final template in templates.where((t) => t.isDefault)) {
        final key = '${template.type}|${template.templateCategory}';
        defaultGroups.update(key, (count) => count + 1, ifAbsent: () => 1);
      }
      expect(
        defaultGroups.values.every((count) => count == 1),
        isTrue,
        reason:
            'more than one isDefault in the same type/category: $defaultGroups',
      );
    },
  );

  test('all declared document types resolve to binding-capable rules', () {
    expect(
      TemplateResolver.documentTypes,
      containsAll(<String>[
        'sales_invoice',
        'sales_return',
        'purchase_invoice',
        'purchase_return',
        'sales_receipt',
        'quotation',
        'kitchen_order',
        'shift_closing',
        'party_statement',
        'report',
      ]),
    );
    expect(TemplateResolver.wiredDocumentTypes, isNot(contains('report')));
    expect(TemplateResolver.wiredDocumentTypes, contains('party_statement'));
  });
}

Future<int> _template(AppDatabase db, {required double width}) => db
    .into(db.invoiceTemplates)
    .insert(
      InvoiceTemplatesCompanion.insert(
        name: 'audit-$width',
        type: Value(width < 100 ? 'thermal' : 'a4'),
        paperSize: Value(width == 58 ? '58mm' : '${width.toInt()}mm'),
        paperWidth: Value(width),
      ),
    );
