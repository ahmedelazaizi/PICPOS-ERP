import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/presentation/pos/services/scale_barcode_encoder.dart';
import 'package:picpos_erp/services/templated_invoice_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('scale label template seeds once and builds EAN-13 PDF bytes', () async {
    final db = AppDatabase.forTesting();
    try {
      await db.seedDefaultTemplates();
      final firstSeed = (await db.getAllTemplates()).singleWhere(
        (template) =>
            template.templateCategory == 'barcode' &&
            template.name == 'ملصق ميزان',
      );
      // Keep the six legacy barcode templates, as on an upgraded installation.
      await db.deleteTemplate(firstSeed.id);
      await db.seedDefaultTemplates();
      await db.seedDefaultTemplates();
      final matching = (await db.getAllTemplates())
          .where(
            (template) =>
                template.templateCategory == 'barcode' &&
                template.name == 'ملصق ميزان',
          )
          .toList();
      expect(matching, hasLength(1));
      final elements = await db.getTemplateElements(matching.single.id);
      expect(
        elements.map((element) => element.elementType),
        containsAll([
          'product_name',
          'scale_weight',
          'scale_unit_price',
          'scale_total',
          'scale_pack_date',
          'barcode_image',
        ]),
      );
      expect(
        elements
            .singleWhere((element) => element.elementType == 'barcode_image')
            .content,
        'ean13',
      );

      final code = ScaleBarcodeEncoder.encode(
        plu: '123',
        value: 1.234,
        kind: ScaleBarcodeValueKind.weight,
      );
      Uint8List? generated;
      final printed = await TemplatedInvoiceService.printBarcodeWithTemplate(
        db: db,
        templateId: matching.single.id,
        barcodeValue: code,
        productName: 'تفاح أحمر',
        productCode: '123',
        price: 2.5,
        weight: 1.234,
        total: 3.085,
        packDate: DateTime(2026, 11, 3),
        directPrint: false,
        pdfSender: (bytes, name) async {
          generated = Uint8List.fromList(bytes);
          expect(name, 'Barcode_${code}_x1');
          return true;
        },
      );
      expect(printed, isTrue);
      expect(generated, isNotNull);
      expect(String.fromCharCodes(generated!.take(5)), '%PDF-');
      expect(generated!.length, greaterThan(1000));
      final mediaBox = RegExp(
        r'MediaBox\[0 0 ([\d.]+) ([\d.]+)\]',
      ).firstMatch(String.fromCharCodes(generated!));
      expect(mediaBox, isNotNull);
      expect(double.parse(mediaBox!.group(1)!), closeTo(58 * 72 / 25.4, 0.01));
      expect(double.parse(mediaBox.group(2)!), closeTo(40 * 72 / 25.4, 0.01));

      await db.updateTemplateElement(
        elements.first.id,
        InvoiceTemplateElementsCompanion(xPosition: const Value(12)),
      );
      Uint8List? editedPdf;
      await TemplatedInvoiceService.printBarcodeWithTemplate(
        db: db,
        templateId: matching.single.id,
        barcodeValue: code,
        productName: 'تفاح أحمر',
        productCode: '123',
        price: 2.5,
        weight: 1.234,
        total: 3.085,
        packDate: DateTime(2026, 11, 3),
        directPrint: false,
        pdfSender: (bytes, _) async {
          editedPdf = Uint8List.fromList(bytes);
          return true;
        },
      );
      expect(editedPdf, isNotNull);
      expect(
        editedPdf,
        isNot(equals(generated)),
        reason: 'تغيير إحداثي العنصر المحفوظ يجب أن يغيّر محتوى PDF',
      );

      final outputDir = Directory('docs/plans/scale_label_2026-11-03');
      await outputDir.create(recursive: true);
      await File(
        '${outputDir.path}/scale_label_preview.pdf',
      ).writeAsBytes(generated!);
    } finally {
      await db.close();
    }
  });
}
