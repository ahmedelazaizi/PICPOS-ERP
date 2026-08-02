// الجرد الفعلي كان بيطبّق **فرق قديم** بدل ما يوصل للكمية المعدودة.
//
// ── العطل ────────────────────────────────────────────────────────────────────
// `finalizeAudit` كان بيستعمل `item.difference` — لقطة اتحفظت وقت **العدّ**
// (`saveAuditItem`). مفيش قراءة جديدة للرصيد وقت الترحيل.
//
// أي حركة بين العدّ والترحيل بتخلّي الفرق ده قديم، والتطبيق بيوصل لرصيد
// **غير** الكمية المعدودة:
//
//   رصيد دفتري ١٠٠ · العدّ الفعلي ٩٥  ⇒  difference = ‎-٥
//   بيعة ١٠ بين العدّ والترحيل        ⇒  الرصيد ٩٠
//   بعد الترحيل: ٩٠ ‎- ٥ = **٨٥**     ⇒  والعدّ قال ٩٥
//
// يعني الفرق اتخصم مرتين فعلياً: البيعة + العجز القديم. والجرد — وهو
// الإجراء اللي المفروض **يصحّح** الرصيد — بقى مصدر انحراف جديد.
//
// ── المقارنة اللي بتحسم ─────────────────────────────────────────────────────
// الجرد الدوري (`cycle_count_dao.dart:400-407`) بيقرا الرصيد **طازج** جوه
// الترانزاكشن ويحسب `delta = counted − current`. النظامين في نفس الكودبيس
// وواحد بس منهم صح.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int productId;
  late int warehouseId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    warehouseId = await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(name: 'مخزن الجرد'),
        );
    productId = await db.into(db.products).insert(ProductsCompanion.insert(
          name: 'صنف الجرد',
          code: 'P-AUDIT',
          salePrice: const Value(20.0),
          costPrice: const Value(10.0),
        ));
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 100,
      type: 'in',
      postAdjustmentJournal: false,
    );
  });
  tearDown(() => db.close());

  Future<double> stockIn(int wid) async {
    final b = await (db.select(db.inventoryBalances)
          ..where((x) => x.productId.equals(productId) & x.warehouseId.equals(wid))
          ..limit(1))
        .getSingleOrNull();
    return b?.quantity ?? 0;
  }

  Future<int> makeAudit({required double counted, required double bookAtCount}) async {
    final auditId = await db.into(db.stockAudits).insert(StockAuditsCompanion.insert(
          warehouseId: Value(warehouseId),
          status: const Value('open'),
        ));
    await db.into(db.stockAuditItems).insert(StockAuditItemsCompanion.insert(
          auditId: auditId,
          productId: productId,
          expectedQuantity: bookAtCount,
          actualQuantity: counted,
          difference: counted - bookAtCount,
        ));
    return auditId;
  }

  test('الترحيل بيوصل للكمية المعدودة حتى لو حصلت بيعة بعد العدّ', () async {
    // العدّ: الدفتري ١٠٠ والفعلي ٩٥.
    final auditId = await makeAudit(counted: 95, bookAtCount: 100);

    // بيعة ١٠ بين العدّ والترحيل.
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: -10,
      type: 'out',
      postAdjustmentJournal: false,
    );
    expect(await stockIn(warehouseId), 90);

    await db.finalizeAudit(auditId);

    expect(await stockIn(warehouseId), 95,
        reason: 'الفرق القديم (-5) اتطبّق على 90 فبقى 85 — والعدّ قال 95');
  });

  test('من غير حركة بينهم النتيجة زي ما هي', () async {
    final auditId = await makeAudit(counted: 95, bookAtCount: 100);
    await db.finalizeAudit(auditId);
    expect(await stockIn(warehouseId), 95);
  });

  test('فائض جرد بيوصل للكمية المعدودة كمان', () async {
    final auditId = await makeAudit(counted: 110, bookAtCount: 100);
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: -10,
      type: 'out',
      postAdjustmentJournal: false,
    );

    await db.finalizeAudit(auditId);

    expect(await stockIn(warehouseId), 110);
  });

  test('عدّ مطابق للرصيد الحالي ما بيحركش حاجة', () async {
    final auditId = await makeAudit(counted: 100, bookAtCount: 100);
    await db.finalizeAudit(auditId);
    expect(await stockIn(warehouseId), 100);
  });
}
