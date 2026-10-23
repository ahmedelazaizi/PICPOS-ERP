// ═══════════════════════════════════════════════════════════════════════════
// §٣‑٢ — شاشةُ التحليلات: مقامُ الهامش، وحصرُ المصروف
// ═══════════════════════════════════════════════════════════════════════════
//
// عطبان في `getMonthlyPerformanceSeries` — أساسِ كلّ بطاقةٍ في الشاشة:
//
// ‏١) **الهامشُ يقسم إيراداً شاملَ الضريبة على تكلفةٍ خالصة.** `cost_price`
//    تكلفةٌ بلا ضريبة، و`net_sales` كان `SUM(total)` شاملَها — فالهامشُ
//    يُنفَخ بنسبةِ الضريبة على كلّ صنف. وهذا **عينُ** ما عولج في
//    `getCategoryProfitReport` بنفس الملفّ (`SUM(si.total - si.tax_amount)`)
//    ولم ينزل هنا.
//
// ‏٢) **المصروفُ بلا حصرِ فرعٍ ولا مركزِ تكلفة** بينما المبيعاتُ والتكلفةُ
//    محصورتان بهما. فمديرُ فرعٍ يرى مبيعاتِ فرعِه مقابلَ مصروفاتِ الشركة
//    كلِّها — رقمان من نطاقَين على بطاقةٍ واحدة.
//
// ⚠️ **وما لا يُرشَّح عمداً**: الخارطةُ اقترحت ترشيحَ `status` («يحتسب
// المسوّدات»)، وهو **خطأ**. `status` أثرُ مراجعةٍ لا حدثٌ محاسبيّ: القيدُ
// يُرحَّل عند التسجيل و`updateExpenseStatus` يكتب العمودَ وحدَه، وافتراضُه
// `draft` — فترشيحُ المسوّدات كان سيحذف المصروفاتِ الحقيقيّةَ كلَّها. وآخرُ
// اختبارٍ هنا يقفل ذلك القرارَ صراحةً.
//
// و`net_sales` يبقى شاملَ الضريبة عن قصد: هو ما يعرضه تقريرُ المبيعات على
// نفس المدى، فلو تغيّر لاختلفت شاشتان على نفس الرقم.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int categoryId;
  late int productId;
  final from = DateTime(2026, 3, 1);
  final to = DateTime(2026, 3, 31);

  /// مجموعُ مفتاحٍ عبر شهور المدى — تفادياً لهشاشةِ مفتاح الشهر.
  Future<double> total(String key, {Set<int>? scope}) async {
    final rows = await db.getMonthlyPerformanceSeries(
      from: from,
      to: to,
      allowedBranchIds: scope,
    );
    var sum = 0.0;
    for (final r in rows) {
      sum += (r[key] as num?)?.toDouble() ?? 0.0;
    }
    return sum;
  }

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.into(db.branches).insert(BranchesCompanion.insert(name: 'فرع ٢'));

    categoryId = await db.into(db.opExpenseCategories).insert(
          OpExpenseCategoriesCompanion.insert(name: 'إيجار'),
        );

    productId = await db.into(db.products).insert(ProductsCompanion.insert(
          code: 'ANL-VAT-1',
          name: 'صنفٌ بضريبة',
          salePrice: const Value(125),
          costPrice: const Value(100),
        ));
  });

  tearDown(() => db.close());

  // ───────────────────────────────────────────────────────────────────────
  // ‏١) مقامُ الهامش
  // ───────────────────────────────────────────────────────────────────────

  group('§٣‑٢ مقامُ الهامش خالٍ من الضريبة', () {
    // بيعٌ ١٢٥ قبل الضريبة + ضريبةُ ١٦٪ = ٢٠ ⇒ الإجماليُّ ١٤٥.
    // والتكلفةُ ١٠٠ خالصةٌ من الضريبة.
    //   الهامشُ الصحيح  = (125 − 100) / 125 = ٢٠٪
    //   الهامشُ المعطوب = (145 − 100) / 145 = ٣١٪
    setUp(() async {
      final invoiceId =
          await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
                invoiceNumber: 'SI-VAT-32',
                warehouseId: 1,
                userId: 1,
                invoiceDate: DateTime(2026, 3, 5),
                branchId: const Value(1),
                subtotal: const Value(125),
                tax: const Value(20),
                total: const Value(145),
              ));
      await db
          .into(db.salesInvoiceItems)
          .insert(SalesInvoiceItemsCompanion.insert(
            invoiceId: invoiceId,
            productId: productId,
            quantity: 1,
            unitPrice: 125,
            total: 125,
            costPrice: const Value(100),
            quantityInBase: const Value(1),
          ));
    });

    test('مرساة: الفاتورةُ في السلسلة و`net_sales` شاملُ الضريبة كما كان',
        () async {
      expect(await total('net_sales'), 145.0,
          reason: 'لو تغيّر هذا لاختلفت التحليلاتُ عن تقرير المبيعات');
      expect(await total('cogs'), 100.0);
    });

    test('🔴 `net_sales_ex_tax` = الإجماليُّ ناقصَ الضريبة', () async {
      expect(await total('net_sales_ex_tax'), 125.0,
          reason: 'كان الهامشُ يقسم على 145 فيعطي ٣١٪ بدل ٢٠٪');
    });

    test('🔴 الهامشُ المحسوبُ منه = ٢٠٪ لا ٣١٪', () async {
      final exTax = await total('net_sales_ex_tax');
      final cogs = await total('cogs');
      final gross = await total('net_sales');

      expect((exTax - cogs) / exTax * 100, closeTo(20.0, 1e-9));
      // والمقابلُ المعطوب — مثبَّتٌ كي يبقى الفرقُ مقيساً لا موصوفاً.
      expect((gross - cogs) / gross * 100, closeTo(31.03448, 1e-4));
    });

    test('فاتورةٌ بلا ضريبة: الرقمان متساويان — حارسٌ ضدّ إصلاحٍ زائد',
        () async {
      await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
            invoiceNumber: 'SI-NOVAT-32',
            warehouseId: 1,
            userId: 1,
            invoiceDate: DateTime(2026, 3, 9),
            branchId: const Value(1),
            subtotal: const Value(60),
            total: const Value(60),
          ));

      expect(await total('net_sales'), 205.0); // 145 + 60
      expect(await total('net_sales_ex_tax'), 185.0, // 125 + 60
          reason: 'الفاتورةُ بلا ضريبةٍ تدخل الرقمَين بنفس القيمة');
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // ‏٢) حصرُ المصروف
  // ───────────────────────────────────────────────────────────────────────

  group('§٣‑٢ المصروفُ يُحصَر بنفس نطاق المبيعات', () {
    setUp(() async {
      Future<void> expense(String note, double amount, int? branchId) =>
          db.into(db.opExpenses).insert(OpExpensesCompanion.insert(
                categoryId: categoryId,
                amount: amount,
                expenseDate: DateTime(2026, 3, 10),
                userId: 1,
                notes: Value(note),
                branchId: Value(branchId),
              ));

      await expense('فرع ١', 100, 1);
      await expense('فرع ٢', 700, 2);
      await expense('مستوى الشركة', 30, null); // NULL يبقى مرئيّاً
    });

    test('مرساة: بلا حصرٍ تُجمَع الثلاثة', () async {
      expect(await total('expenses'), 830.0);
    });

    test('🔴 محصورٌ بالفرع ١ ⇒ ١٣٠ لا ٨٣٠', () async {
      expect(await total('expenses', scope: {1}), 130.0,
          reason: 'كان يرى ٨٣٠ — مصروفاتِ الشركة كلِّها مقابلَ مبيعاتِ فرعِه '
              'وحدَه، والفرقُ يُقرأ خسارةً ليست له');
    });

    test('صفُّ الشركة (‏branch_id NULL) يبقى مرئيّاً تحت الحصر', () async {
      expect(await total('expenses', scope: {2}), 730.0,
          reason: 'نفسُ عقدِ `_buildAuthScopeFilter`: NULL لا يُقصى');
    });

    test('🔴 نطاقٌ فارغ ⇒ صفر (فشلٌ مقفول) لا الكلّ', () async {
      expect(await total('expenses', scope: <int>{}), 0.0);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // ‏٣) قرارٌ مقفول: المسوّدةُ مصروفٌ حقيقيّ
  // ───────────────────────────────────────────────────────────────────────

  test('🔴 المسوّدةُ تُحتسَب — `status` أثرُ مراجعةٍ لا حدثٌ محاسبيّ', () async {
    // `status` افتراضُه `draft`، والقيدُ يُرحَّل للأستاذ عند التسجيل. فلو
    // رُشِّحت المسوّداتُ لسقطت المصروفاتُ الحقيقيّةُ كلُّها وخالفت الشاشةُ
    // الأستاذ.
    await db.into(db.opExpenses).insert(OpExpensesCompanion.insert(
          categoryId: categoryId,
          amount: 250,
          expenseDate: DateTime(2026, 3, 12),
          userId: 1,
          notes: const Value('مسوّدة'),
          branchId: const Value(1),
        ));

    final rows = await db.getMonthlyPerformanceSeries(from: from, to: to);
    final stored = await (db.select(db.opExpenses)
          ..where((e) => e.notes.equals('مسوّدة')))
        .getSingle();

    expect(stored.status, 'draft', reason: 'مرساة: الصفُّ مسوّدةٌ فعلاً');
    expect(rows.fold<double>(0, (a, r) => a + (r['expenses'] as num).toDouble()),
        250.0,
        reason: 'ترشيحُ المسوّدات كان سيصفّر المصروفاتِ كلَّها');
  });
}
