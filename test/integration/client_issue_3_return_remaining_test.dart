// ═══════════════════════════════════════════════════════════════════════════
// متطلبات العميل 2026-07-25 · البند 3 (م0) — «عند عمل مرتجع لا يظهر المبلغ
// المتبقي من الفاتورة على السيرفر ولكن يظهر على جهاز العميل».
// ═══════════════════════════════════════════════════════════════════════════
//
// «المتبقي» غير مخزَّن — يُحسب عند العرض كـ
//     total − paid − getReturnedAmountsForInvoices(id)
// و getReturnedAmountsForInvoices تربط المرتجع بأصله عبر نص حر في `notes`
// بالصيغة 'Return for invoice #<id>' (لا يوجد عمود FK).
//
// العطل: postSalesReturn يكتب في `notes` معرّف الفاتورة كما أرسله **العميل**
// (`data['originalInvoiceId']` = معرّف محلي على جهاز العميل)، بينما يحلّ
// الفاتورة الأصلية حلاً صحيحاً عبر `globalId` بعد ذلك مباشرة — ولا يستخدم
// النتيجة. فحين تختلف المعرّفات بين العميل والسيرفر (وهي الحالة الطبيعية)،
// لا يطابق المرتجع أي فاتورة على السيرفر ⇒ قيمة المرتجعات = صفر ⇒ «المتبقي»
// لا يتأثر على السيرفر، بينما يظهر صحيحاً على جهاز العميل.
//
// الإصلاح: حلّ الفاتورة الأصلية **قبل** إنشاء صف المرتجع واستخدام معرّف
// السيرفر (`original.id`) في `notes`.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/api/api_sales_handler.dart';

void main() {
  late AppDatabase db;
  late ApiSalesHandler handler;
  late int warehouseId;
  late int userId;
  late int productId;
  late int customerId;

  /// معرّف الفاتورة على جهاز العميل — مختلف عمداً عن معرّف السيرفر،
  /// وهو جوهر العطل.
  const clientSideInvoiceId = 9137;
  const originalGlobalId = 'gid-orig-issue3';

  setUp(() async {
    db = AppDatabase.forTesting();
    handler = ApiSalesHandler(db, {});

    warehouseId = await db.into(db.warehouses).insert(
        WarehousesCompanion.insert(
            name: 'مخزن الاختبار',
            globalId: const Value('gid-wh-issue3')));
    userId = await db.into(db.users).insert(UsersCompanion.insert(
          username: 'issue3_user',
          passwordHash: 'x',
          displayName: 'Issue3 User',
          roleId: const Value(1),
        ));
    productId = await db.insertProduct(ProductsCompanion.insert(
      name: 'صنف الاختبار',
      code: 'P-ISSUE3',
      salePrice: const Value(100.0),
      costPrice: const Value(60.0),
      trackInventory: const Value(true),
      globalId: const Value('gid-prod-issue3'),
    ));
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 100.0,
      type: 'in',
      notes: 'رصيد افتتاحي للاختبار',
    );
    customerId = await db.into(db.parties).insert(PartiesCompanion.insert(
          name: 'عميل الاختبار',
          isCustomer: const Value(true),
          globalId: const Value('gid-cust-issue3'),
        ));
  });

  tearDown(() async {
    await db.close();
  });

  /// تنشئ الفاتورة الأصلية على السيرفر: 1000 إجمالي، مدفوع 400.
  Future<int> createOriginalInvoice() => db.createSalesInvoice(
        invoiceNumber: 'INV-ISSUE3',
        customerId: customerId,
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 1000,
        discount: 0,
        tax: 0,
        total: 1000,
        paid: 400,
        paymentMethod: 'credit',
        globalId: originalGlobalId,
        items: [
          SalesInvoiceItemsCompanion(
            productId: Value(productId),
            quantity: const Value(10),
            unitPrice: const Value(100),
            total: const Value(1000),
          ),
        ],
      );

  Future<Response> postReturn(int serverOriginalId) => handler.postSalesReturn(
        Request(
          'POST',
          Uri.parse('http://localhost:8080/api/sales/return'),
          body: json.encode({
            'globalId': 'gid-return-issue3',
            // العميل يرسل معرّفه المحلي — لا معرّف السيرفر.
            'originalInvoiceId': clientSideInvoiceId,
            'originalInvoiceGlobalId': originalGlobalId,
            'invoiceNumber': 'SRET-ISSUE3',
            'customerId': customerId,
            'customerGlobalId': 'gid-cust-issue3',
            'warehouseId': warehouseId,
            'userId': userId,
            'subtotal': 300,
            'discount': 0,
            'tax': 0,
            'total': 300,
            'paid': 0,
            'paymentMethod': 'cash',
            'isFullReturn': false,
            'items': [
              {
                'productId': productId,
                'productGlobalId': 'gid-prod-issue3',
                'quantity': 3,
                'unitPrice': 100,
                'total': 300,
                'quantityInBase': 1.0,
              },
            ],
          }),
        ),
      );

  test(
      'المرتجع القادم من العميل يُنسب لمعرّف السيرفر فيظهر المتبقي صحيحاً '
      'رغم اختلاف المعرّفات', () async {
    final serverOriginalId = await createOriginalInvoice();
    // شرط صحة الاختبار: المعرّفان مختلفان فعلاً.
    expect(serverOriginalId, isNot(clientSideInvoiceId));

    final res = await postReturn(serverOriginalId);
    expect(res.statusCode, 200);

    final returned =
        await db.getReturnedAmountsForInvoices([serverOriginalId]);

    expect(returned[serverOriginalId], 300,
        reason: 'المرتجع يجب أن يُنسب للفاتورة الأصلية على السيرفر');

    // «المتبقي» كما تحسبه الشاشة: 1000 − 400 − 300 = 300
    final invoice = await (db.select(db.salesInvoices)
          ..where((s) => s.id.equals(serverOriginalId)))
        .getSingle();
    final remaining =
        invoice.total - invoice.paid - (returned[serverOriginalId] ?? 0);
    expect(remaining, 300);
  });

  test('حالة تطابق المعرّفات تبقى صحيحة (انحدار)', () async {
    // لا تعتمد على globalId إطلاقاً: يجب أن يظل المسار الاحتياطي
    // (المطابقة بالمعرّف الرقمي) عاملاً حين يرسل العميل معرّفاً مطابقاً.
    final serverOriginalId = await createOriginalInvoice();

    final res = await handler.postSalesReturn(Request(
      'POST',
      Uri.parse('http://localhost:8080/api/sales/return'),
      body: json.encode({
        'globalId': 'gid-return-issue3-b',
        'originalInvoiceId': serverOriginalId,
        // بلا originalInvoiceGlobalId — يجبر المسار الاحتياطي.
        'invoiceNumber': 'SRET-ISSUE3-B',
        'customerId': customerId,
        'warehouseId': warehouseId,
        'userId': userId,
        'subtotal': 100,
        'discount': 0,
        'tax': 0,
        'total': 100,
        'paid': 0,
        'paymentMethod': 'cash',
        'isFullReturn': false,
        'items': [
          {
            'productId': productId,
            'quantity': 1,
            'unitPrice': 100,
            'total': 100,
            'quantityInBase': 1.0,
          },
        ],
      }),
    ));
    expect(res.statusCode, 200);

    final returned =
        await db.getReturnedAmountsForInvoices([serverOriginalId]);
    expect(returned[serverOriginalId], 100);
  });
}
