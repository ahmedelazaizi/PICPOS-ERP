// ═══════════════════════════════════════════════════════════════════════════
// متطلبات العميل 2026-07-25 · م4 · البند 5 — «عند عمل مشتريات يقبل رقم
// الفاتورة في شكل متشابه (يقبل نفس الرقم لأكثر من فاتورة)».
// ═══════════════════════════════════════════════════════════════════════════
//
// لا يوجد فحص تفرّد في **أي** طبقة: لا في الفورم، ولا في حالة الاستخدام، ولا
// في الـDAO، ولا قيد UNIQUE في سكيمة Drift أو Postgres. النتيجة: ذمة مورد
// مزدوجة + ضريبة مدخلات مزدوجة + كشف حساب مورد غير قابل للمطابقة.
//
// النطاق الصحيح: **لكل مورد** لا عام — رقم فاتورة المورد فريد في دفتره هو
// فقط، ومن الطبيعي أن يحمل موردان مختلفان الرقم `1001`.
//
// الفهرس الفريد الجزئي **مؤجَّل عمداً**: قد تحمل قاعدة العميل تكرارات قائمة
// فتفشل الهجرة. الحارس هنا على مستوى التطبيق — يعمل فوراً وبلا مخاطر هجرة.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/api/api_purchase_handler.dart';
import 'package:ural_erp/services/api/api_user_context.dart';

void main() {
  late AppDatabase db;
  late int warehouseId;
  late int supplierA;
  late int supplierB;
  late int productId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();

    warehouseId = await db.into(db.warehouses).insert(
        WarehousesCompanion.insert(
            name: 'مخزن م4', globalId: const Value('gid-wh-m4')));
    supplierA = await db.into(db.parties).insert(PartiesCompanion.insert(
          name: 'مورد أ',
          isSupplier: const Value(true),
          globalId: const Value('gid-sup-m4-a'),
        ));
    supplierB = await db.into(db.parties).insert(PartiesCompanion.insert(
          name: 'مورد ب',
          isSupplier: const Value(true),
          globalId: const Value('gid-sup-m4-b'),
        ));
    productId = await db.insertProduct(ProductsCompanion.insert(
      code: 'M4-1',
      name: 'صنف م4',
      trackInventory: const Value(true),
    ));
  });

  tearDown(() async => db.close());

  Future<int> createPurchase({
    required int supplierId,
    String? supplierInvoiceNumber,
  }) =>
      db.createPurchaseInvoice(
        supplierId: supplierId,
        warehouseId: warehouseId,
        paid: 0.0,
        paymentMethod: 'credit',
        supplierInvoiceNumber: supplierInvoiceNumber,
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

  test('نفس رقم فاتورة المورد لنفس المورد يُرفض', () async {
    await createPurchase(supplierId: supplierA, supplierInvoiceNumber: 'INV-2026-001');

    await expectLater(
      createPurchase(supplierId: supplierA, supplierInvoiceNumber: 'INV-2026-001'),
      throwsA(predicate((e) =>
          e.toString().contains('INV-2026-001') &&
          e.toString().contains('مستخدم'))),
      reason: 'التكرار يجب أن يُرفض برسالة تذكر الرقم',
    );

    final count = await db
        .customSelect("SELECT COUNT(*) AS n FROM purchase_invoices "
            "WHERE supplier_invoice_number = 'INV-2026-001'")
        .getSingle();
    expect((count.data['n'] as num).toInt(), 1,
        reason: 'الفاتورة الثانية لم تُحفظ إطلاقاً (تراجعت المعاملة)');
  });

  test('نفس الرقم لموردين مختلفين مسموح — التفرّد لكل مورد لا عام', () async {
    await createPurchase(supplierId: supplierA, supplierInvoiceNumber: '1001');
    await createPurchase(supplierId: supplierB, supplierInvoiceNumber: '1001');

    final count = await db
        .customSelect("SELECT COUNT(*) AS n FROM purchase_invoices "
            "WHERE supplier_invoice_number = '1001'")
        .getSingle();
    expect((count.data['n'] as num).toInt(), 2,
        reason: 'تفرّد عام كان سيكسر بيانات مشروعة');
  });

  test('ترك رقم فاتورة المورد فارغاً لا يمنع فواتير متعددة', () async {
    await createPurchase(supplierId: supplierA);
    await createPurchase(supplierId: supplierA);
    await createPurchase(supplierId: supplierA, supplierInvoiceNumber: '');

    final count = await db
        .customSelect('SELECT COUNT(*) AS n FROM purchase_invoices')
        .getSingle();
    expect((count.data['n'] as num).toInt(), 3,
        reason: 'الأرقام المولَّدة تلقائياً لا تخضع لفحص التفرّد');
  });

  test('تعديل الفاتورة بنفس رقمها لا يعتبرها مكرّرة لنفسها', () async {
    final invoiceId =
        await createPurchase(supplierId: supplierA, supplierInvoiceNumber: 'EDIT-1');
    final adminId = (await db
            .customSelect("SELECT id FROM users WHERE username = 'admin' LIMIT 1")
            .getSingle())
        .read<int>('id');

    // إعادة الحفظ بنفس الرقم يجب أن تنجح — الفحص يستثني الصف نفسه.
    await db.updatePurchaseInvoice(
      invoiceId: invoiceId,
      supplierId: supplierA,
      warehouseId: warehouseId,
      paid: 0.0,
      paymentMethod: 'credit',
      supplierInvoiceNumber: 'EDIT-1',
      userId: adminId,
      items: [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: invoiceId,
          productId: productId,
          quantity: 2,
          unitCost: 100,
          total: 200,
        ),
      ],
    );

    final inv = await (db.select(db.purchaseInvoices)
          ..where((p) => p.id.equals(invoiceId)))
        .getSingle();
    expect(inv.total, closeTo(200, 0.001), reason: 'التعديل نجح');
  });

  test('التعديل إلى رقم يخصّ فاتورة أخرى لنفس المورد يُرفض', () async {
    await createPurchase(supplierId: supplierA, supplierInvoiceNumber: 'TAKEN');
    final second =
        await createPurchase(supplierId: supplierA, supplierInvoiceNumber: 'FREE');
    final adminId = (await db
            .customSelect("SELECT id FROM users WHERE username = 'admin' LIMIT 1")
            .getSingle())
        .read<int>('id');

    await expectLater(
      db.updatePurchaseInvoice(
        invoiceId: second,
        supplierId: supplierA,
        warehouseId: warehouseId,
        paid: 0.0,
        paymentMethod: 'credit',
        supplierInvoiceNumber: 'TAKEN',
        userId: adminId,
        items: [
          PurchaseInvoiceItemsCompanion.insert(
            invoiceId: second,
            productId: productId,
            quantity: 1,
            unitCost: 100,
            total: 100,
          ),
        ],
      ),
      throwsA(predicate((e) => e.toString().contains('TAKEN'))),
    );
  });

  test('الخادم يُرجع 409 للتكرار — لا 500 — ويميّز إعادة المحاولة المشروعة',
      () async {
    final handler = ApiPurchaseHandler(db, {});

    Future<shelf.Response> post(String gid, String supplierInvoiceNo) =>
        handler.postPurchase(shelf.Request(
          'POST',
          Uri.parse('http://localhost:8080/api/purchases'),
          body: json.encode({
            'globalId': gid,
            'supplierId': supplierA,
            'supplierGlobalId': 'gid-sup-m4-a',
            'warehouseId': warehouseId,
            'paid': 0,
            'paymentMethod': 'credit',
            'supplierInvoiceNumber': supplierInvoiceNo,
            'items': [
              {'productId': productId, 'quantity': 1, 'unitCost': 100, 'total': 100},
            ],
          }), context: {ApiUserCtx.userIdKey: 1},
        ));

    final first = await post('gid-pur-m4-1', 'SRV-001');
    expect(first.statusCode, 200);

    // إعادة إرسال **نفس** الطلب (نفس globalId) = إعادة محاولة مشروعة من
    // الطابور، ويجب أن تُقصَر كمكرّرة إيجابية لا كتعارض.
    final replay = await post('gid-pur-m4-1', 'SRV-001');
    expect(replay.statusCode, 200,
        reason: 'إعادة المحاولة على نفس globalId ليست تعارضاً');
    expect(json.decode(await replay.readAsString())['duplicate'], true);

    // فاتورة **مختلفة** بنفس رقم المورد = تعارض حقيقي.
    final conflict = await post('gid-pur-m4-2', 'SRV-001');
    expect(conflict.statusCode, 409,
        reason: '409 يميّز تعارض العمل عن عطل الخادم، فيتوقف الطابور عن '
            'إعادة المحاولة اللانهائية');
    expect(await conflict.readAsString(), contains('SRV-001'));
  });

  test('الفاتورة الملغاة لا تحجز رقمها', () async {
    final invoiceId =
        await createPurchase(supplierId: supplierA, supplierInvoiceNumber: 'VOIDED-1');
    await (db.update(db.purchaseInvoices)
          ..where((p) => p.id.equals(invoiceId)))
        .write(const PurchaseInvoicesCompanion(isDeleted: Value(true)));

    // إعادة استخدام رقم فاتورة محذوفة يجب أن تنجح.
    await createPurchase(supplierId: supplierA, supplierInvoiceNumber: 'VOIDED-1');

    final live = await db
        .customSelect("SELECT COUNT(*) AS n FROM purchase_invoices "
            "WHERE supplier_invoice_number = 'VOIDED-1' AND is_deleted = 0")
        .getSingle();
    expect((live.data['n'] as num).toInt(), 1);
  });
}
