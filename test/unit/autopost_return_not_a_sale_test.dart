// ═══════════════════════════════════════════════════════════════════════════
// فاتورة مرتجع ماينفعش تترحّل كـ«بيعة» — الحارس ناقص في الـDAO نفسه
// ═══════════════════════════════════════════════════════════════════════════
//
// `autoPostCashSale` / `autoPostCreditSale` بيرحّلوا قيد بيعة عادي:
//   مدين نقدية / دائن مبيعات · مدين تكلفة / دائن مخزون.
// وحارس التكرار الوحيد فيهم هو `hasAutoPostEntry('sale', sale.id)`
// (`accounting_autopost_dao.dart:249` و`:639`) — **ومفيش أي فحص لـ`saleType`**.
//
// وقيد المرتجع بيتخزّن بـ`referenceType = 'sales_return'`، يعني الحارس ده
// **ما بيشوفهوش**. فأي مُنادٍ بينده `autoPostCashSale` على فاتورة مرتجع
// بيضيف قيد بيعة **بعكس اتجاه** قيد المرتجع اللي اتكتب قبله.
//
// المسار الحيّ اللي بيعمل كده: `api_sales_handler.dart:353` بينده
// `autoPostCashSale(createdInv)` **بلا شرط** بعد ما `createSalesInvoice`
// تكون رحّلت المرتجع جوّاها (`sales_mutations_dao.dart:~473`). ده مسار
// «المرتجع السريع» من نقطة البيع في وضع client/mirror.
//
// الأثر على مرتجع نقدي بـ١٠٠ وتكلفة ٦٠:
//   قيد المرتجع:   نقدية −١٠٠ · مردودات +١٠٠ · مخزون +٦٠ · تكلفة −٦٠
//   قيد البيعة:    نقدية +١٠٠ · مبيعات +١٠٠ · مخزون −٦٠ · تكلفة +٦٠
//   الصافي:        نقدية **٠** بينما الدرج −١٠٠، ومخزون **٠** بينما الرف +١
//                  وإيراد وهمي ١٠٠ في قائمة الدخل.
//
// الحارس مكانه الـDAO مش المُنادِي: «قيد بيعة لفاتورة مرتجع» غلط **مهما كان
// اللي نداه**، والمنتج فيه أكتر من مسار بينده الدالتين دول.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int warehouseId;
  late int userId;

  setUp(() async {
    db = AppDatabase.forTesting();
    warehouseId = await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(name: 'مخزن المرتجعات'),
        );
    userId = await db.into(db.users).insert(
          UsersCompanion.insert(
            username: 'ret_cashier',
            passwordHash: 'x',
            displayName: 'كاشير',
          ),
        );
  });

  tearDown(() => db.close());

  Future<SalesInvoiceData> insertInvoice({required String saleType}) async {
    final id = await db.into(db.salesInvoices).insert(
          SalesInvoicesCompanion.insert(
            invoiceNumber: 'RET-$saleType-1',
            warehouseId: warehouseId,
            userId: userId,
            invoiceDate: DateTime(2026, 8, 4),
            subtotal: const Value(100),
            total: const Value(100),
            paid: const Value(100),
            cashPaid: const Value(100),
            paymentMethod: const Value('cash'),
            saleType: Value(saleType),
          ),
        );
    return (db.select(db.salesInvoices)..where((i) => i.id.equals(id)))
        .getSingle();
  }

  Future<int> journalEntryCount() async {
    final rows = await db.select(db.journalEntries).get();
    return rows.length;
  }

  test('autoPostCashSale بترفض فاتورة saleType == return', () async {
    final ret = await insertInvoice(saleType: 'return');
    final before = await journalEntryCount();

    final result = await db.autoPostCashSale(ret);

    expect(result, isNull,
        reason: 'قيد بيعة اتكتب لفاتورة مرتجع — بيعكس قيد المرتجع');
    expect(await journalEntryCount(), before,
        reason: 'مفيش أي قيد المفروض يتكتب');
  });

  test('autoPostCreditSale بترفض فاتورة saleType == return', () async {
    final ret = await insertInvoice(saleType: 'return');
    final before = await journalEntryCount();

    final result = await db.autoPostCreditSale(ret);

    expect(result, isNull);
    expect(await journalEntryCount(), before);
  });

  test('الضابط: فاتورة بيع عادية لسه بتترحّل', () async {
    // من غير الضابط ده، حارس بيرفض **كل حاجة** كان هيعدّي الاختبارين فوق.
    final sale = await insertInvoice(saleType: 'sale');

    final result = await db.autoPostCashSale(sale);

    expect(result, isNotNull,
        reason: 'الحارس أوسع من العطل — البيع العادي اتكسر');
    expect(await journalEntryCount(), greaterThan(0));
  });
}
