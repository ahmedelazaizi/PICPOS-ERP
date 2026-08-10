// ═══════════════════════════════════════════════════════════════════════════
// §٣-أ — تقريرُ المبيعات صافياً من المرتجعات · على قاعدةٍ حقيقية
// ═══════════════════════════════════════════════════════════════════════════
//
// البلاغ: فاتورةٌ بـ١٨ ثم مرتجعٌ جزئيٌّ بـ٤ — تقريرُ المبيعات لم يخصم الأربعة،
// فاختلف عن شاشة الفواتير وعن لوحة التحكم.
//
// الشاشتان كانتا تختلفان **بالبناء**: `sales_invoices_controller` ينده
// `getReturnedAmountsForInvoices` ويطرح، و`sales_report_screen` لم يكن ينده
// المرتجعاتِ ولا مرّةً واحدة — نفسُ القاعدة، واحدةٌ تطرح وأخرى لا.
//
// هذا الملفّ يقفل التركيبةَ التي تنفّذها الشاشة على قاعدةٍ حقيقية:
//     صافٍ = getSalesAnalytics (مجملاً)
//           − Σ min(getReturnedAmountsForInvoices[id], total) على **المعروض**
//
// والمصدرُ يغطّي الشكلين معاً كما يقتضي §٣-أ-٦:
//   • الشكل (أ) — حركةُ خزينةٍ `reference_type='sales_return'`
//     (‏التنصيبُ المستقلّ: `processSalesReturn` يقلب حالةَ الأصل ويكتب صفَّ
//      خزينةٍ فقط، ولا يكتب مستندَ مرتجعٍ إطلاقاً)
//   • الشكل (ب) — مستندُ `sale_type='return'` مربوطٌ بالأصل عبر
//     `notes = 'Return for invoice #<id>'` (مسارُ السيرفر)
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/models/sales_returns_netting.dart';

void main() {
  late AppDatabase db;
  late int productId;
  late int userId;

  final from = DateTime(2026, 1, 1);
  final to = DateTime(2026, 12, 31);
  final saleDate = DateTime(2026, 6, 1);

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(name: 'مخزن المرتجعات'),
        ); // id = 1
    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(name: 'مدير', isSystemRole: const Value(true)),
        );
    userId = await db.into(db.users).insert(
          UsersCompanion.insert(
            username: 'net_returns_user',
            passwordHash: 'x',
            displayName: 'مستخدم',
            roleId: Value(roleId),
          ),
        );
    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'P-NET',
        name: 'صنف',
        salePrice: const Value(18.0),
        costPrice: const Value(12.0),
        trackInventory: const Value(false),
      ),
    );
  });

  tearDown(() async => db.close());

  /// فاتورةُ بيعٍ اعتيادية بقيمة [total].
  Future<int> sale(String number, double total) => db.createSalesInvoice(
        invoiceNumber: number,
        warehouseId: 1,
        userId: userId,
        subtotal: total,
        discount: 0,
        tax: 0,
        total: total,
        paid: total,
        paymentMethod: 'cash',
        invoiceDate: saleDate,
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 1.0,
            unitPrice: total,
            total: total,
          ),
        ],
      );

  /// يقلب حالةَ الأصل كما يفعل `processSalesReturn`.
  Future<void> setStatus(int invoiceId, String status) async {
    await (db.update(db.salesInvoices)..where((t) => t.id.equals(invoiceId)))
        .write(SalesInvoicesCompanion(status: Value(status)));
  }

  /// الشكل (أ) — استردادُ خزينة، بلا مستندِ مرتجع.
  Future<void> returnViaSafe(int originalId, double amount) async {
    await db.into(db.safeTransactions).insert(
          SafeTransactionsCompanion.insert(
            safeId: 1,
            transactionType: 'payment',
            voucherNumber: 'SRET-SAFE-$originalId',
            amount: amount,
            balanceAfter: 0,
            category: 'sales_return',
            referenceType: const Value('sales_return'),
            referenceId: Value(originalId),
            createdAt: Value(saleDate),
          ),
        );
  }

  /// الشكل (ب) — مستندُ مرتجعٍ مربوطٌ بالأصل عبر `notes`.
  Future<void> returnViaDocument(int originalId, double amount) =>
      db.createSalesInvoice(
        invoiceNumber: 'SRET-DOC-$originalId',
        warehouseId: 1,
        userId: userId,
        subtotal: amount,
        discount: 0,
        tax: 0,
        total: amount,
        paid: amount,
        paymentMethod: 'cash',
        saleType: 'return',
        notes: 'Return for invoice #$originalId',
        invoiceDate: saleDate,
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 1.0,
            unitPrice: amount,
            total: amount,
          ),
        ],
      );

  /// نفسُ التركيبة التي تنفّذها `sales_report_screen._loadData`.
  Future<({double gross, double returned, double net})> reportFigures() async {
    final analytics = await db.getSalesAnalytics(from, to);
    final displayed = await db.getSalesByDateRange(from, to, revenueOnly: true);
    final returnedByInvoice =
        await db.getReturnedAmountsForInvoices([for (final i in displayed) i.id]);
    final returned = clampedReturnedTotal(
      returnedByInvoice: returnedByInvoice,
      displayedInvoiceTotals: {for (final i in displayed) i.id: i.total},
    );
    final net = netOfReturns(analytics, returned);
    return (
      gross: analytics.totalSales,
      returned: returned,
      net: net.totalSales,
    );
  }

  group('أرقامُ البلاغ — ١٨ ثم مرتجعٌ جزئيٌّ بـ٤', () {
    test('الشكل (ب): مستندُ مرتجع ⇒ الصافي ١٤', () async {
      final id = await sale('INV-B', 18);
      await returnViaDocument(id, 4);
      await setStatus(id, 'partial_return');

      final f = await reportFigures();
      // المجملُ يحتسب الفاتورةَ كاملةً — حالتُها `partial_return` فلا
      // يستثنيها الاستعلام، ومستندُ المرتجع مستثنىً بـ`sale_type != 'return'`.
      expect(f.gross, 18.0, reason: 'المجمل يحتسب المرتجَعةَ جزئياً كاملةً');
      expect(f.returned, 4.0);
      expect(f.net, 14.0);
    });

    test('الشكل (أ): استردادُ خزينةٍ بلا مستند ⇒ الصافي ١٤', () async {
      // هذا هو التنصيبُ المستقلّ: لا صفَّ `sale_type='return'` إطلاقاً.
      final id = await sale('INV-A', 18);
      await returnViaSafe(id, 4);
      await setStatus(id, 'partial_return');

      final f = await reportFigures();
      expect(f.gross, 18.0);
      expect(f.returned, 4.0);
      expect(f.net, 14.0);
    });

    test('الشكلان مجتمعَين على فاتورةٍ واحدة — جمعٌ لا استبدال', () async {
      // `getReturnedAmountsForInvoices` يجمع المصدرَين عمداً (موثَّقٌ عنده)،
      // وهو ما يغذّي «المتبقي» في شاشة الفواتير. فالتقريرُ يتبع نفسَ الدلالة
      // حرفياً وإلا اختلفت الشاشتان من جديد.
      final id = await sale('INV-AB', 18);
      await returnViaSafe(id, 4);
      await returnViaDocument(id, 4);
      await setStatus(id, 'partial_return');

      final f = await reportFigures();
      expect(f.gross, 18.0);
      expect(f.returned, 8.0);
      expect(f.net, 10.0);
    });

    test('ردٌّ يتجاوز الفاتورةَ يُقَصُّ — لا سطرَ سالبٍ يقاصّ فواتيرَ أخرى',
        () async {
      final big = await sale('INV-BIG', 18);
      await sale('INV-OTHER', 30);
      // ٢٥ على فاتورةِ ١٨ (مثلاً بازدواج مصدرَين) — بلا قصٍّ يصير هذا
      // السطرُ −٧ فيأكل من مبيعات INV-OTHER ويعطي صافياً ٤١ بدل ٣٠.
      await returnViaSafe(big, 25);
      await setStatus(big, 'partial_return');

      final f = await reportFigures();
      expect(f.gross, 48.0);
      expect(f.returned, 18.0, reason: 'مقصوصٌ عند قيمة الفاتورة');
      expect(f.net, 30.0, reason: 'مبيعاتُ INV-OTHER سليمةٌ لم يأكلها القصّ');
    });
  });

  group('المرتجعُ الكامل — لا يُطرح مرّتين', () {
    test('الفاتورةُ المرتجَعةُ كلياً خارجَ المجمل وخارجَ الحسم', () async {
      final id = await sale('INV-FULL', 18);
      await returnViaDocument(id, 18);
      await setStatus(id, 'returned');

      final f = await reportFigures();
      // مستثناةٌ بـ`status IN ('returned',…)` ⇒ لم تدخل المجملَ أصلاً.
      expect(f.gross, 0.0);
      // وليست في القائمة المعروضة ⇒ لا تُحسم. لولا ذلك لصار الصافي −١٨.
      expect(f.returned, 0.0);
      expect(f.net, 0.0);
    });

    test('كاملةٌ بجوار جزئيةٍ — تُحسم الجزئيةُ وحدَها', () async {
      final full = await sale('INV-F', 18);
      await returnViaDocument(full, 18);
      await setStatus(full, 'returned');

      final partial = await sale('INV-P', 50);
      await returnViaSafe(partial, 10);
      await setStatus(partial, 'partial_return');

      final f = await reportFigures();
      expect(f.gross, 50.0);
      expect(f.returned, 10.0);
      expect(f.net, 40.0);
    });
  });

  group('حالاتُ الحدّ', () {
    test('بلا مبيعاتٍ ولا مرتجعات ⇒ أصفارٌ بلا NaN', () async {
      final f = await reportFigures();
      expect(f.gross, 0.0);
      expect(f.returned, 0.0);
      expect(f.net, 0.0);
      expect(f.net.isNaN, isFalse);
    });

    test('مبيعاتٌ بلا مرتجعاتٍ ⇒ الصافي = المجمل', () async {
      await sale('INV-1', 18);
      await sale('INV-2', 30);
      final f = await reportFigures();
      expect(f.gross, 48.0);
      expect(f.returned, 0.0);
      expect(f.net, 48.0);
    });
  });
}
