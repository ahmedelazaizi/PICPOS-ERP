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
}
