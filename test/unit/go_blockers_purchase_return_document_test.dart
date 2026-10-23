// ═══════════════════════════════════════════════════════════════════════════
// §٦‑٢ — مرتجعُ الشراء صار مستنداً بضريبته
// ═══════════════════════════════════════════════════════════════════════════
//
// كان مرتجعُ الشراء بلا صفٍّ في أيِّ جدولِ مستندات: قيدٌ في الأستاذ ومذكّرةُ
// رصيدٍ تحمل **تصحيحَ رصيدٍ لا ضريبة**، و`stock_movements` كمّيّاتٌ لا ضريبة.
// فتسويةُ ض.ق.م كانت تشتقُّ ضريبتَه **من الأستاذ نفسِه** ⇒ الطرفان يقرآن
// مصدراً واحداً ويتّفقان بالبناء: مكوّنٌ لا يُطابَق مطابقةً مستقلّة.
//
// وجدولُ `purchase_returns` (v172) هو الطرفُ الثاني الغائب. وما يقيسه هذا
// الملفّ هو **استقلالُ المصدرَين** لا مجرّدُ وجودِ صفّ:
//
//   ١ — المستندُ يُكتَب بضريبةٍ وتاريخٍ صحيحَين من القُمع الوحيد.
//   ٢ — **وإفسادُ المستند وحدَه يُظهر فرقاً** — وهذا هو الدليلُ القاطع على
//       أنّ التسويةَ لم تعد تقرأ الأستاذَ مرّتين. لو بقي الاشتقاقُ لظلّ
//       الطرفان متّفقَين مهما فعلتُ بالمستند.
//   ٣ — وعكسُ المرتجع يُبطل مستندَه، وإلّا انقلب الفرقُ للاتّجاه الآخر.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int supplierId;
  late int warehouseId;
  // ignore: unused_local_variable
  late int userId;
  // ignore: unused_local_variable
  late int productId;

  // فاتورةُ شراءٍ بضريبةٍ صريحة، ومرتجعٌ جزئيٌّ بأرقامٍ متمايزةٍ عمداً.
  const purchaseSubtotal = 1000.0;
  const purchaseTax = 140.0;
  const returnSubtotal = 250.0;
  const returnTax = 35.0; // ١٤٪ من ٢٥٠



  late DateTime docDate;

  setUp(() async {
    db = AppDatabase.forTesting();
    docDate = DateTime(2026, 5, 15);



    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(name: 'مشتريات', isSystemRole: const Value(false)),
        );
    userId = await db.createUser(
      username: 'pret_user',
      password: 'test',
      displayName: 'Purchase User',
      roleId: roleId,
    );
    warehouseId = (await db.getDefaultWarehouse())!.id;
    supplierId = await db.into(db.parties).insert(
          PartiesCompanion.insert(
            name: 'موردُ الاختبار',
            isCustomer: const Value(false),
          ),
        );
    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'PRET-1',
        name: 'صنفُ مشتريات',
        salePrice: const Value(20.0),
        costPrice: const Value(10.0),
        taxRate: const Value(14.0),
        trackInventory: const Value(true),
      ),
    );
  });

  tearDown(() async => db.close());

  Future<PurchaseInvoiceData> seedPurchase() async {
    final id = await db.into(db.purchaseInvoices).insert(
          PurchaseInvoicesCompanion.insert(
            invoiceNumber: 'PINV-1',
            supplierId: supplierId,
            warehouseId: warehouseId,
            invoiceDate: docDate,
            subtotal: const Value(purchaseSubtotal),
            tax: const Value(purchaseTax),
            total: const Value(purchaseSubtotal + purchaseTax),
          ),
        );
    return (db.select(db.purchaseInvoices)..where((p) => p.id.equals(id)))
        .getSingle();
  }

  Future<List<PurchaseReturn>> docsFor(int invoiceId) =>
      (db.select(db.purchaseReturns)
            ..where((r) => r.originalInvoiceId.equals(invoiceId)))
          .get();

  Future<void> postReturn(PurchaseInvoiceData inv) async {
    await db.autoPostPurchaseReturn(
      originalPurchase: inv,
      returnDate: docDate,
      returnAmount: returnSubtotal,
      vatAmount: returnTax,
      returnEventId: 'PRET-0001',
    );
  }

  Future<double> reconciledInputVatReturns() async {
    final r = await db.getVatReconciliationData(year: 2026, month: 5);
    return r.inputVatReturns;
  }

  test('المرتجعُ يكتب مستنداً بضريبته وتاريخِ ترحيله', () async {
    final inv = await seedPurchase();
    await postReturn(inv);

    final docs = await docsFor(inv.id);
    expect(docs.length, 1, reason: 'مستندٌ واحدٌ لحدثٍ واحد');

    final doc = docs.single;
    expect(doc.tax, returnTax, reason: 'الحقلُ الذي وُجد الجدولُ لأجله');
    expect(doc.subtotal, returnSubtotal);
    expect(doc.total, returnSubtotal + returnTax);
    expect(doc.supplierId, supplierId);
    expect(doc.isDeleted, isFalse);
    expect(doc.returnDate, docDate,
        reason: 'تاريخُ الترحيل عينُه — التسويةُ دوريّةٌ فتاريخانِ مختلفانِ '
            'لحدثٍ واحدٍ يُنتجان فرقاً على حدِّ الشهر');
    expect(doc.globalId, isNotNull,
        reason: 'المعرّفُ العامُّ شرطُ المزامنة');
  });

  test('إعادةُ نداءٍ لنفس الحدث لا تُنتج مستنداً ثانياً', () async {
    final inv = await seedPurchase();
    await postReturn(inv);
    await postReturn(inv); // إعادةُ محاولةٍ حقيقيّةٌ بنفس `returnEventId`

    expect((await docsFor(inv.id)).length, 1,
        reason: 'حارسُ الـdedup يحمي المستندَ كما يحمي القيد');
  });

  test('🔴 المصدرانِ مستقلّان — إفسادُ المستند وحدَه يُظهر فرقاً', () async {
    final inv = await seedPurchase();
    await postReturn(inv);

    // مرساة: التسويةُ تقرأ المستندَ فعلاً.
    expect(await reconciledInputVatReturns(), returnTax,
        reason: 'مرساة: الضريبةُ تصل التسويةَ من المستند');

    // الآن يُغيَّر **المستندُ وحدَه** والأستاذُ يبقى كما هو. لو كانت التسويةُ
    // ما زالت تشتقُّ من الأستاذ لما تغيّر الرقمُ بحرف — وهذا بالضبط ما يجعل
    // هذا التوكيدَ دليلاً على الاستقلال لا على وجود صفّ.
    await (db.update(db.purchaseReturns)
          ..where((r) => r.originalInvoiceId.equals(inv.id)))
        .write(const PurchaseReturnsCompanion(tax: Value(999.0)));

    expect(await reconciledInputVatReturns(), 999.0,
        reason: 'التسويةُ تقرأ المستندَ — لا الأستاذَ مرّةً ثانية');
  });

  test('عكسُ المرتجع يُبطل مستندَه فلا تُطرح ضريبةُ مرتجعٍ أُلغي', () async {
    final inv = await seedPurchase();
    await postReturn(inv);
    expect(await reconciledInputVatReturns(), returnTax, reason: 'مرساة');

    final voided = await db.voidPurchaseReturnDocs(inv.id);
    expect(voided, 1, reason: 'صفٌّ واحدٌ أُبطل');

    expect(await reconciledInputVatReturns(), 0.0,
        reason: 'مستندٌ مُبطَلٌ لا يُطرح — وإلّا انقلب الفرقُ للاتّجاه الآخر');

    // حذفٌ ناعمٌ لا صلب: الصفُّ يبقى كي ينتشر الإبطالُ بالمزامنة.
    final docs = await docsFor(inv.id);
    expect(docs.length, 1);
    expect(docs.single.isDeleted, isTrue);
  });

  test('مرتجعٌ خارجَ المدى لا يدخل تسويةَ الشهر', () async {
    final inv = await seedPurchase();
    await db.autoPostPurchaseReturn(
      originalPurchase: inv,
      returnDate: DateTime(2026, 7, 10), // شهرٌ آخر
      returnAmount: returnSubtotal,
      vatAmount: returnTax,
      returnEventId: 'PRET-0002',
    );

    expect(await reconciledInputVatReturns(), 0.0,
        reason: 'حارسٌ ضدّ تجميعٍ يُسقط الدوريّة — مرتجعُ يوليو ليس من مايو');
  });
}
