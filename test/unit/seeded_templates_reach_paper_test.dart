// لا عنصرَ في قالبٍ مبذورٍ يسقط صامتاً من مرشّح المُصيِّر.
//
// ── فئةُ العطب ────────────────────────────────────────────────────────────
// المُصيِّرُ يرشّح عناصرَه قبل الرسم (`templated_invoice_service.dart`):
//     {'variable', 'text', 'line', 'image', 'rectangle'}.contains(elementType)
// وما خرج عن هذه رُمي **بلا رسالةٍ ولا سجلّ**.
//
// وثلاثُ بذورٍ تكتب الصيغةَ القديمة — نوعَ العنصر مكانَ محتواه:
// `_seedPurchaseElements` و`_seedSalesReturnElements` و
// `_seedPurchaseReturnElements` تكتب `elementType: 'company_name'` و`'total'`
// و`'divider'` و`'items_table'`. فقالبٌ كامل الشكل على الشاشة يخرج على الورق
// **شبهَ فارغ**: لا يبقى منه إلا عناصرُ `text`.
//
// وكان العطبُ نائماً لأن مسارات الطباعة لم تكن تعثر على هذه القوالب أصلاً.
// فلمّا صارت تُعثَر (‏تصحيحُ الفئات 2026-08-12) استيقظ.
//
// و`_migrateOldFormatElements` لا تُنقذ: مناديها `seedDefaultTemplates`،
// ومناديها الوحيدُ شاشةُ المصمّم — ومن لا يفتحها لا يصله شيء. ثم إنها تعمل
// **قبل** البذر في نفس الاستدعاء، فما تبذره الآن يبقى قديماً حتى الزيارة
// التالية.
//
// والحارسُ هنا يشمل القوالبَ كلَّها لا المرتجعاتِ وحدَها: أيُّ بذرةٍ جديدةٍ
// تكتب صيغةً قديمةً تسقط هنا قبل أن تصل ورقةَ المالك.

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:ural_erp/data/database/database.dart';

/// القائمةُ البيضاءُ في `TemplatedInvoiceService.layoutSequenceForPrint`.
const _renderable = {'variable', 'text', 'line', 'image', 'rectangle'};

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  test('كلُّ عنصرٍ مبذورٍ يمرّ بمرشّح المُصيِّر', () async {
    await db.seedDefaultTemplates();

    final dropped = <String>[];
    for (final t in await db.getAllTemplates()) {
      // الملصقاتُ مسارُ رسمٍ آخرُ بالكامل (`printBarcodeWithTemplate`).
      if (t.templateCategory == 'barcode') continue;
      for (final e in await db.getTemplateElements(t.id)) {
        if (!_renderable.contains(e.elementType)) {
          dropped.add('${t.name} → ${e.elementType}');
        }
      }
    }

    expect(dropped, isEmpty,
        reason: 'هذه العناصرُ تُرمى صامتةً فتخرج الورقةُ ناقصةً أو فارغة');
  });

  test('لكلّ قالبٍ مبذورٍ عنصرٌ واحدٌ يُطبع على الأقل', () async {
    await db.seedDefaultTemplates();

    for (final t in await db.getAllTemplates()) {
      if (t.templateCategory == 'barcode') continue;
      final renderable = (await db.getTemplateElements(t.id))
          .where((e) => _renderable.contains(e.elementType))
          .length;
      expect(renderable, greaterThan(3),
          reason: 'قالب «${t.name}» يخرج شبهَ فارغ');
    }
  });

  group('مسارا المرتجع يجدان قالبَيهما', () {
    test('مرتجعُ المبيعات — `(thermal, sales_return)`', () async {
      await db.seedDefaultTemplates();

      final t = await db.getDefaultTemplateByCategory('thermal', 'sales_return');
      expect(t, isNotNull);
    });

    test('مرتجعُ المشتريات — `(a4, purchase_return)`', () async {
      await db.seedDefaultTemplates();

      final t =
          await db.getDefaultTemplateByCategory('a4', 'purchase_return');
      expect(t, isNotNull,
          reason: 'ورقُه A4 كما يطبعه المولّدُ اليوم — لا ينقلب إلى حراريّ');
    });

    test('لكلٍّ عنوانُه في القالب لا في الكود', () async {
      await db.seedDefaultTemplates();

      for (final pair in [
        ('thermal', 'sales_return', 'مرتجع مبيعات'),
        ('a4', 'purchase_return', 'مرتجع مشتريات'),
      ]) {
        final t =
            await db.getDefaultTemplateByCategory(pair.$1, pair.$2);
        final titles = (await db.getTemplateElements(t!.id))
            .where((e) => e.content != null && e.content!.contains(pair.$3));
        expect(titles, isNotEmpty,
            reason: 'الاستثناءُ القديمُ كان لأن العنوانَ ثابتٌ في القالب — '
                'والعلاجُ قالبٌ لكلّ مستندٍ بعنوانه، لا تخطّي القوالب');
      }
    });
  });

  test('قالبُ مرتجع المبيعات يحمل كلَّ ما كان يعرضه المولّدُ القديم', () async {
    // `ThermalReceiptGenerator.printReturnReceipt` يعرض ثمانيةَ حقول. توصيلُ
    // القالب مكانَه يجب ألّا يُسقط منها شيئاً — والحقلُ الذي لا عنصرَ له في
    // القالب يغيب عن الورقة صامتاً ولو وصلت قيمتُه.
    await db.seedDefaultTemplates();
    final t = await db.getDefaultTemplateByCategory('thermal', 'sales_return');
    final keys = (await db.getTemplateElements(t!.id))
        .map((e) => e.content)
        .whereType<String>()
        .toSet();

    for (final key in const {
      'company_name', // اسمُ الشركة
      'invoice_number', // سندُ المرتجع SRET-N
      'order_number', // الفاتورةُ الأصلية
      'date', // تاريخُ المرتجع
      'customer_name', // العميل
      'cashier_name', // employeeName
      'items_table', // الأصناف
      'total_amount', // returnTotal
      'cash_amount', // cashRefund
      'bank_amount', // bankRefund
      'payment_method', // paymentMethod
      'notes', // returnReason
    }) {
      expect(keys, contains(key), reason: '$key يغيب عن الورقة صامتاً');
    }
  });

  group('الترقيةُ تصلح قوالبَ المرتجع القديمة', () {
    test('نوعُ `sales_return` البائتُ يصير `(thermal, sales_return)`', () async {
      final id = await db.into(db.invoiceTemplates).insert(
            InvoiceTemplatesCompanion.insert(
              name: 'إيصال مرتجع مبيعات',
              type: const Value('sales_return'),
              isDefault: const Value(true),
            ),
          );

      await db.repairTemplateCategories();

      final t = await (db.select(db.invoiceTemplates)
            ..where((x) => x.id.equals(id)))
          .getSingle();
      expect(t.type, 'thermal');
      expect(t.templateCategory, 'sales_return');
    });

    test('نوعُ `purchase_return` البائتُ يصير `(a4, purchase_return)`',
        () async {
      final id = await db.into(db.invoiceTemplates).insert(
            InvoiceTemplatesCompanion.insert(
              name: 'إيصال مرتجع مشتريات',
              type: const Value('purchase_return'),
              paperSize: const Value('80mm'),
              paperWidth: const Value(80),
              isDefault: const Value(true),
            ),
          );

      await db.repairTemplateCategories();

      final t = await (db.select(db.invoiceTemplates)
            ..where((x) => x.id.equals(id)))
          .getSingle();
      expect(t.type, 'a4');
      expect(t.templateCategory, 'purchase_return');
      // ورقُه اليومَ A4 عبر `ReportPdfGenerator` — وتوصيلُ قالبٍ ٨٠mm كان
      // سيقلب مرتجعَ المشتريات إلى شريطٍ حراريّ بلا أن يطلبه أحد.
      expect(t.paperWidth, 210);
    });
  });
}
