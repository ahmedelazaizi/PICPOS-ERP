// ═══════════════════════════════════════════════════════════════════════════
// SAL-1 (الامتدادُ الثاني) — quantityInBase في تكلفةِ سلسلةِ الأداء الشهريّة
// ═══════════════════════════════════════════════════════════════════════════
//
// `accounting_autopost_dao.dart` يوثّق الدلالةَ حرفيّاً:
//   «quantity is in SALE units, cost_price is per BASE unit (WAC)»
// فيضرب في `quantity_in_base` عند ترحيل COGS إلى الأستاذ — وكذلك تفعل ثلاثةٌ
// من أربعةِ استعلاماتِ التكلفة في `sales_analytics_dao.dart` (‏:264 · :906 ·
// :1298). الاستعلامُ الرابعُ — تكلفةُ [getMonthlyPerformanceSeries] — كان
// يجمع `quantity * cost_price` فقط، فيُنقص التكلفةَ بمقدارِ معاملِ التحويل
// على كلّ بيعةِ كرتونة. والدالّةُ حيّةٌ: `analytics_picpos_screen.dart:149`
// تبني منها بطاقاتِ التكلفةِ وهامشِ الربح، فالشاشةُ كانت تخالف الأستاذَ
// على نفسِ الفاتورةِ بعينها.
//
// ولذلك يقيس هذا الاختبارُ الرقمَين معاً: القيمةَ المطلقةَ المحسوبةَ يدويّاً،
// **وتطابُقَها مع ما رُحِّل فعلاً إلى حساب COGS في الأستاذ**.
//
// تجهيزةُ القاعدة منقولةٌ عن `test/unit/sales_cogs_uom_autopost_test.dart`.

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int userId;
  late int warehouseId;
  late int productId;

  setUp(() async {
    db = AppDatabase.forTesting();

    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(name: 'كاشير', isSystemRole: const Value(false)),
        );
    userId = await db.createUser(
      username: 'analytics_uom_user',
      password: 'test',
      displayName: 'Analytics UOM User',
      roleId: roleId,
    );

    final wh = await db.getDefaultWarehouse();
    warehouseId = wh!.id;

    // costPrice بالوحدةِ الأساس (قطعة).
    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'ANL-UOM-1',
        name: 'منتج بوحدة كرتون',
        salePrice: const Value(300.0),
        costPrice: const Value(10.0),
        currentStock: const Value(1000.0),
        trackInventory: const Value(true),
      ),
    );
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 1000.0,
      type: 'in',
      notes: 'seed',
    );
  });

  tearDown(() async => db.close());

  /// تكلفةُ المبيعاتِ كما رُحِّلت فعلاً إلى حساب `5211` في الأستاذ.
  Future<double> postedCogsFor(int invoiceId) async {
    final entry = await (db.select(db.journalEntries)
          ..where((e) =>
              e.referenceType.equals('sale') & e.referenceId.equals(invoiceId)))
        .getSingle();
    final lines = await (db.select(db.journalEntryLines)
          ..where((l) => l.entryId.equals(entry.id)))
        .get();
    final cogsAcc = await db.getAccountByCode('5211');
    final cogsLine = lines.firstWhere((l) => l.accountId == cogsAcc!.id);
    return cogsLine.debit;
  }

  /// السلسلةُ الشهريّةُ مجموعةً على المدى — تفادياً لهشاشةِ مفتاحِ الشهر
  /// حين يقع التشغيلُ على حدِّ شهرَين.
  Future<({double netSales, double cogs})> seriesTotals() async {
    final now = DateTime.now();
    final rows = await db.getMonthlyPerformanceSeries(
      from: now.subtract(const Duration(days: 2)),
      to: now.add(const Duration(days: 2)),
    );
    var netSales = 0.0;
    var cogs = 0.0;
    for (final r in rows) {
      netSales += (r['net_sales'] as num).toDouble();
      cogs += (r['cogs'] as num).toDouble();
    }
    return (netSales: netSales, cogs: cogs);
  }

  Future<int> sellCartons({
    required String invoiceNumber,
    required double quantity,
    required double quantityInBase,
    required double unitPrice,
  }) {
    final lineTotal = quantity * unitPrice;
    return db.createSalesInvoice(
      invoiceNumber: invoiceNumber,
      warehouseId: warehouseId,
      userId: userId,
      subtotal: lineTotal,
      discount: 0.0,
      tax: 0.0,
      total: lineTotal,
      paid: lineTotal,
      paymentMethod: 'cash',
      items: [
        SalesInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: quantity,
          unitPrice: unitPrice,
          total: lineTotal,
          costPrice: const Value(10.0), // بالقطعة (الوحدةُ الأساس)
          quantityInBase: Value(quantityInBase),
        ),
      ],
    );
  }

  test('تكلفةُ السلسلةِ الشهريّة = الكمّيّة × معاملِ التحويل × التكلفة '
      '(بيعةُ كرتونة)', () async {
    const quantity = 3.0; // كراتين (وحداتُ بيع)
    const quantityInBase = 24.0; // قطعةً في الكرتونة
    const costPrice = 10.0; // للقطعة (الوحدةُ الأساس)
    const unitPrice = 300.0;
    const expectedCogs = quantity * quantityInBase * costPrice; // 720
    const expectedNetSales = quantity * unitPrice; // 900

    final invoiceId = await sellCartons(
      invoiceNumber: 'INV-ANL-UOM-001',
      quantity: quantity,
      quantityInBase: quantityInBase,
      unitPrice: unitPrice,
    );

    final totals = await seriesTotals();

    // مرساة: الصفُّ موجودٌ فعلاً في السلسلة، فصفرُ التكلفةِ لن يمرَّ بوصفه
    // «لا بيانات».
    expect(totals.netSales, expectedNetSales,
        reason: 'الفاتورةُ يجب أن تظهر في السلسلةِ الشهريّة');

    expect(totals.cogs, expectedCogs,
        reason: 'COGS في التحليلات يجب أن تكون '
            'qty × quantityInBase × costPrice = $expectedCogs، '
            'لا qty × costPrice = ${quantity * costPrice}');

    // والأهمّ: الشاشةُ والأستاذُ يقولان الرقمَ نفسَه على الفاتورةِ نفسِها.
    expect(totals.cogs, await postedCogsFor(invoiceId),
        reason: 'تكلفةُ شاشةِ التحليلات يجب أن تطابق ما رُحِّل إلى حساب '
            'COGS في الأستاذ');
  });

  test('بيعةٌ بالوحدةِ الأساس (معاملُ التحويل = 1) لا تتأثّر بالإصلاح',
      () async {
    const quantity = 7.0;
    const costPrice = 10.0;
    const unitPrice = 25.0;
    const expectedCogs = quantity * costPrice; // 70

    final invoiceId = await sellCartons(
      invoiceNumber: 'INV-ANL-UOM-002',
      quantity: quantity,
      quantityInBase: 1.0,
      unitPrice: unitPrice,
    );

    final totals = await seriesTotals();

    expect(totals.netSales, quantity * unitPrice);
    expect(totals.cogs, expectedCogs,
        reason: 'الضربُ في معاملِ تحويلٍ قيمتُه 1 لا يغيّر شيئاً — '
            'حارسٌ ضدّ إصلاحٍ زائد');
    expect(totals.cogs, await postedCogsFor(invoiceId));
  });
}
