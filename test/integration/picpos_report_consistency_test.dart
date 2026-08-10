// ═══════════════════════════════════════════════════════════════════════════
// اتّساقُ التقارير — H6 · H7 · H9 · H12
// ═══════════════════════════════════════════════════════════════════════════
//
// العائلةُ كلُّها من فئةٍ واحدة: **بطاقةٌ وجدولٌ على نفس الشاشة يقرآن نفس
// المدى بشرطَين مختلفَين**، فيرى المستخدمُ رقمَين ولا يعرف أيَّهما الصحيح.
//
// H6 · المشتريات: بطاقةُ الإجمالي تستبعد المحذوفَ ناعماً، وقائمةُ الموردين
//   وجدولُ الفواتير لا يستبعدانه.
// H7 · حدُّ المدى: `normalizedEnd` منتصفُ ليل اليوم التالي و`BETWEEN` شاملٌ
//   للطرفين ⇒ فاتورةُ الحدّ تُحتسب في **مدّتين** — ازدواجُ إيرادٍ عند حدود
//   الشهور. (‏نفسُ العلّة على جانب المشتريات.)
// H9 · تبويبُ «حسب التصنيف» يستبعد المرتجعَ والملغى، وتبويبُ «حسب النوع» لا
//   يستبعد شيئاً — ويُخرج مجموعةً اسمُها `return` ضمن «أنواع البيع».
// H12 · الخزينة: فلترُ المستخدم يُطبَّق على الجدول ولا يصل البطاقات.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int warehouseId;
  late int userId;
  late int otherUserId;
  late int productId;
  late int supplierId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    warehouseId = (await db.getDefaultWarehouse())!.id;
    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(name: 'كاشير RP', isSystemRole: const Value(false)),
        );
    userId = await db.createUser(
      username: 'rp_a', password: 'pw', displayName: 'أ', roleId: roleId);
    otherUserId = await db.createUser(
      username: 'rp_b', password: 'pw', displayName: 'ب', roleId: roleId);
    productId = await db.insertProduct(ProductsCompanion.insert(
      code: 'RP-1',
      name: 'صنف',
      salePrice: const Value(100),
      costPrice: const Value(60),
      trackInventory: const Value(true),
    ));
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 1000,
      type: 'in',
      unitCost: 60,
    );
    supplierId = await db.insertParty(PartiesCompanion.insert(
      name: 'مورد التقارير',
      isCustomer: const Value(false),
      isSupplier: const Value(true),
    ));
  });

  tearDown(() async => db.close());

  Future<int> purchase({
    required String no,
    required double total,
    required DateTime date,
    bool deleted = false,
  }) async {
    final id = await db.into(db.purchaseInvoices).insert(
          PurchaseInvoicesCompanion.insert(
            invoiceNumber: no,
            supplierId: supplierId,
            warehouseId: warehouseId,
            subtotal: Value(total),
            total: Value(total),
            invoiceDate: date,
          ),
        );
    if (deleted) {
      await (db.update(db.purchaseInvoices)..where((p) => p.id.equals(id)))
          .write(const PurchaseInvoicesCompanion(isDeleted: Value(true)));
    }
    return id;
  }

  Future<int> sale({
    required String no,
    required double total,
    required DateTime date,
    String saleType = 'default',
    String status = 'completed',
  }) =>
      db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
            invoiceNumber: no,
            warehouseId: warehouseId,
            userId: userId,
            invoiceDate: date,
            subtotal: Value(total),
            total: Value(total),
            paid: Value(total),
            paymentMethod: const Value('cash'),
            saleType: Value(saleType),
            status: Value(status),
          ));

  // ═════════════════════════════════════════════════════════════════════════
  // H6
  // ═════════════════════════════════════════════════════════════════════════

  group('H6 — المشتريات: المحذوفُ ناعماً', () {
    final from = DateTime(2026, 7, 1);
    final to = DateTime(2026, 7, 31);

    test('البطاقةُ وقائمةُ الموردين تقولان نفسَ الرقم', () async {
      await purchase(no: 'P-OK', total: 10000, date: DateTime(2026, 7, 5));
      await purchase(
          no: 'P-DEL', total: 4000, date: DateTime(2026, 7, 6), deleted: true);

      final analytics = await db.getPurchasesReportAnalytics(from, to);
      final bySupplier = await db.getPurchasesBySupplier(from: from, to: to);
      final supplierTotal = bySupplier.fold<double>(
          0, (s, r) => s + ((r['totalPurchases'] as num?)?.toDouble() ?? 0));

      expect(analytics.totalPurchases, closeTo(10000, 0.01),
          reason: 'ضابط: البطاقةُ كانت تستبعد المحذوفَ أصلاً');
      expect(
        supplierTotal,
        closeTo(10000, 0.01),
        reason: 'اتقاس ١٤٬٠٠٠ — قائمةُ الموردين كانت تعدّ المحذوفَ ناعماً '
            'بينما البطاقةُ فوقها لا تعدّه: رقمان لنفس المدى.',
      );
    });

    test('وجدولُ الفواتير كذلك لا يعرض المحذوف', () async {
      await purchase(no: 'P-OK2', total: 10000, date: DateTime(2026, 7, 5));
      await purchase(
          no: 'P-DEL2', total: 4000, date: DateTime(2026, 7, 6), deleted: true);

      final rows = await db.getPurchasesWithSupplierByDateRange(from, to);
      expect(rows.map((r) => r.invoice.invoiceNumber), ['P-OK2'],
          reason: 'الجدولُ كان يعرض الفاتورةَ المحذوفة صراحةً.');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // H7
  // ═════════════════════════════════════════════════════════════════════════

  group('H7 — فاتورةُ الحدّ', () {
    // فاتورةٌ مختومةٌ في منتصف ليل أوّل أغسطس بالضبط.
    final boundary = DateTime(2026, 8, 1);

    test('فاتورةُ منتصف الليل تُحتسب في أغسطس وحدَه لا في يوليو كذلك', () async {
      await sale(no: 'S-BND', total: 700, date: boundary);

      final july = await db.getSalesAnalytics(
          DateTime(2026, 7, 1), DateTime(2026, 7, 31));
      final august = await db.getSalesAnalytics(
          DateTime(2026, 8, 1), DateTime(2026, 8, 31));

      expect(
        july.totalSales,
        closeTo(0, 0.01),
        reason: 'اتقاست ٧٠٠ — `BETWEEN` شاملٌ للطرفين و`normalizedEnd` هو '
            'منتصفُ ليل اليوم التالي، فالفاتورةُ اتعدّت في الشهرين: '
            'ازدواجُ إيرادٍ عند كلّ حدّ شهر.',
      );
      expect(august.totalSales, closeTo(700, 0.01),
          reason: 'ضابط: لازم تظهر في شهرها');
    });

    test('نفسُ الحدّ على جانب المشتريات', () async {
      await purchase(no: 'P-BND', total: 900, date: boundary);

      final july = await db.getPurchasesReportAnalytics(
          DateTime(2026, 7, 1), DateTime(2026, 7, 31));
      final august = await db.getPurchasesReportAnalytics(
          DateTime(2026, 8, 1), DateTime(2026, 8, 31));

      expect(july.totalPurchases, closeTo(0, 0.01));
      expect(august.totalPurchases, closeTo(900, 0.01));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // H9
  // ═════════════════════════════════════════════════════════════════════════

  group('H9 — تبويبا التصنيف والنوع', () {
    final from = DateTime(2026, 7, 1);
    final to = DateTime(2026, 7, 31);

    test('التبويبان يعطيان نفسَ المجموع مع وجود مرتجعٍ وملغى', () async {
      final ok = await sale(no: 'S-1', total: 1600, date: DateTime(2026, 7, 4));
      await db.into(db.salesInvoiceItems).insert(SalesInvoiceItemsCompanion.insert(
            invoiceId: ok,
            productId: productId,
            quantity: 16,
            unitPrice: 100,
            total: 1600,
          ));
      // مرتجعٌ وملغى — لا يُحتسب أيٌّ منهما مبيعات.
      await sale(
          no: 'S-RET', total: 400, date: DateTime(2026, 7, 5), saleType: 'return');
      await sale(
          no: 'S-CAN',
          total: 250,
          date: DateTime(2026, 7, 6),
          status: 'cancelled');

      final byType = await db.getSalesBySaleType(from: from, to: to);
      final typeTotal = byType.fold<double>(0, (s, r) => s + r.total);

      expect(
        typeTotal,
        closeTo(1600, 0.01),
        reason: 'اتقاس ٢٬٢٥٠ — تبويبُ «حسب النوع» ما كانش بيستبعد المرتجعَ '
            'ولا الملغى بينما تبويبُ «حسب التصنيف» بيستبعدهما، فالتبويبان '
            'يعطيان مجموعَين مختلفَين لنفس المدى.',
      );
      expect(
        byType.any((r) => r.type == 'return'),
        isFalse,
        reason: '`GROUP BY sale_type` كان يُخرج مجموعةً اسمُها «return» ضمن '
            'أنواع البيع نفسِها.',
      );
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // H12
  // ═════════════════════════════════════════════════════════════════════════

  group('H12 — الخزينة: فلترُ المستخدم', () {
    final from = DateTime(2026, 7, 1);
    final to = DateTime(2026, 7, 31);

    Future<void> voucher({required int by, required double amount}) async {
      final safe = (await db.getDefaultSafeByType('cash'))!;
      await db.createSafeTransaction(SafeTransactionsCompanion.insert(
        voucherNumber: 'V-$by-${amount.toInt()}',
        safeId: safe.id,
        transactionType: 'receipt',
        category: 'other',
        amount: amount,
        balanceAfter: 0,
        userId: Value(by),
        createdAt: Value(DateTime(2026, 7, 10)),
      ));
    }

    test('البطاقاتُ تتبع فلترَ المستخدم كما يتبعه الجدول', () async {
      await voucher(by: userId, amount: 1000);
      await voucher(by: otherUserId, amount: 400);

      final rows = await db.getTransactionsByDateRange(from, to, userId: userId);
      final tableTotal = rows.fold<double>(0, (s, r) => s + r.amount);
      final cards =
          await db.getTreasuryReportAnalytics(from, to, userId: userId);

      expect(tableTotal, closeTo(1000, 0.01), reason: 'ضابط: الجدولُ يفلتر');
      expect(
        cards.totalReceipts,
        closeTo(1000, 0.01),
        reason: 'اتقاس ١٬٤٠٠ — البطاقةُ كانت تجمع كلَّ المستخدمين بينما '
            'الجدولُ تحتها يعرض واحداً: رقمان على نفس الشاشة وبنفس الفلتر.',
      );
    });

    test('ضابط: بلا فلتر، البطاقةُ تجمع الاتنين', () async {
      await voucher(by: userId, amount: 1000);
      await voucher(by: otherUserId, amount: 400);
      final cards = await db.getTreasuryReportAnalytics(from, to);
      expect(cards.totalReceipts, closeTo(1400, 0.01));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // H11
  // ═════════════════════════════════════════════════════════════════════════

  group('H11 — المصروفات: الإجماليُّ والجدول', () {
    final from = DateTime(2026, 7, 1);
    final to = DateTime(2026, 7, 31);

    /// ينشئ تصنيفاً ومصروفاً عليه، ثم يعطّل التصنيفَ اختيارياً — وهو ما يحصل
    /// فعلاً حين يقرّر المحاسبُ ألّا يُسجَّل على البند بعد اليوم.
    Future<void> expense({
      required String category,
      required double amount,
      bool deactivateAfter = false,
    }) async {
      final catId = await db.into(db.opExpenseCategories).insert(
            OpExpenseCategoriesCompanion.insert(name: category),
          );
      await db.into(db.opExpenses).insert(OpExpensesCompanion.insert(
            categoryId: catId,
            amount: amount,
            expenseDate: DateTime(2026, 7, 8),
            userId: userId,
          ));
      if (deactivateAfter) {
        await (db.update(db.opExpenseCategories)
              ..where((c) => c.id.equals(catId)))
            .write(const OpExpenseCategoriesCompanion(isActive: Value(false)));
      }
    }

    test('إجماليُّ البطاقة يساوي مجموعَ صفوف الجدول', () async {
      await expense(category: 'إيجار', amount: 1000);
      await expense(category: 'بند مُعطَّل', amount: 750, deactivateAfter: true);

      final summary =
          await db.getMonthlyExpenseSummary(from: from, to: to);
      final detail = await db.getExpensesForReport(from: from, to: to);

      final cardTotal = summary.fold<double>(
          0, (s, r) => s + ((r['total_amount'] as num?)?.toDouble() ?? 0));
      final tableTotal = detail.fold<double>(
          0, (s, r) => s + ((r['amount'] as num?)?.toDouble() ?? 0));

      expect(tableTotal, closeTo(1750, 0.01), reason: 'ضابط: الجدولُ يعرضهما');
      expect(
        cardTotal,
        closeTo(1750, 0.01),
        reason: 'اتقاس ١٬٠٠٠ — استعلامُ الملخّص كان يشترط `c.is_active` '
            'وجدولُ التفصيل لا يعرف الشرطَ أصلاً، فمصروفُ التصنيف المُعطَّل '
            'يظهر في الجدول ولا يدخل الإجمالي. وتعطيلُ التصنيف قرارٌ '
            'مستقبليٌّ لا يمحو مالاً أُنفق.',
      );
    });

    test('ضابط: التصنيفُ الفعّالُ الفارغ يفضل ظاهراً في الملخّص', () async {
      await db.into(db.opExpenseCategories).insert(
            OpExpenseCategoriesCompanion.insert(name: 'بند بلا صرف'),
          );
      final summary =
          await db.getMonthlyExpenseSummary(from: from, to: to);
      expect(summary.any((r) => r['name'] == 'بند بلا صرف'), isTrue,
          reason: 'الشاشةُ تعتمد على ظهور التصنيفات الفارغة');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // H8
  // ═════════════════════════════════════════════════════════════════════════

  group('H8 — تفاصيلُ الضريبة تطابق البطاقة', () {
    final from = DateTime(2026, 7, 1);
    final to = DateTime(2026, 7, 31);

    Future<void> taxedSale({
      required String no,
      required double tax,
      String saleType = 'default',
      String status = 'completed',
    }) async {
      await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
            invoiceNumber: no,
            warehouseId: warehouseId,
            userId: userId,
            invoiceDate: DateTime(2026, 7, 12),
            subtotal: const Value(1000),
            tax: Value(tax),
            total: Value(1000 + tax),
            paid: Value(1000 + tax),
            paymentMethod: const Value('cash'),
            saleType: Value(saleType),
            status: Value(status),
          ));
    }

    /// نفسُ الحساب الذي تجريه الشاشة على العمود: المرتجعُ يُطرح.
    double signedTaxSum(List<SalesInvoiceData> rows) => rows
        .where((s) => s.tax > 0)
        .fold<double>(
            0, (sum, s) => sum + (s.saleType == 'return' ? -s.tax : s.tax));

    test('مجموعُ عمود الضريبة = صافي المخرجات، لا جمعُ كلِّ شيء', () async {
      await taxedSale(no: 'TX-1', tax: 200);
      await taxedSale(no: 'TX-RET', tax: 50, saleType: 'return');
      await taxedSale(no: 'TX-CAN', tax: 55, status: 'cancelled');

      final rows = await db.getSalesByDateRange(from, to, excludeVoided: true);

      expect(
        rows.any((s) => s.invoiceNumber == 'TX-CAN'),
        isFalse,
        reason: 'الملغى كان يدخل التفصيل بينما بطاقةُ الأستاذ لا تراه.',
      );
      expect(
        rows.any((s) => s.invoiceNumber == 'TX-RET'),
        isTrue,
        reason: 'المرتجعُ لازم يفضل ظاهراً — إسقاطُه (‏`revenueOnly`) بيخفي '
            'عكسَ ضريبة المخرجات فيفتح فجوةً في الاتجاه المعاكس.',
      );
      expect(
        signedTaxSum(rows),
        closeTo(150, 0.01),
        reason: 'اتقاس ٢٥٥ — التفصيلُ كان يجمع الملغى (٥٥) ويجمع المرتجعَ '
            '**موجباً** (٥٠) بدل أن يطرحه. الصافي الصحيح ٢٠٠ − ٥٠ = ١٥٠.',
      );
    });

    test('ضابط: بلا الخيار، الملغى يعود ويظهر', () async {
      await taxedSale(no: 'TX-CAN2', tax: 55, status: 'cancelled');
      final rows = await db.getSalesByDateRange(from, to);
      expect(rows.any((s) => s.invoiceNumber == 'TX-CAN2'), isTrue,
          reason: 'الدلالةُ الافتراضيةُ ما اتغيّرتش — مسارُ المرتجعات '
              'بيعتمد عليها');
    });

    test('وفاتورةُ الحدّ لا تُحتسب في مدّتين', () async {
      await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
            invoiceNumber: 'TX-BND',
            warehouseId: warehouseId,
            userId: userId,
            invoiceDate: DateTime(2026, 8, 1),
            subtotal: const Value(1000),
            tax: const Value(90),
            total: const Value(1090),
            paid: const Value(1090),
            paymentMethod: const Value('cash'),
          ));

      final july = await db.getSalesByDateRange(from, to, excludeVoided: true);
      expect(july.any((s) => s.invoiceNumber == 'TX-BND'), isFalse,
          reason: '`isBetween` شاملُ الطرفين ونهايةُ المدى منتصفُ ليل اليوم '
              'التالي ⇒ فاتورةُ أوّل أغسطس كانت تظهر في يوليو كمان.');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // H14
  // ═════════════════════════════════════════════════════════════════════════

  group('H14 — طيُّ طرق الدفع إلى قنوات', () {
    test('العطبُ مقيس: الاستعلامُ يرجّع ثلاثةَ صفوفٍ لقناةٍ واحدة', () async {
      // ثلاثُ بيعاتٍ بثلاث قيمٍ خامٍ تقع كلُّها على «بطاقة/تحويل».
      for (final (i, m) in ['card', 'transfer', 'bank'].indexed) {
        await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
              invoiceNumber: 'PM-$m',
              warehouseId: warehouseId,
              userId: userId,
              invoiceDate: DateTime(2026, 7, 9),
              subtotal: Value(100.0 * (i + 1)),
              total: Value(100.0 * (i + 1)),
              paid: Value(100.0 * (i + 1)),
              paymentMethod: Value(m),
            ));
      }

      final raw = await db.getPaymentMethodStats(
          from: DateTime(2026, 7, 1), to: DateTime(2026, 7, 31));
      expect(
        raw.where((r) => paymentChannelOf(r.method) == PaymentChannel.card),
        hasLength(3),
        reason: 'ده أصلُ العطب: `GROUP BY payment_method` بيجمع بالقيمة '
            'الخام، والشاشةُ بتسمّي التلاتة «بطاقة/تحويل» ⇒ فطيرةٌ فيها '
            'نفسُ الاسم ٣ مرّاتٍ بـ٣ نسب.',
      );

      final folded = foldPaymentChannels(raw);
      expect(
        folded.where((c) => c.channel == PaymentChannel.card),
        hasLength(1),
        reason: 'الطيُّ لازم يخلّيها شريحةً واحدة',
      );
      expect(
          folded
              .firstWhere((c) => c.channel == PaymentChannel.card)
              .total,
          closeTo(600, 0.01));
    });

    test('card/transfer/bank تُطوى في قناةٍ واحدة', () {
      final folded = foldPaymentChannels(const [
        PaymentMethodStatRow(method: 'card', count: 1, total: 300),
        PaymentMethodStatRow(method: 'transfer', count: 1, total: 500),
        PaymentMethodStatRow(method: 'bank', count: 1, total: 200),
        PaymentMethodStatRow(method: 'cash', count: 2, total: 1000),
      ]);

      final card =
          folded.where((c) => c.channel == PaymentChannel.card).toList();
      expect(card, hasLength(1),
          reason: 'الاستعلامُ يجمع بالقيمة الخام فيرجّع ثلاثةَ صفوف، والشاشةُ '
              'تسمّيها كلَّها «بطاقة/تحويل» ⇒ ثلاثُ شرائحَ بنفس الاسم لا '
              'يستطيع القارئ جمعَها بعينه.');
      expect(card.single.total, closeTo(1000, 0.01));
      expect(card.single.count, 3);
    });

    test('المجهولُ يقع على «أخرى» ولا يُسقَط', () {
      final folded = foldPaymentChannels(const [
        PaymentMethodStatRow(method: 'crypto', count: 1, total: 90),
      ]);
      expect(folded, hasLength(1));
      expect(folded.single.channel, PaymentChannel.other);
      expect(folded.single.total, closeTo(90, 0.01),
          reason: 'إخفاءُ مبلغٍ من الفطيرة أسوأ من تسميته «أخرى»');
    });

    test('الترتيبُ ثابتٌ فلا تقفز الشرائحُ بين تحميلَين', () {
      final a = foldPaymentChannels(const [
        PaymentMethodStatRow(method: 'credit', count: 1, total: 10),
        PaymentMethodStatRow(method: 'cash', count: 1, total: 20),
      ]);
      final b = foldPaymentChannels(const [
        PaymentMethodStatRow(method: 'cash', count: 1, total: 20),
        PaymentMethodStatRow(method: 'credit', count: 1, total: 10),
      ]);
      expect(a.map((c) => c.channel).toList(),
          b.map((c) => c.channel).toList());
    });
  });
}
