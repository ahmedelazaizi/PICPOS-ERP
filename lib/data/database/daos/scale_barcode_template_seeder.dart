// Scale barcode label seed kept separate to preserve the large template seeder.
part of '../database.dart';

extension ScaleBarcodeTemplateSeeder on AppDatabase {
  /// Adds this template on older installations without repeating existing labels.
  ///
  /// عامّةٌ (لا `_`) لأنّ نشرَ القوالب الجاهزة عند الإقلاع يناديها أيضاً
  /// (`ready_template_deployment.dart`): منادي البذرة الوحيدُ شاشةُ المصمّم
  /// القديم المخفيّة، فلم يصل «ملصق ميزان» قاعدةً قائمةً قطّ.
  Future<void> seedScaleBarcodeTemplateIfMissing() async {
    final templates = await select(invoiceTemplates).get();
    if (templates.any(
      (t) => t.templateCategory == 'barcode' && t.name == 'ملصق ميزان',
    )) {
      return;
    }

    final id = await into(invoiceTemplates).insert(
      InvoiceTemplatesCompanion.insert(
        name: 'ملصق ميزان',
        type: const Value('thermal'),
        templateCategory: const Value('barcode'),
        paperSize: const Value('58x40'),
        paperWidth: const Value(58),
        paperHeight: const Value(40),
        isDefault: const Value(false),
      ),
    );
    const elements =
        <
          ({
            String type,
            String label,
            double x,
            double y,
            double w,
            double h,
            double size,
            String? content,
          })
        >[
          (
            type: 'product_name',
            label: 'اسم المنتج',
            x: 2,
            y: 1,
            w: 54,
            h: 6,
            size: 8,
            content: null,
          ),
          (
            type: 'scale_weight',
            label: 'الوزن',
            x: 2,
            y: 8,
            w: 26,
            h: 5,
            size: 6,
            content: null,
          ),
          (
            type: 'scale_unit_price',
            label: 'سعر الوحدة / كجم',
            x: 30,
            y: 8,
            w: 26,
            h: 5,
            size: 6,
            content: null,
          ),
          (
            type: 'scale_total',
            label: 'الإجمالي',
            x: 2,
            y: 14,
            w: 54,
            h: 6,
            size: 8,
            content: null,
          ),
          (
            type: 'scale_pack_date',
            label: 'تاريخ التعبئة',
            x: 2,
            y: 20,
            w: 54,
            h: 4,
            size: 5,
            content: null,
          ),
          (
            type: 'barcode_image',
            label: 'باركود الميزان',
            x: 5,
            y: 24,
            w: 48,
            h: 14,
            size: 5,
            content: 'ean13',
          ),
        ];
    for (var i = 0; i < elements.length; i++) {
      final el = elements[i];
      await into(invoiceTemplateElements).insert(
        InvoiceTemplateElementsCompanion.insert(
          templateId: id,
          elementType: el.type,
          sortOrder: Value(i),
          xPosition: Value(el.x),
          yPosition: Value(el.y),
          width: Value(el.w),
          height: Value(el.h),
          fontSize: Value(el.size),
          isBold: Value(el.type == 'scale_total' || el.type == 'product_name'),
          textAlign: const Value('center'),
          labelAr: Value(el.label),
          content: Value(el.content),
        ),
      );
    }
  }
}
