// إثباتُ وصولِ مخطّطَي v154 وv155. `build_runner` قد ينجح ظاهرياً ويُنقص
// المولَّد بصمتٍ، و`flutter analyze` لا يكشفها. هذا الاختبار يكشفها.
//
// وهو مقيَّدٌ برقمٍ بعينه بقصد: لو أُضيف عمودٌ في نسخةٍ تاليةٍ ولم يُضَف هنا
// سطرُه، بقي الحارسُ أخضرَ على مخطّطٍ ناقص. فكلُّ نسخةٍ تجرّ اختبارَها.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  test('أعمدةُ TableOrders الجديدة تُكتب وتُقرأ', () async {
    final tableId = await db.createTable(name: 'ط١');
    final orderId = await db.into(db.tableOrders).insert(
          TableOrdersCompanion.insert(
            tableId: tableId,
            guestCount: const Value(4),
            notes: const Value('بجانب النافذة'),
            discountType: const Value('percent'),
            discountValue: const Value(10),
            paidAmount: const Value(25.5),
          ),
        );

    final order = await (db.select(db.tableOrders)
          ..where((o) => o.id.equals(orderId)))
        .getSingle();

    expect(order.guestCount, 4);
    expect(order.notes, 'بجانب النافذة');
    expect(order.discountType, 'percent');
    expect(order.discountValue, 10);
    expect(order.paidAmount, 25.5);
  });

  test('عددُ الأشخاص الافتراضيُّ واحد ولا يكون عدماً', () async {
    final tableId = await db.createTable(name: 'ط٢');
    final orderId = await db.createTableOrder(tableId);
    final order = await (db.select(db.tableOrders)
          ..where((o) => o.id.equals(orderId)))
        .getSingle();
    expect(order.guestCount, 1);
    expect(order.paidAmount, 0);
  });

  test('عمودا ضريبة v155 يُكتبان ويُقرآن', () async {
    final tableId = await db.createTable(name: 'ط٣');
    final orderId = await db.into(db.tableOrders).insert(
          TableOrdersCompanion.insert(
            tableId: tableId,
            taxEnabled: const Value(true),
            // كسريّةٌ لا مئويّة — لقطةُ `pos_default_tax_rate`.
            taxRate: const Value(0.16),
          ),
        );

    final order = await (db.select(db.tableOrders)
          ..where((o) => o.id.equals(orderId)))
        .getSingle();

    expect(order.taxEnabled, isTrue);
    expect(order.taxRate, 0.16);
  });

  test('افتراضا الضريبة: مطفأةٌ ونسبةٌ صفرٌ ⇐ سلوكُ ما قبل v155 بحرفه', () async {
    final tableId = await db.createTable(name: 'ط٤');
    final orderId = await db.createTableOrder(tableId);
    final order = await (db.select(db.tableOrders)
          ..where((o) => o.id.equals(orderId)))
        .getSingle();

    // هذان الافتراضان هما ما يجعل الترقيةَ لا تُغيّر حسابَ طاولةٍ مفتوحة.
    expect(order.taxEnabled, isFalse);
    expect(order.taxRate, 0);
  });

  test('نسبةُ ضريبة البند تُكتب وتُقرأ — العمودُ ما عاد صفراً أبداً', () async {
    final tableId = await db.createTable(name: 'ط٥');
    final orderId = await db.createTableOrder(tableId);
    final productId = await db.into(db.products).insert(
          ProductsCompanion.insert(code: 'SCH-1', name: 'صنفُ المخطّط'),
        );

    await db.addOrUpdateTableOrderItem(
      orderId: orderId,
      productId: productId,
      quantity: 2,
      unitPrice: 25,
      taxRate: 16, // مئويّةٌ هنا — مرآةُ `Products.taxRate`
    );

    final items = await db.getTableOrderItems(orderId);
    expect(items.single.taxRate, 16);
    expect(items.single.total, 50);
  });

  test('جدولُ TableOrderPayments موجودٌ ويقبل صفّاً', () async {
    final tableId = await db.createTable(name: 'ط٣');
    final orderId = await db.createTableOrder(tableId);

    // table_order_payments.invoice_id يتبع sales_invoices، والقيدُ الأجنبي
    // مُفعَّلٌ في اختبارات forTesting() (مطابقةً للإنتاج) — فتُزرع فاتورةٌ
    // حقيقية بدل رقمٍ وهميّ (نفسُ نمط hold_order_usecase_test.dart). المخزنُ
    // والمستخدمُ مبذوران سلفاً في beforeOpen فيُعاد استخدامهما، والفاتورةُ
    // الأولى في قاعدةٍ فارغة تحمل id=1 فتطابق `invoiceId: 1` أدناه.
    final warehouseId = (await db.select(db.warehouses).get()).first.id;
    final userId = (await db.select(db.users).get()).first.id;
    await db.into(db.salesInvoices).insert(
          SalesInvoicesCompanion.insert(
            invoiceNumber: 'INV-TEST-1',
            warehouseId: warehouseId,
            userId: userId,
            invoiceDate: DateTime.now(),
          ),
        );

    final paymentId = await db.into(db.tableOrderPayments).insert(
          TableOrderPaymentsCompanion.insert(
            tableOrderId: orderId,
            // v158: `invoiceId` صار معدوماً-مسموحاً (الحجزُ يسبق الفاتورة)،
            // فالإدراجُ يحتاج `Value` صريحة.
            invoiceId: const Value(1),
            amount: 33.334,
            splitLabel: const Value('ضيف ٣'),
          ),
        );

    final row = await (db.select(db.tableOrderPayments)
          ..where((p) => p.id.equals(paymentId)))
        .getSingle();
    expect(row.amount, 33.334);
    expect(row.splitLabel, 'ضيف ٣');
  });

  test('مصدرُ البند يُحفَظ على بند الطلب', () async {
    final tableId = await db.createTable(name: 'ط٤');
    final orderId = await db.createTableOrder(tableId);

    // table_order_items.product_id يتبع products، والقيدُ الأجنبي مُفعَّلٌ في
    // اختبارات forTesting() — فتُزرع سلعةٌ حقيقية. products فارغٌ في قاعدةٍ
    // جديدة فتحمل أول سلعةٍ id=1، فتطابق `productId: 1` أدناه.
    await db.into(db.products).insert(
          ProductsCompanion.insert(code: 'TEST-1', name: 'صنف اختبار'),
        );

    final itemId = await db.into(db.tableOrderItems).insert(
          TableOrderItemsCompanion.insert(
            tableOrderId: orderId,
            productId: 1,
            quantity: 1,
            unitPrice: 10,
            total: 10,
            notes: const Value('بلا بصل'),
            sourceTableOrderId: Value(orderId),
          ),
        );
    final item = await (db.select(db.tableOrderItems)
          ..where((i) => i.id.equals(itemId)))
        .getSingle();
    expect(item.notes, 'بلا بصل');
    expect(item.sourceTableOrderId, orderId);
  });
}
