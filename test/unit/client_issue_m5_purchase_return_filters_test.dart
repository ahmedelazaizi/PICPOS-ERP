// ═══════════════════════════════════════════════════════════════════════════
// متطلبات العميل 2026-07-25 · م5 · البند 7 — «مردودات المشتريات: يجب إضافة
// الفلاتر التالية لتسهيل عملية التتبع: المورد، الصنف الموجود في جميع الفواتير
// (القدرة على البحث عنه)، رقم الفاتورة».
// ═══════════════════════════════════════════════════════════════════════════
//
// الموجود اليوم: تاريخَان فقط على مستوى الاستعلام، و«البحث برقم الفاتورة»
// مجرّد `contains()` **في الذاكرة** فوق نتيجة محدودة بـ500 صف.
//
// أثر ذلك أخطر من نقص ميزة: البحث عن فاتورة **يفشل صامتاً** متى خرجت من أحدث
// 500 فاتورة في المدى — يظهر «لا نتائج» بينما الفاتورة موجودة. فأي إصلاح
// يجب أن يدفع المسند إلى SQL لا أن يضيف فلاتر ذاكرة فوق أساس مبتور.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int warehouseId;
  late int supplierA;
  late int supplierB;
  late int productX;
  late int productY;

  final from = DateTime(2026, 7, 1);
  final to = DateTime(2026, 7, 31);

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();

    warehouseId = await db.into(db.warehouses).insert(
        WarehousesCompanion.insert(
            name: 'مخزن م5', globalId: const Value('gid-wh-m5')));
    supplierA = await db.into(db.parties).insert(PartiesCompanion.insert(
        name: 'مورد أ', isSupplier: const Value(true),
        globalId: const Value('gid-sup-m5-a')));
    supplierB = await db.into(db.parties).insert(PartiesCompanion.insert(
        name: 'مورد ب', isSupplier: const Value(true),
        globalId: const Value('gid-sup-m5-b')));
    productX = await db.insertProduct(ProductsCompanion.insert(
        code: 'M5-X', name: 'صنف س', trackInventory: const Value(true)));
    productY = await db.insertProduct(ProductsCompanion.insert(
        code: 'M5-Y', name: 'صنف ص', trackInventory: const Value(true)));
  });

  tearDown(() async => db.close());

  Future<int> makeInvoice({
    required int supplierId,
    required int productId,
    required String supplierInvoiceNumber,
    DateTime? date,
  }) =>
      db.createPurchaseInvoice(
        supplierId: supplierId,
        warehouseId: warehouseId,
        paid: 0.0,
        paymentMethod: 'credit',
        supplierInvoiceNumber: supplierInvoiceNumber,
        invoiceDate: date ?? DateTime(2026, 7, 15),
        items: [
          PurchaseInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 1,
            unitCost: 100,
            total: 100,
          ),
        ],
      );

  test('فلتر المورد يحصر النتائج على مورد واحد', () async {
    await makeInvoice(
        supplierId: supplierA, productId: productX, supplierInvoiceNumber: 'A-1');
    await makeInvoice(
        supplierId: supplierB, productId: productX, supplierInvoiceNumber: 'B-1');

    final rows = await db.getPurchasesForDateRange(from, to, supplierId: supplierA);
    expect(rows, hasLength(1));
    expect(rows.single.supplierId, supplierA);
  });

  test('فلتر رقم الفاتورة يبحث في رقم المورد والرقم الداخلي معاً', () async {
    await makeInvoice(
        supplierId: supplierA, productId: productX, supplierInvoiceNumber: 'INV-777');
    await makeInvoice(
        supplierId: supplierA, productId: productX, supplierInvoiceNumber: 'OTHER-1');

    // المستخدم يفكّر في «رقم الفاتورة» على أنه رقم المورد.
    final rows = await db.getPurchasesForDateRange(from, to, invoiceNumberLike: '777');
    expect(rows, hasLength(1));
    expect(rows.single.supplierInvoiceNumber, 'INV-777');
  });

  test('بحث جزئي غير حسّاس لحالة الأحرف', () async {
    await makeInvoice(
        supplierId: supplierA, productId: productX, supplierInvoiceNumber: 'abc-99');

    expect(await db.getPurchasesForDateRange(from, to, invoiceNumberLike: 'ABC'),
        hasLength(1));
  });

  test('فلتر الصنف يجد الفواتير التي تحتوي الصنف عبر كل الفواتير', () async {
    await makeInvoice(
        supplierId: supplierA, productId: productX, supplierInvoiceNumber: 'X-1');
    await makeInvoice(
        supplierId: supplierB, productId: productY, supplierInvoiceNumber: 'Y-1');
    await makeInvoice(
        supplierId: supplierB, productId: productX, supplierInvoiceNumber: 'X-2');

    final rows = await db.getPurchasesForDateRange(from, to, productId: productX);
    expect(rows, hasLength(2));
    expect(rows.map((r) => r.supplierInvoiceNumber).toSet(), {'X-1', 'X-2'});
  });

  test('الفلاتر تتراكب — مورد + صنف معاً', () async {
    await makeInvoice(
        supplierId: supplierA, productId: productX, supplierInvoiceNumber: 'A-X');
    await makeInvoice(
        supplierId: supplierB, productId: productX, supplierInvoiceNumber: 'B-X');
    await makeInvoice(
        supplierId: supplierA, productId: productY, supplierInvoiceNumber: 'A-Y');

    final rows = await db.getPurchasesForDateRange(
      from,
      to,
      supplierId: supplierA,
      productId: productX,
    );
    expect(rows, hasLength(1));
    expect(rows.single.supplierInvoiceNumber, 'A-X');
  });

  test('البحث يجد فاتورة خارج أحدث 500 صف — لا يبتره الترقيم', () async {
    // الفاتورة المطلوبة أقدم من 500 فاتورة لاحقة: البحث في الذاكرة كان
    // يفوّتها ويعرض «لا نتائج» رغم وجودها.
    await makeInvoice(
      supplierId: supplierA,
      productId: productX,
      supplierInvoiceNumber: 'NEEDLE-1',
      date: DateTime(2026, 7, 2),
    );
    for (var i = 0; i < 520; i++) {
      await makeInvoice(
        supplierId: supplierB,
        productId: productY,
        supplierInvoiceNumber: 'BULK-$i',
        date: DateTime(2026, 7, 20),
      );
    }

    final rows =
        await db.getPurchasesForDateRange(from, to, invoiceNumberLike: 'NEEDLE');
    expect(rows, hasLength(1),
        reason: 'المسند في SQL يجد الفاتورة مهما كان ترتيبها');
    expect(rows.single.supplierInvoiceNumber, 'NEEDLE-1');
  });

  test('بلا فلاتر يبقى السلوك كما هو (انحدار)', () async {
    await makeInvoice(
        supplierId: supplierA, productId: productX, supplierInvoiceNumber: 'R-1');
    await makeInvoice(
        supplierId: supplierB, productId: productY, supplierInvoiceNumber: 'R-2');

    expect(await db.getPurchasesForDateRange(from, to), hasLength(2));
  });

  test('الفواتير خارج المدى الزمني تبقى مستبعدة رغم مطابقة الفلاتر', () async {
    await makeInvoice(
      supplierId: supplierA,
      productId: productX,
      supplierInvoiceNumber: 'OLD-1',
      date: DateTime(2026, 6, 15),
    );

    expect(
        await db.getPurchasesForDateRange(from, to,
            supplierId: supplierA, productId: productX),
        isEmpty);
  });
}
