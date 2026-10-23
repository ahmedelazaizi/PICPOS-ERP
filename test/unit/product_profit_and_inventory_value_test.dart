// ربحُ الصنف وقيمةُ المخزون بتاريخٍ ماضٍ.
//
// ═══ ما يحمي هذا الملفّ ═══
//
// استعلامان بُنيا بأمر المالك 2026-08-26، ولكلٍّ عطبٌ يمرّ صامتاً:
//
// **`getProductProfitReport`**
//  ‏١) **الإيرادُ شاملُ الضريبة** ⇒ هامشٌ منتفخٌ بنسبة الضريبة على كلّ صنف.
//     صنفٌ يبيع بخسارةٍ يظهر رابحاً، وهو عينُ ما يبحث عنه التقرير.
//  ‏٢) **التكلفةُ من `products.cost_price` لا من سطر البيع** ⇒ صنفٌ ارتفعت
//     تكلفتُه اليومَ يُتّهم بأنّه كان يبيع بخسارةٍ الشهرَ الماضي.
//  ‏٣) المرتجعُ والمحذوفُ يدخلان المجموع.
//
// **`getInventoryCostValueAt`**
//  ‏٤) **الإشارةُ مقلوبة** ⇒ الماضي يُقرأ أكبرَ كلّما بِيع أكثر. والحركةُ
//     موجبةٌ للوارد وسالبةٌ للصادر، فالرجوعُ يطرح لا يجمع.
//  ‏٥) **حركاتُ ما قبلَ التاريخ تُطرَح أيضاً** ⇒ رقمٌ لا معنى له.
//  ‏٦) صفرُ حركاتٍ بعد التاريخ ⇒ لا بدّ أن يساويَ القيمةَ الحاليّة بالضبط.
//
// ⚠️ ولا `db.close()`: انظر بقيّةَ ملفّات هذه السويّة.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int wh;
  late int user;
  late int cat;
  late int product;

  final from = DateTime(2026, 8, 1);
  final to = DateTime(2026, 8, 31, 23, 59, 59);

  setUp(() async {
    db = AppDatabase.forTesting();
    wh = await db
        .into(db.warehouses)
        .insert(WarehousesCompanion.insert(name: 'المخزن الرئيسي'));
    user = await db.into(db.users).insert(
          UsersCompanion.insert(
            username: 'cashier',
            passwordHash: 'x',
            displayName: 'كاشير',
          ),
        );
    cat = await db
        .into(db.categories)
        .insert(CategoriesCompanion.insert(name: 'مخبوزات'));
    product = await db.into(db.products).insert(
          ProductsCompanion.insert(
            code: 'P-001',
            name: 'خبز بلدي',
            categoryId: Value(cat),
            salePrice: const Value(10),
            // التكلفةُ **اليوم** ٩ — وسطرُ البيع سيحمل ٦، والفرقُ هو الفحص.
            costPrice: const Value(9),
            currentStock: const Value(100),
          ),
        );
  });

  Future<int> sale({
    required DateTime at,
    required double total,
    required double tax,
    required double qty,
    required double lineCost,
    String? saleType,
    String number = 'S1',
  }) async {
    final id = await db.into(db.salesInvoices).insert(
          SalesInvoicesCompanion.insert(
            invoiceNumber: number,
            warehouseId: wh,
            userId: user,
            invoiceDate: at,
            subtotal: Value(total - tax),
            tax: Value(tax),
            total: Value(total),
            saleType: Value.absentIfNull(saleType),
          ),
        );
    await db.into(db.salesInvoiceItems).insert(
          SalesInvoiceItemsCompanion.insert(
            invoiceId: id,
            productId: product,
            quantity: qty,
            unitPrice: total / qty,
            total: total,
            taxAmount: Value(tax),
            costPrice: Value(lineCost),
            quantityInBase: const Value(1),
          ),
        );
    return id;
  }

  group('ربحُ الصنف', () {
    test('الإيرادُ صافي الضريبة والتكلفةُ من سطر البيع', () async {
      // ١٠ قطع · إجمالي ١١٠ منها ١٠ ضريبة · تكلفةُ السطر ٦ للقطعة.
      await sale(
          at: DateTime(2026, 8, 5),
          total: 110,
          tax: 10,
          qty: 10,
          lineCost: 6);

      final row =
          (await db.getProductProfitReport(from: from, to: to)).single;

      expect(row.productName, 'خبز بلدي');
      expect(row.categoryName, 'مخبوزات');
      expect(row.quantity, 10);
      // ⚠️ ١٠٠ لا ١١٠ — الضريبةُ ليست إيراداً.
      expect(row.totalSales, 100,
          reason: 'الضريبةُ دخلت الإيرادَ فانتفخ الهامش');
      // ⚠️ ٦٠ لا ٩٠ — التكلفةُ لقطةُ وقتِ البيع لا تكلفةُ اليوم.
      expect(row.totalCost, 60,
          reason: 'التكلفةُ قُرئت من products.cost_price لا من سطر البيع');
      expect(row.profit, 40);
      expect(row.margin, 40);
      expect(row.averagePrice, 10);
      expect(row.averageCost, 6);
      expect(row.currentStock, 100);
    });

    test('المرتجعُ لا يدخل الحساب', () async {
      await sale(
          at: DateTime(2026, 8, 5),
          total: 110,
          tax: 10,
          qty: 10,
          lineCost: 6);
      await sale(
          at: DateTime(2026, 8, 6),
          total: 55,
          tax: 5,
          qty: 5,
          lineCost: 6,
          saleType: 'return',
          number: 'R1');

      final row =
          (await db.getProductProfitReport(from: from, to: to)).single;
      expect(row.quantity, 10, reason: 'كمّيّةُ المرتجع دخلت المبيعات');
      expect(row.totalSales, 100);
    });

    test('ما خارجَ المدى لا يُحتسَب، والمدى الفارغُ يعود فارغاً', () async {
      await sale(
          at: DateTime(2026, 7, 5),
          total: 110,
          tax: 10,
          qty: 10,
          lineCost: 6,
          number: 'S0');
      expect(await db.getProductProfitReport(from: from, to: to), isEmpty);
    });

    test('إيرادٌ صفرٌ ⇒ هامشٌ صفرٌ لا لانهاية', () async {
      // بيعٌ بخصمٍ كامل: الإجمالي صفرٌ والتكلفةُ حقيقيّة.
      await sale(
          at: DateTime(2026, 8, 5), total: 0, tax: 0, qty: 4, lineCost: 6);
      final row =
          (await db.getProductProfitReport(from: from, to: to)).single;
      expect(row.totalSales, 0);
      expect(row.totalCost, 24);
      expect(row.margin, 0, reason: 'قسمةٌ على صفرٍ تسرّبت إلى الهامش');
      expect(row.margin.isNaN, isFalse);
    });
  });

  group('قيمةُ المخزون بتاريخٍ ماضٍ', () {
    Future<void> move({required DateTime at, required double qty}) async {
      await db.into(db.stockMovements).insert(
            StockMovementsCompanion.insert(
              productId: product,
              warehouseId: wh,
              movementType: qty >= 0 ? 'in' : 'out',
              quantity: qty,
              balanceAfter: 0,
              referenceType: const Value('test'),
              createdAt: Value(at),
            ),
          );
    }

    test('بلا حركاتٍ بعد التاريخ ⇒ القيمةُ الحاليّةُ نفسُها', () async {
      // ١٠٠ قطعة × ٩ = ٩٠٠.
      final v = await db.getInventoryCostValueAt(DateTime(2026, 8, 31));
      expect(v, 900);
    });

    test('الرجوعُ يطرح الوارد ويردّ الصادر', () async {
      // بعد ١٠ أغسطس: دخل ٣٠ وخرج ٥٠ ⇒ صافي −٢٠.
      // فرصيدُ ١٠ أغسطس = ١٠٠ − (−٢٠) = ١٢٠ قطعة × ٩ = ١٠٨٠.
      await move(at: DateTime(2026, 8, 15), qty: 30);
      await move(at: DateTime(2026, 8, 20), qty: -50);

      final v = await db.getInventoryCostValueAt(DateTime(2026, 8, 10));
      expect(v, 1080,
          reason: 'الإشارةُ مقلوبةٌ — الرجوعُ يطرح صافيَ ما بعد التاريخ');
    });

    test('حركاتُ ما قبلَ التاريخ لا تُطرَح', () async {
      await move(at: DateTime(2026, 8, 1), qty: 40); // قبلَ نقطة القياس
      await move(at: DateTime(2026, 8, 20), qty: -50); // بعدَها

      // ١٠٠ − (−٥٠) = ١٥٠ × ٩ = ١٣٥٠ — والأربعون لا شأنَ لها.
      final v = await db.getInventoryCostValueAt(DateTime(2026, 8, 10));
      expect(v, 1350, reason: 'حركةٌ سابقةٌ للتاريخ دخلت الحساب');
    });

    test('الحركةُ المحذوفةُ ناعماً لا تُحتسَب', () async {
      await db.into(db.stockMovements).insert(
            StockMovementsCompanion.insert(
              productId: product,
              warehouseId: wh,
              movementType: 'out',
              quantity: -50,
              balanceAfter: 0,
              referenceType: const Value('test'),
              createdAt: Value(DateTime(2026, 8, 20)),
              deletedAt: Value(DateTime(2026, 8, 21)),
            ),
          );
      final v = await db.getInventoryCostValueAt(DateTime(2026, 8, 10));
      expect(v, 900, reason: 'حركةٌ محذوفةٌ ناعماً حُسبت');
    });

    test('قائمةُ مخازنَ فارغةٌ تعني «لا شيء» لا «الكلّ»', () async {
      // عقدُ FIL-3 نفسُه في بقيّة استعلامات المخزون.
      expect(
        await db.getInventoryCostValueAt(DateTime(2026, 8, 10),
            warehouseIds: const []),
        0,
      );
    });
  });
}
