// ═══════════════════════════════════════════════════════════════════════════
// الهدرُ والتلفُ يُرحَّلان — ولا يُرحَّلان مرّتين
// ═══════════════════════════════════════════════════════════════════════════
//
// شاشتا المخزون تُصدران `movementType` من قائمةٍ واحدة: «إزالة» ⇒ `adjustment`
// و«هدر» ⇒ `waste` و«تالف» ⇒ `damage`. وكان `adjustmentAccountedTypes` يحوي
// الأوّلَ وحدَه، فخيارٌ في القائمة يُرحَّل وجاراه لا يُرحَّلان:
// **المخزونُ ينقص والأستاذُ لا يتحرّك** ⇒ الأصلُ والربحُ مبالَغٌ فيهما بقيمةِ
// كلِّ إعدامٍ يدويٍّ منذ أوّل يوم.
//
// ⚠️ وللإصلاح شقٌّ ثانٍ لا يقلّ أهمّيّة: مسارُ المرتجع التالف يستدعي
// `adjustStock(type: 'waste')` **ثمّ يرحّل قيدَه بنفسه**. فإضافةُ النوعَين
// بلا `postAdjustmentJournal: false` هناك تُنتج **ترحيلاً مزدوجاً**. الاختبارُ
// الأخيرُ هنا يحرس ذلك الشقَّ تحديداً.

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int warehouseId;
  late int productId;

  setUp(() async {
    db = AppDatabase.forTesting();
    final wh = await db.getDefaultWarehouse();
    warehouseId = wh!.id;
    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'WASTE-1',
        name: 'صنفُ اختبارِ الهدر',
        salePrice: const Value(50.0),
        costPrice: const Value(25.0),
        currentStock: const Value(0),
        trackInventory: const Value(true),
      ),
    );
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 40.0,
      type: 'in',
      unitCost: 25.0,
      notes: 'seed',
    );
  });

  tearDown(() async => db.close());

  /// صافي الحركة على شجرة حسابات المخزون الثلاثة (‏1131/1133/1136).
  Future<double> inventoryNet() async {
    final accounts = await db.select(db.accounts).get();
    final ids = accounts
        .where((a) =>
            a.code == '1131' || a.code == '1133' || a.code == '1136')
        .map((a) => a.id)
        .toSet();
    final lines = await db.select(db.journalEntryLines).get();
    return lines
        .where((l) => ids.contains(l.accountId))
        .fold<double>(0, (s, l) => s + l.debit - l.credit);
  }

  Future<int> jeCountFor(String refType, int refId) async {
    final rows = await (db.select(db.journalEntries)
          ..where((e) =>
              e.referenceType.equals(refType) & e.referenceId.equals(refId)))
        .get();
    return rows.length;
  }

  for (final type in const ['waste', 'damage']) {
    test('«$type» يُنقص المخزونَ **ويُرحّل** قيداً مقابلاً', () async {
      final before = await inventoryNet();

      await db.adjustStock(
        productId: productId,
        warehouseId: warehouseId,
        quantity: -4.0,
        type: type,
        notes: 'إعدامٌ يدويٌّ من شاشة المخزون',
      );

      final after = await inventoryNet();
      final stock = (await db.getProductById(productId))!.currentStock;

      expect(stock, 36.0, reason: 'المخزونُ الماديُّ نقص أربعَ وحدات');
      expect(after - before, closeTo(-100.0, 0.0001),
          reason: 'وحسابُ المخزون يجب أن ينقص ٤ × ٢٥ = ١٠٠ — '
              'بلا هذا السطر يبقى الأصلُ مبالَغاً فيه ١٠٠ إلى الأبد');
    });
  }

  test('«adjustment» ما زال يُرحّل كما كان — مرساةُ عدمِ الانحدار', () async {
    final before = await inventoryNet();
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: -4.0,
      type: 'adjustment',
      notes: 'إزالة',
    );
    expect(await inventoryNet() - before, closeTo(-100.0, 0.0001));
  });

  // ⚠️ **المرساةُ التي تُثبت أنّ الفحصَ يقيس شيئاً**: نوعٌ خارجَ المجموعة
  // (‏`in`) لا يُرحَّل من هنا. بدونها كان اختبارٌ يمرّ حتى لو رحّل كلَّ شيء.
  test('نوعٌ خارجَ المجموعة لا يُرحَّل من `adjustStock`', () async {
    final before = await inventoryNet();
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 5.0,
      type: 'transfer_in',
      unitCost: 25.0,
      notes: 'تحويل',
    );
    expect(await inventoryNet() - before, closeTo(0, 0.0001),
        reason: 'التحويلاتُ لها قيدُها المزدوجُ في مكانٍ آخر');
  });

  test('`postAdjustmentJournal: false` يمنع الترحيلَ — سياجُ المرتجع التالف',
      () async {
    // هذا ما يمرّره `returns_repository_impl` على شقِّ الإتلاف، لأنّه يرحّل
    // قيدَه بنفسه. بلا احترامِ هذا الوسيط يقع الترحيلُ مرّتين لكلِّ مرتجعٍ تالف.
    final before = await inventoryNet();
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: -4.0,
      type: 'waste',
      referenceType: 'sales_return_damaged',
      referenceId: 999,
      postAdjustmentJournal: false,
      notes: 'إتلافٌ مع مرتجع',
    );

    expect(await inventoryNet() - before, closeTo(0, 0.0001),
        reason: 'المنادي يرحّل بنفسه — فترحيلُ `adjustStock` هنا ازدواج');
    expect(await jeCountFor('sales_return_damaged', 999), 0);
    expect((await db.getProductById(productId))!.currentStock, 36.0,
        reason: 'والمخزونُ يتحرّك في الحالتين — السياجُ على القيد وحدَه');
  });
}
