// تصميمُ A4 يجب أن يصل الورقة.
//
// ── فئةُ العطب (بلاغُ المالك 2026-08-12: «تصميمي مش بيوصل للورقة») ────────
// `InvoiceGenerator.printSalesInvoice` يسأل:
//     hasDefaultTemplate(db, 'a4', category: 'invoice')
// والبذرةُ تُنشئ «فاتورة A4» بـ`type: 'a4'` و**بلا** `templateCategory` —
// فتأخذ الافتراضَ `'receipt'` (`invoice_template_tables.dart:13`).
// و`getDefaultTemplateByCategory` يشترط تطابقَ الاثنين، فلا يجد شيئاً.
//
// والنتيجة صامتة: `hasTemplate == false` ⇒ يسقط التنفيذُ إلى المولّد المكتوب
// في الكود، فتُطبع كلُّ فاتورة A4 بتصميمٍ ثابتٍ **لا يمسّه المصمّم أبداً**.
// لا استثناءَ ولا سطرَ سجلّ — المالكُ يصمّم ويحفظ ويطبع فيرى ورقتَه القديمة.
//
// ونفسُ العطب في المشتريات: البذرةُ `type: 'purchase'` بفئةٍ افتراضيةٍ
// `'receipt'`، والمنادي يسأل `('a4', 'purchase')` — فلا يتطابق طرفٌ منهما.
//
// ── لماذا الفئةُ هي الصواب لا النوع ───────────────────────────────────────
// قائمةُ المصمّم نفسِها (`invoice_designer_ui.dart:314-320`) تجعل
// `templateCategory` نوعَ المستند: نقطةُ بيع · فواتيرُ مبيعات · مشتريات ·
// مطبخ · عرضُ سعر · باركود · إقفالُ وردية. ومحرّرُ الأقسام يتفرّع عليها
// (`invoice_section_editor.dart:252-254`). فالبذرةُ هي الشاذّة.
//
// ⚠️ وكلُّ اختبارٍ يبني قاعدةً جديدةً فيأخذ البذرةَ المصحّحة — فالعطبُ لا
// يظهر إلا على قاعدةٍ قديمة. لذلك يزرع الاختبارُ الحالَ القديمةَ عمداً.

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/templated_invoice_service.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  group('البذرةُ تطابق ما يسأله المنادي', () {
    test('فاتورةُ A4 — `(a4, invoice)`', () async {
      await db.seedDefaultTemplates();

      expect(
        await TemplatedInvoiceService.hasDefaultTemplate(db, 'a4',
            category: 'invoice'),
        isTrue,
        reason: 'ما يسأله `invoice_generator.dart:164` بالحرف',
      );
    });

    test('فاتورةُ المشتريات — `(a4, purchase)`', () async {
      await db.seedDefaultTemplates();

      expect(
        await TemplatedInvoiceService.hasDefaultTemplate(db, 'a4',
            category: 'purchase'),
        isTrue,
        reason: 'ما يسأله `invoice_generator.dart:239` بالحرف. والمصمّمُ لا '
            'يعرض إلا thermal/a4/kitchen، فلا وجودَ لنوعٍ اسمُه purchase',
      );
    });

    test('طلبُ المطبخ فئتُه `kitchen` — وإلا فتحه المصمّمُ بأقسام الإيصال',
        () async {
      await db.seedDefaultTemplates();

      final t = await db.getDefaultTemplate('kitchen');
      expect(t?.templateCategory, 'kitchen',
          reason: '`invoice_section_editor.dart:252` يتفرّع على الفئة لا النوع');
    });

    test('ضابط: الإيصالُ الحراريُّ لم ينكسر — `(thermal, receipt)`', () async {
      await db.seedDefaultTemplates();

      expect(
        await TemplatedInvoiceService.hasDefaultTemplate(db, 'thermal',
            category: 'receipt'),
        isTrue,
      );
    });
  });

  group('الترقيةُ تصلح قاعدةً قائمة', () {
    /// قالبٌ على الحال القديمة: فئتُه الافتراضيةُ `receipt`.
    Future<int> seedStale(String name, String type) => db
        .into(db.invoiceTemplates)
        .insert(InvoiceTemplatesCompanion.insert(
          name: name,
          type: Value(type),
          paperSize: const Value('A4'),
          paperWidth: const Value(210),
          isDefault: const Value(true),
        ));

    test('فئةُ قالب A4 تُصحَّح إلى `invoice`', () async {
      final id = await seedStale('فاتورة A4', 'a4');

      await db.repairTemplateCategories();

      final t = await (db.select(db.invoiceTemplates)
            ..where((x) => x.id.equals(id)))
          .getSingle();
      expect(t.templateCategory, 'invoice');
    });

    test('قالبُ المشتريات يُصحَّح في المحورَين — `(a4, purchase)`', () async {
      // `type: 'purchase'` نوعٌ لا وجودَ له في المصمّم أصلاً.
      final id = await seedStale('فاتورة مشتريات', 'purchase');

      await db.repairTemplateCategories();

      final t = await (db.select(db.invoiceTemplates)
            ..where((x) => x.id.equals(id)))
          .getSingle();
      expect(t.type, 'a4');
      expect(t.templateCategory, 'purchase');
    });

    test('الإيصالُ الحراريُّ لا يُمَسّ — فئتُه `receipt` صحيحةٌ أصلاً', () async {
      final id = await seedStale('إيصال حراري', 'thermal');

      await db.repairTemplateCategories();

      final t = await (db.select(db.invoiceTemplates)
            ..where((x) => x.id.equals(id)))
          .getSingle();
      expect(t.templateCategory, 'receipt');
    });

    test('فئةٌ اختارها المالكُ بنفسه لا تُدهَس', () async {
      // من ضبط قالبَ A4 على «عرض سعر» عمداً لا يُعاد قسراً إلى «مبيعات».
      final id = await db.into(db.invoiceTemplates).insert(
            InvoiceTemplatesCompanion.insert(
              name: 'فاتورة A4',
              type: const Value('a4'),
              templateCategory: const Value('quotation'),
              isDefault: const Value(true),
            ),
          );

      await db.repairTemplateCategories();

      final t = await (db.select(db.invoiceTemplates)
            ..where((x) => x.id.equals(id)))
          .getSingle();
      expect(t.templateCategory, 'quotation');
    });

    test('متعادلة — تشغيلتان لا تختلفان', () async {
      await seedStale('فاتورة A4', 'a4');

      await db.repairTemplateCategories();
      final second = await db.repairTemplateCategories();

      expect(second, 0);
    });
  });
}
