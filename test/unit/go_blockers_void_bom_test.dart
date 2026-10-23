// ═══════════════════════════════════════════════════════════════════════════
// مانعُ Go ٢‑٩ — الإبطالُ يعيد خاماتِ قائمة المكوّنات
// ═══════════════════════════════════════════════════════════════════════════
//
// صنفٌ مركَّبٌ (‏وجبةٌ لها قائمةُ مكوّنات) لا يخرج من المخزون بنفسه — الذي
// يخرج **خاماتُه**. و`voidSalesInvoice` كان يعيد الصنفَ المباعَ ولا يعيدها،
// بينما القيدُ المحاسبيُّ يعكس قيدَ البيع سطراً بسطر ومنه رجلُ تكلفةِ تلك
// الخامات.
//
// فالنتيجةُ اتّجاهٌ واحدٌ لا يتصفّى: الأستاذُ يرتفع والكمّيّاتُ تبقى ناقصة —
// أي أنّ تقييمَ المخزون ينخفض عن حساب المخزون في الأستاذ مع **كلِّ** إبطال.
//
// والقياسُ هنا على **الكمّيّات في المستودع** لا على قيمةٍ مرتجَعةٍ من دالّة.

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:picpos_erp/core/utils/uuid_v7.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int warehouseId;
  late int branchId;
  late int mealId;
  late int meatId;
  late int spiceId;
  late int userId;

  const meatPerMeal = 1.0;
  const spicePerMeal = 0.01;
  const seededStock = 100.0;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.seedChartOfAccounts();

    final wh = await db.getDefaultWarehouse();
    warehouseId = wh!.id;
    branchId = wh.branchId ?? 1;

    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(
            name: 'مدير اختبار الإبطال',
            isSystemRole: const Value(true),
          ),
        );
    userId = await db.createUser(
      username: 'void-bom-tester',
      password: 'pw',
      displayName: 'Void BOM Tester',
      roleId: roleId,
    );

    mealId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'GO-MEAL',
        name: 'وجبة',
        salePrice: const Value(50.0),
        costPrice: const Value(20.0),
        // الصنفُ المركَّبُ لا يُتابَع مخزونُه: يُركَّب عند البيع.
        trackInventory: const Value(false),
        allowNegativeSale: const Value(true),
      ),
    );
    meatId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'GO-MEAT',
        name: 'لحمة',
        costPrice: const Value(11.0),
        trackInventory: const Value(true),
        allowNegativeSale: const Value(true),
      ),
    );
    spiceId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'GO-SPICE',
        name: 'بهارات',
        costPrice: const Value(2.0),
        trackInventory: const Value(true),
        allowNegativeSale: const Value(true),
      ),
    );

    final bomId = await db.createBOM(
      finishedProductId: mealId,
      bomCode: 'GO-BOM-MEAL',
      expectedQuantity: 1.0,
      components: [
        {'rawMaterialId': meatId, 'quantity': meatPerMeal,
          'wastagePercent': 0.0},
        {'rawMaterialId': spiceId, 'quantity': spicePerMeal,
          'wastagePercent': 0.0},
      ],
    );
    await (db.update(db.billOfMaterials)..where((b) => b.id.equals(bomId)))
        .write(const BillOfMaterialsCompanion(
      autoDepleteOnSale: Value(true),
      depletionPolicy: Value('always_auto_deplete'),
    ));

    for (final p in [meatId, spiceId]) {
      await db.adjustStock(
          productId: p,
          warehouseId: warehouseId,
          quantity: seededStock,
          type: 'initial');
    }
  });

  tearDown(() => db.close());

  Future<double> stockOf(int productId) async {
    final row = await (db.select(db.inventoryBalances)
          ..where((b) =>
              b.productId.equals(productId) &
              b.warehouseId.equals(warehouseId)))
        .getSingleOrNull();
    return row?.quantity ?? 0.0;
  }

  /// فاتورةُ بيعٍ **آجلة** (‏`paid: 0`) عمداً: الإبطالُ لفاتورةٍ مدفوعةٍ
  /// بالكامل يمرّ بفحصِ `voidPaidInvoice` الحرج، وهذا الملفُّ عن المخزون لا
  /// عن الصلاحيّات.
  Future<({int id, int itemId})> sellMeals(double qty) async {
    final gid = UuidV7.generate();
    final invoiceId = await db.createSalesInvoice(
      invoiceNumber: 'GO-VOID-${DateTime.now().microsecondsSinceEpoch}',
      warehouseId: warehouseId,
      userId: userId,
      subtotal: 50.0 * qty,
      discount: 0.0,
      tax: 0.0,
      total: 50.0 * qty,
      paid: 0.0,
      paymentMethod: 'آجل',
      branchId: branchId,
      globalId: gid,
      items: [
        SalesInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: mealId,
          quantity: qty,
          unitPrice: 50.0,
          total: 50.0 * qty,
          sortOrder: const Value(1),
        ),
      ],
    );
    final items = await db.getSalesInvoiceItems(invoiceId);
    await db.transaction(() async {
      await db.applyAutoDepleteForSale(
        saleInvoiceId: invoiceId,
        saleGlobalId: gid,
        branchId: branchId,
        shortagePolicy: 'allow_negative',
        items: [
          SaleLineRef(
            saleItemId: items.first.id,
            productId: mealId,
            qty: qty,
            warehouseId: warehouseId,
          ),
        ],
      );
    });
    return (id: invoiceId, itemId: items.first.id);
  }

  test('إبطالُ بيعةِ صنفٍ مركَّبٍ يعيد خاماتِه إلى المستودع', () async {
    final sale = await sellMeals(3);

    // شرطٌ مسبق: الخاماتُ خرجت فعلاً.
    expect(await stockOf(meatId), closeTo(seededStock - 3 * meatPerMeal, 0.001),
        reason: 'الاستنزافُ لم يحدث — التجهيزةُ نفسُها لم تصل');
    expect(await stockOf(spiceId),
        closeTo(seededStock - 3 * spicePerMeal, 0.001));

    await db.voidSalesInvoice(sale.id, reason: 'اختبار', deletedBy: userId);

    // 🔴 المعطوب: تبقى ٩٧ و٩٩٫٩٧ إلى الأبد بينما الأستاذُ يعود إلى قيمته
    //    الأصليّة ⇒ التقييمُ أقلُّ من الأستاذ بقيمة الخامات.
    expect(await stockOf(meatId), closeTo(seededStock, 0.001),
        reason: 'اللحمةُ تعود كاملةً بعد الإبطال');
    expect(await stockOf(spiceId), closeTo(seededStock, 0.001),
        reason: 'البهاراتُ تعود كاملةً بعد الإبطال');
  });

  test('صفوفُ الاستهلاك تُوسَم مُعادةً — فإعادةُ الإبطال لا تُضاعف', () async {
    final sale = await sellMeals(2);
    await db.voidSalesInvoice(sale.id, reason: 'اختبار', deletedBy: userId);

    final rows = await (db.select(db.saleBomConsumptions)
          ..where((c) => c.saleInvoiceId.equals(sale.id)))
        .get();
    expect(rows, isNotEmpty, reason: 'مرساةٌ: صفوفُ الاستهلاك موجودة');
    expect(rows.every((r) => r.reversedByReturnId != null), isTrue,
        reason: 'الوسمُ هو ما يجعل العمليّةَ لا تتكرّر');

    // إبطالٌ ثانٍ يُرفَض بحكم الحالة — والمهمُّ أنّ المخزونَ لم يتحرّك مرّةً
    // ثانيةً حتّى لو وصل نداءٌ مكرَّر.
    await expectLater(
      db.voidSalesInvoice(sale.id, reason: 'مكرّر', deletedBy: userId),
      throwsA(anything),
    );
    expect(await stockOf(meatId), closeTo(seededStock, 0.001),
        reason: 'لا إعادةَ مضاعفةٌ للخامات');
  });
}
