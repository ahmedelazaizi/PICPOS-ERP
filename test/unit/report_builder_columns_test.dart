// ═══════════════════════════════════════════════════════════════════════════
// منشئ التقارير كان بيخترع بيانات — أعمدة ثابتة باسم حقول حقيقية.
// ═══════════════════════════════════════════════════════════════════════════
//
// `getAvailableFields` بيعرض للمستخدم «حالة الدفع» و«نوع البيع» كحقول يختارها،
// و`_buildReportQuery` كان بيترجمهم لنصوص **ثابتة**:
//
//     if (col == 'payment_status') return "'مكتمل' AS payment_status";
//     if (col == 'sale_type')      return "'أجل'  AS sale_type";
//
// يعني كل صف في التقرير بيقول «مكتمل» و«أجل» مهما كانت الحقيقة. ده أسوأ من
// عمود ناقص: عمود ناقص بيبان، وعمود مُختلَق بيتقرا كأنه بيانات.
//
// و`sale_type` غلط مرتين: العمود **موجود فعلاً** في sales_invoices، وقيمه
// (default/talabat/careem/ashyae — sales_purchase_tables.dart:202) مالهاش
// علاقة بـ«أجل» أصلاً. «أجل مقابل نقدي» دلالتها payment_method == 'credit'.
//
// و`payment_status` مش عمود في الجدول خالص — لازم يُشتق من paid مقابل total.
//
// وعطل تالت: `LEFT JOIN inventory_balances` في تقارير الأصناف بلا تجميع ⇒
// الصنف الموجود في مخزنين بيطلع **صفّين** في التقرير، فأي جمع لعمود بيتضاعف.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int warehouseId;
  late int warehouseBId;

  Future<int> makeReport({
    required String sourceEntity,
    required String columns,
  }) =>
      db.into(db.customReports).insert(CustomReportsCompanion.insert(
            name: 'تقرير اختبار',
            sourceEntity: sourceEntity,
            columns: columns,
          ));

  Future<void> insertInvoice({
    required String number,
    required double total,
    required double paid,
    String saleType = 'default',
  }) =>
      db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
            invoiceNumber: number,
            warehouseId: warehouseId,
            userId: 1,
            invoiceDate: DateTime(2026, 8, 1),
            total: Value(total),
            paid: Value(paid),
            saleType: Value(saleType),
          ));

  setUp(() async {
    db = AppDatabase.forTesting();
    warehouseId = await db
        .into(db.warehouses)
        .insert(WarehousesCompanion.insert(name: 'مخزن أ'));
    warehouseBId = await db
        .into(db.warehouses)
        .insert(WarehousesCompanion.insert(name: 'مخزن ب'));
  });

  tearDown(() => db.close());

  group('حالة الدفع لازم تُشتق مش تُختلق', () {
    setUp(() async {
      await insertInvoice(number: 'PAID', total: 100, paid: 100);
      await insertInvoice(number: 'PARTIAL', total: 100, paid: 40);
      await insertInvoice(number: 'UNPAID', total: 100, paid: 0);
    });

    test('كل فاتورة بتدي حالتها الحقيقية', () async {
      final id = await makeReport(
          sourceEntity: 'sales_invoices',
          columns: 'invoice_number,payment_status');
      final rows = await db.executeReport(id);
      final byNumber = {
        for (final r in rows) r['invoice_number'] as String: r['payment_status']
      };
      expect(byNumber['PAID'], 'مكتمل');
      expect(byNumber['PARTIAL'], 'جزئي',
          reason: 'كانت بتقول «مكتمل» لفاتورة مدفوع منها ٤٠٪');
      expect(byNumber['UNPAID'], 'غير مدفوع',
          reason: 'كانت بتقول «مكتمل» لفاتورة ما اتدفعش منها مليم');
    });
  });

  group('نوع البيع لازم ييجي من العمود الحقيقي', () {
    setUp(() async {
      await insertInvoice(
          number: 'A', total: 10, paid: 10, saleType: 'default');
      await insertInvoice(
          number: 'B', total: 10, paid: 10, saleType: 'talabat');
    });

    test('القيم بتطابق المخزَّن مش نص ثابت', () async {
      final id = await makeReport(
          sourceEntity: 'sales_invoices', columns: 'invoice_number,sale_type');
      final rows = await db.executeReport(id);
      final byNumber = {
        for (final r in rows) r['invoice_number'] as String: r['sale_type']
      };
      expect(byNumber['A'], 'default');
      expect(byNumber['B'], 'talabat',
          reason: 'كانت بتقول «أجل» للاتنين — وقيمة مش من مجال العمود أصلاً');
    });
  });

  group('صنف في مخزنين = صف واحد مش صفّين', () {
    test('التقرير ما بيتضاعفش بعدد المخازن', () async {
      final productId = await db.into(db.products).insert(
          ProductsCompanion.insert(name: 'مكرونة', code: 'P-1'));
      for (final w in [warehouseId, warehouseBId]) {
        await db.into(db.inventoryBalances).insert(
            InventoryBalancesCompanion.insert(
                productId: productId,
                warehouseId: w,
                quantity: const Value(5)));
      }

      final id = await makeReport(
          sourceEntity: 'products', columns: 'name,quantity');
      final rows = await db.executeReport(id);
      expect(rows.length, 1,
          reason: 'الـLEFT JOIN بلا تجميع كان بيطلّع صف لكل مخزن');
      expect((rows.single['quantity'] as num).toDouble(), 10,
          reason: 'الكمية المعروضة لازم تكون إجمالي المخازن');
    });
  });
}
