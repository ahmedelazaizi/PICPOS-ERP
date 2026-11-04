import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../data/providers/providers.dart';
import '../../../../domain/entities/product_entity.dart';
import '../../../../services/printing/barcode_label_printer.dart';
import '../../../../services/printing/barcode_label_spec.dart';
import '../../../../services/printing/label_default_copies.dart';
import '../../../../services/printing/label_item_sample.dart';
import '../../../../services/templated_invoice_service.dart';
import '../../../pos/services/scale_barcode_config.dart';
import 'barcode_label_batch_dialog.dart';

/// طباعة ملصقات صنف واحد: يفتح حوار الطباعة الدفعي بصنف واحد، ونسخه
/// الافتراضية من كمية آخر استلام (أو 1).
class BarcodePrintDialog {
  const BarcodePrintDialog._();

  static Future<void> show(BuildContext context, ProductEntity product) async {
    final container = ProviderScope.containerOf(context);
    final db = container.read(databaseProvider);
    final settings = <String, String>{};
    // كلُّ مفاتيح إعداد الميزان (منها `scale_weight_enabled` والمفاتيح
    // القديمة) — كانت ثلاثة فقط، فلا يعرف الحوار إن كان الإعداد مفعّلاً.
    // تُقرأ عند كل فتح ⇒ تفعيلُ الإعداد يظهر في القائمة بإعادة فتح النافذة.
    for (final key in ScaleBarcodeConfig.readKeys) {
      final value = await db.getSettingValue(key);
      if (value != null) settings[key] = value;
    }
    final templates =
        (await container
                .read(invoiceTemplatesRepositoryProvider)
                .getAllTemplates())
            .where((template) => template.templateCategory == 'barcode')
            .toList();
    final scaleTemplate = templates
        .where((t) => t.name == 'ملصق ميزان')
        .firstOrNull;
    final defaultTemplate = templates.where((t) => t.isDefault).firstOrNull;
    // عناصرُ كلِّ قالبٍ للمعاينة — بنفس قارئ المحرّر والراسم (‏`loadLabelDesign`).
    // بلاها كانت المعاينةُ ترسم خلايا باسم الصنف وحده والورقةُ تحمل السعرَ
    // والباركود.
    final repo = container.read(invoiceTemplatesRepositoryProvider);
    final designs = {
      for (final t in templates) t.id: await repo.getLabelDesign(t.id),
    };
    if (!context.mounted) return;

    return BarcodeLabelBatchDialog.show(
      context,
      [
        BarcodeLabelItem(
          name: product.name,
          barcode: product.barcode ?? product.code,
          price: product.salePrice,
          productId: product.id,
          scalePluNumber: product.scalePluNumber ?? int.tryParse(product.code),
          isSoldByWeight: product.isSoldByWeight,
        ),
      ],
      scaleSettings: settings,
      scaleTemplateId: scaleTemplate?.id,
      templates: [
        for (final template in templates)
          BarcodeLabelTemplateOption(
            id: template.id,
            name: template.name,
            widthMm: template.paperWidth,
            heightMm: template.paperHeight ?? 25,
            design: designs[template.id],
          ),
      ],
      defaultTemplateId: defaultTemplate?.id,
      onPrintTemplate: (items, spec, selectedTemplateId) async {
        for (final item in items) {
          // نفسُ العيّنة التي ترسمها المعاينة — المعاينة = الخرج.
          final s = labelSampleForItem(item);
          final printed =
              await TemplatedInvoiceService.printBarcodeWithTemplate(
                db: db,
                templateId: selectedTemplateId,
                barcodeValue: s.barcodeValue,
                productName: s.productName,
                productCode: s.productCode,
                price: s.price,
                weight: s.weight,
                total: s.total,
                packDate: s.packDate,
                copies: item.copies,
                directPrint: false,
              );
          if (!printed) return false;
        }
        return true;
      },
      onPrint: (items, spec) => BarcodeLabelPrinter.print(items, spec: spec),
      loadDefaults: (items) => withLastReceiptCopies(db, items),
    );
  }
}
