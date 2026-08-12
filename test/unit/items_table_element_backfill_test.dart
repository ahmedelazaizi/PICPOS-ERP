// جدولُ الأصناف يصير عنصراً في القالب — كي يملك المالكُ تحريكَه.
//
// ── فئةُ العطب ────────────────────────────────────────────────────────────
// قسمُ «جدول الأصناف» في محرّر الأقسام له أزرارُ تحريكٍ لأعلى وأسفل، ولوحةُ
// العناصر تُدرجه `variable` + `content='items_table'`. لكنّ القاعدةَ لا تحوي
// له عنصراً قطّ: البذورُ تكتفي بتعليقِ «يُقحمه المُصيِّرُ تلقائياً»، ثم
// `_migrateOldFormatElements` **تحذف** أيَّ عنصرٍ نوعُه `items_table`.
//
// فالمالكُ يحرّك شيئاً لا وجودَ له، ويعود التصميمُ كما كان. وبعد قرار الخيار
// (ب) صار الأمرُ أثقل: المُصيِّرُ يحترم موضعَ عنصر الجدول — ومن لا عنصرَ له
// يبقى على الاستدلال القديم أبداً.
//
// ── ولمَ الإلحاقُ في الإقلاع لا في البذرة ─────────────────────────────────
// `seedDefaultTemplates` مناديها الوحيدُ شاشةُ المصمّم، وهي مشروطةٌ بـ
// `if (!existingTypes.contains(...))` — فقاعدةُ المالك لا تراها. وكلُّ
// اختبارٍ يبني قاعدةً جديدةً فيأخذ البذرةَ كاملةً، فالعطبُ لا يظهر إلا على
// **قاعدةٍ قديمة**. لذلك الاختبارُ هنا يزرع قالباً على الحال القديمة عمداً.
//
// ── ولمَ لا ينقلب مطبوعٌ قائم ─────────────────────────────────────────────
// العنصرُ المُلحَقُ يوضع **حيث كان الاستدلالُ يُقحم الجدولَ بالضبط**: قبل
// أوّل عنصرٍ من الإجماليات. فالورقةُ لا تتغيّر بحرف، وإنما صار الموضعُ
// مملوكاً للقالب بعد أن كان أثراً جانبياً في الكود.

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  /// قالبُ إيصالٍ على الحال القديمة: بلا عنصرِ جدولٍ إطلاقاً.
  Future<int> seedStaleReceiptTemplate() async {
    final id = await db.into(db.invoiceTemplates).insert(
          InvoiceTemplatesCompanion.insert(
            name: 'إيصال حراري',
            type: const Value('thermal'),
            paperSize: const Value('80mm'),
            paperWidth: const Value(80),
            isDefault: const Value(true),
          ),
        );
    const stale = [
      ('variable', 'company_name'),
      ('line', ''),
      ('variable', 'invoice_number'),
      ('variable', 'customer_name'),
      ('line', ''),
      ('variable', 'subtotal'),
      ('variable', 'total_amount'),
      ('text', 'شكراً لتعاملكم معنا'),
    ];
    for (var i = 0; i < stale.length; i++) {
      await db.into(db.invoiceTemplateElements).insert(
            InvoiceTemplateElementsCompanion.insert(
              templateId: id,
              elementType: stale[i].$1,
              content: Value(stale[i].$2),
              sortOrder: Value(i),
            ),
          );
    }
    return id;
  }

  Future<List<String>> orderOf(int templateId) async {
    final els = await (db.select(db.invoiceTemplateElements)
          ..where((e) => e.templateId.equals(templateId))
          ..orderBy([(e) => OrderingTerm(expression: e.sortOrder)]))
        .get();
    return els
        .map((e) => (e.content?.isNotEmpty ?? false) ? e.content! : e.elementType)
        .toList();
  }

  test('الإلحاقُ يضع عنصرَ الجدول حيث كان الاستدلالُ يُقحمه — قبل الإجماليات',
      () async {
    final id = await seedStaleReceiptTemplate();

    // القاعدةُ المُختبَرة مبذورةٌ سلفاً بقوالبَ أخرى، فالعددُ يشملها.
    final n = await db.backfillItemsTableElements();

    expect(n, greaterThanOrEqualTo(1));
    expect(await orderOf(id), [
      'company_name',
      'line',
      'invoice_number',
      'customer_name',
      'line',
      'items_table', // ← حيث كان الاستدلالُ يُقحمه بالضبط
      'subtotal',
      'total_amount',
      'شكراً لتعاملكم معنا',
    ]);
  });

  test('العنصرُ المُلحَقُ صيغتُه جديدةٌ فيمرّ بمرشّح المُصيِّر', () async {
    final id = await seedStaleReceiptTemplate();
    await db.backfillItemsTableElements();

    final table = await (db.select(db.invoiceTemplateElements)
          ..where((e) =>
              e.templateId.equals(id) & e.content.equals('items_table')))
        .getSingle();

    // القائمةُ البيضاءُ في المُصيِّر: {variable, text, line, image, rectangle}
    expect(table.elementType, 'variable');
    expect(table.isVisible, isTrue);
  });

  test('متعادلٌ — تشغيلتان لا تُنتجان جدولين', () async {
    final id = await seedStaleReceiptTemplate();

    await db.backfillItemsTableElements();
    final second = await db.backfillItemsTableElements();

    expect(second, 0);
    final tables = await (db.select(db.invoiceTemplateElements)
          ..where((e) =>
              e.templateId.equals(id) & e.content.equals('items_table')))
        .get();
    expect(tables.length, 1);
  });

  test('قالبٌ بلا إجمالياتٍ — الجدولُ في الذيل لا في الرأس', () async {
    final id = await db.into(db.invoiceTemplates).insert(
          InvoiceTemplatesCompanion.insert(
            name: 'طلب المطبخ',
            type: const Value('kitchen'),
            isDefault: const Value(true),
          ),
        );
    const stale = [('variable', 'invoice_number'), ('variable', 'time')];
    for (var i = 0; i < stale.length; i++) {
      await db.into(db.invoiceTemplateElements).insert(
            InvoiceTemplateElementsCompanion.insert(
              templateId: id,
              elementType: stale[i].$1,
              content: Value(stale[i].$2),
              sortOrder: Value(i),
            ),
          );
    }

    await db.backfillItemsTableElements();

    expect(await orderOf(id), ['invoice_number', 'time', 'items_table']);
  });

  test('قالبُ الوردية لا يُلحق به جدولٌ — يُطبع بلا أصناف', () async {
    final id = await db.into(db.invoiceTemplates).insert(
          InvoiceTemplatesCompanion.insert(
            name: 'تقرير إغلاق الوردية',
            type: const Value('shift_closing'),
            templateCategory: const Value('shift_closing'),
            isDefault: const Value(true),
          ),
        );
    await db.into(db.invoiceTemplateElements).insert(
          InvoiceTemplateElementsCompanion.insert(
            templateId: id,
            elementType: 'variable',
            content: const Value('shift_total_sales'),
            sortOrder: const Value(0),
          ),
        );

    await db.backfillItemsTableElements();

    expect(await orderOf(id), ['shift_total_sales']);
  });

  test('قوالبُ الباركود لا يُلحق بها جدول', () async {
    final id = await db.into(db.invoiceTemplates).insert(
          InvoiceTemplatesCompanion.insert(
            name: 'باركود قياسي',
            type: const Value('thermal'),
            templateCategory: const Value('barcode'),
            isDefault: const Value(true),
          ),
        );
    await db.into(db.invoiceTemplateElements).insert(
          InvoiceTemplateElementsCompanion.insert(
            templateId: id,
            elementType: 'product_name',
            sortOrder: const Value(0),
          ),
        );

    await db.backfillItemsTableElements();

    expect(await orderOf(id), ['product_name']);
  });
}
