import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/models/table_status.dart';
import 'package:ural_erp/services/table_session_service.dart';

void main() {
  late AppDatabase db;
  late TableSessionService service;

  setUp(() {
    db = AppDatabase.forTesting();
    service = TableSessionService(db);
  });
  tearDown(() => db.close());

  Future<int> newTable(String name) => db.createTable(name: name);

  Future<RestaurantTable> readTable(int id) =>
      (db.select(db.restaurantTables)..where((t) => t.id.equals(id)))
          .getSingle();

  group('openTable', () {
    test('يفتح طاولةً متاحةً ويثبّت عددَ الأشخاص', () async {
      final t = await newTable('ط٧');
      final orderId = await service.openTable(
          tableId: t, guestCount: 4, userId: null, userName: 'أحمد');

      expect((await readTable(t)).status, TableStatus.occupied);
      final order = await db.getActiveOrderForTable(t);
      expect(order!.id, orderId);
      expect(order.guestCount, 4);
    });

    test('يكتب سطراً في السجل', () async {
      final t = await newTable('ط٨');
      await service.openTable(
          tableId: t, guestCount: 2, userId: null, userName: 'أحمد');

      final logs = await (db.select(db.activityLogs)
            ..where((l) => l.entityType.equals('table')))
          .get();
      expect(logs, hasLength(1));
      expect(logs.single.action, 'table_open');
      expect(logs.single.entityId, t);
    });

    test('يرفض طاولةً مشغولة', () async {
      final t = await newTable('ط٩');
      await service.openTable(
          tableId: t, guestCount: 2, userId: null, userName: 'أحمد');

      expect(
        () => service.openTable(
            tableId: t, guestCount: 2, userId: null, userName: 'أحمد'),
        throwsA(isA<TableTransitionException>()),
      );
    });

    test('يرفض عددَ أشخاصٍ أقلَّ من واحد', () async {
      final t = await newTable('ط١٠');
      expect(
        () => service.openTable(
            tableId: t, guestCount: 0, userId: null, userName: 'أحمد'),
        throwsA(isA<TableTransitionException>()),
      );
    });
  });

  group('closeTable', () {
    test('يرفض الإغلاقَ قبل اكتمال الدفع', () async {
      final t = await newTable('ط١١');
      final orderId = await service.openTable(
          tableId: t, guestCount: 2, userId: null, userName: 'أحمد');
      await (db.update(db.tableOrders)..where((o) => o.id.equals(orderId)))
          .write(const TableOrdersCompanion(
              total: Value(100), paidAmount: Value(60)));

      expect(
        () => service.closeTable(
            tableId: t, userId: null, userName: 'أحمد'),
        throwsA(isA<TableTransitionException>()),
      );
      expect((await readTable(t)).status, TableStatus.occupied);
    });

    test('يُغلق ويُحرّر الطاولة عند اكتمال الدفع', () async {
      final t = await newTable('ط١٢');
      final orderId = await service.openTable(
          tableId: t, guestCount: 2, userId: null, userName: 'أحمد');
      await (db.update(db.tableOrders)..where((o) => o.id.equals(orderId)))
          .write(const TableOrdersCompanion(
              total: Value(100), paidAmount: Value(100)));

      await service.closeTable(tableId: t, userId: null, userName: 'أحمد');

      expect((await readTable(t)).status, TableStatus.available);
      expect(await db.getActiveOrderForTable(t), isNull);

      final logs = await (db.select(db.activityLogs)
            ..where((l) => l.action.equals('table_close')))
          .get();
      expect(logs.single.entityId, t);
    });
  });

  group('cancelOrder', () {
    test('يرفض إلغاءَ طلبٍ دُفع منه شيء', () async {
      final t = await newTable('ط١٣');
      final orderId = await service.openTable(
          tableId: t, guestCount: 2, userId: null, userName: 'أحمد');
      await (db.update(db.tableOrders)..where((o) => o.id.equals(orderId)))
          .write(const TableOrdersCompanion(
              total: Value(100), paidAmount: Value(40)));

      expect(
        () => service.cancelOrder(
            tableId: t, userId: null, userName: 'أحمد'),
        throwsA(isA<TableTransitionException>()),
      );
    });

    test('يُلغي طلباً بكراً ويُحرّر الطاولة', () async {
      final t = await newTable('ط١٤');
      await service.openTable(
          tableId: t, guestCount: 2, userId: null, userName: 'أحمد');

      await service.cancelOrder(tableId: t, userId: null, userName: 'أحمد');

      expect((await readTable(t)).status, TableStatus.available);

      final logs = await (db.select(db.activityLogs)
            ..where((l) => l.action.equals('table_order_cancel')))
          .get();
      expect(logs.single.entityId, t);
    });
  });

  group('setTableStatus', () {
    test('يُخرج طاولةً متاحةً من الخدمة ويُعيدها', () async {
      final t = await newTable('ط١٥');
      await service.setTableStatus(
          tableId: t,
          status: TableStatus.outOfService,
          userId: null,
          userName: 'أحمد');
      expect((await readTable(t)).status, TableStatus.outOfService);

      final logs = await (db.select(db.activityLogs)
            ..where((l) => l.action.equals('table_status_change')))
          .get();
      expect(logs.single.entityId, t);

      await service.setTableStatus(
          tableId: t,
          status: TableStatus.available,
          userId: null,
          userName: 'أحمد');
      expect((await readTable(t)).status, TableStatus.available);
    });

    test('يرفض إخراجَ طاولةٍ عليها طلبٌ من الخدمة', () async {
      final t = await newTable('ط١٦');
      await service.openTable(
          tableId: t, guestCount: 2, userId: null, userName: 'أحمد');

      expect(
        () => service.setTableStatus(
            tableId: t,
            status: TableStatus.outOfService,
            userId: null,
            userName: 'أحمد'),
        throwsA(isA<TableTransitionException>()),
      );
    });
  });

  group('transferOrder', () {
    test('ينقل الطلبَ بكلّ حقوله ويُحرّر المصدر', () async {
      final from = await newTable('ط٢٠');
      final to = await newTable('ط٢١');
      final orderId = await service.openTable(
          tableId: from, guestCount: 4, userId: null, userName: 'أحمد');
      await (db.update(db.tableOrders)..where((o) => o.id.equals(orderId)))
          .write(const TableOrdersCompanion(
        notes: Value('بجانب النافذة'),
        discountType: Value('percent'),
        discountValue: Value(10),
      ));

      await service.transferOrder(
          fromTableId: from,
          toTableId: to,
          userId: null,
          userName: 'أحمد');

      expect((await readTable(from)).status, TableStatus.available);
      expect((await readTable(to)).status, TableStatus.occupied);

      final moved = await db.getActiveOrderForTable(to);
      expect(moved!.id, orderId, reason: 'رقمُ الطلب نفسُه ينتقل');
      expect(moved.guestCount, 4);
      expect(moved.notes, 'بجانب النافذة');
      expect(moved.discountValue, 10);
    });

    test('يرفض نقلَ طلبٍ دُفع منه شيء', () async {
      final from = await newTable('ط٢٢');
      final to = await newTable('ط٢٣');
      final orderId = await service.openTable(
          tableId: from, guestCount: 2, userId: null, userName: 'أحمد');
      await (db.update(db.tableOrders)..where((o) => o.id.equals(orderId)))
          .write(const TableOrdersCompanion(
              total: Value(100), paidAmount: Value(40)));

      expect(
        () => service.transferOrder(
            fromTableId: from,
            toTableId: to,
            userId: null,
            userName: 'أحمد'),
        throwsA(isA<TableTransitionException>()),
      );
    });

    test('يرفض هدفاً غيرَ متاح', () async {
      final from = await newTable('ط٢٤');
      final to = await newTable('ط٢٥');
      await service.openTable(
          tableId: from, guestCount: 2, userId: null, userName: 'أحمد');
      await service.openTable(
          tableId: to, guestCount: 2, userId: null, userName: 'أحمد');

      expect(
        () => service.transferOrder(
            fromTableId: from,
            toTableId: to,
            userId: null,
            userName: 'أحمد'),
        throwsA(isA<TableTransitionException>()),
      );
    });
  });

  group('mergeOrders', () {
    // tableOrderItems.productId مفتاحٌ خارجيٌّ إلى products، وforTesting()
    // تُنفِذ القيودَ الخارجية — فلا بدّ من صنفٍ موجودٍ قبل أيّ addItem
    // بـproductId: 1 (راجع hold_order_usecase_test.dart لنفس النمط).
    setUp(() async {
      await db
          .into(db.products)
          .insert(ProductsCompanion.insert(code: 'MRG-1', name: 'صنفُ الدمج'));
    });

    Future<void> addItem(int orderId, int productId, double qty,
            double price) =>
        db.into(db.tableOrderItems).insert(
              TableOrderItemsCompanion.insert(
                tableOrderId: orderId,
                productId: productId,
                quantity: qty,
                unitPrice: price,
                total: qty * price,
              ),
            );

    test('لا يجمع كميّاتِ المتشابه ويوسم كلَّ بندٍ بمصدره', () async {
      final t5 = await newTable('ط٥');
      final t6 = await newTable('ط٦');
      final o5 = await service.openTable(
          tableId: t5, guestCount: 2, userId: null, userName: 'أحمد');
      final o6 = await service.openTable(
          tableId: t6, guestCount: 3, userId: null, userName: 'أحمد');
      await addItem(o5, 1, 2, 10); // نفسُ المنتج على الطاولتين
      await addItem(o6, 1, 1, 10);

      await service.mergeOrders(
          sourceTableId: t6,
          targetTableId: t5,
          userId: null,
          userName: 'أحمد');

      final items = await db.getTableOrderItems(o5);
      expect(items, hasLength(2),
          reason: 'بندان منفصلان لا بندٌ واحدٌ بكميّة ٣');
      final fromSix =
          items.firstWhere((i) => i.sourceTableOrderId == o6);
      expect(fromSix.quantity, 1);
      expect(items.where((i) => i.sourceTableOrderId == null), hasLength(1));
    });

    test('يجمع عددَ الضيوف ويُحرّر المصدر', () async {
      final t5 = await newTable('ط٣٠');
      final t6 = await newTable('ط٣١');
      final o5 = await service.openTable(
          tableId: t5, guestCount: 2, userId: null, userName: 'أحمد');
      final o6 = await service.openTable(
          tableId: t6, guestCount: 3, userId: null, userName: 'أحمد');
      await addItem(o6, 1, 1, 10);

      await service.mergeOrders(
          sourceTableId: t6,
          targetTableId: t5,
          userId: null,
          userName: 'أحمد');

      final merged = await db.getActiveOrderForTable(t5);
      expect(merged!.guestCount, 5);
      expect((await readTable(t6)).status, TableStatus.available);
      final source = await (db.select(db.tableOrders)
            ..where((o) => o.id.equals(o6)))
          .getSingle();
      expect(source.mergedToId, o5);
    });

    test('خصمُ المدموجة يسقط ويُبلَّغ عنه', () async {
      final t5 = await newTable('ط٣٢');
      final t6 = await newTable('ط٣٣');
      final o5 = await service.openTable(
          tableId: t5, guestCount: 2, userId: null, userName: 'أحمد');
      final o6 = await service.openTable(
          tableId: t6, guestCount: 2, userId: null, userName: 'أحمد');
      await (db.update(db.tableOrders)..where((o) => o.id.equals(o5)))
          .write(const TableOrdersCompanion(
              discountType: Value('percent'), discountValue: Value(10)));
      await (db.update(db.tableOrders)..where((o) => o.id.equals(o6)))
          .write(const TableOrdersCompanion(
              discountType: Value('amount'), discountValue: Value(5)));
      await addItem(o6, 1, 1, 10);

      final outcome = await service.mergeOrders(
          sourceTableId: t6,
          targetTableId: t5,
          userId: null,
          userName: 'أحمد');

      expect(outcome.droppedDiscount, isTrue);
      final merged = await db.getActiveOrderForTable(t5);
      expect(merged!.discountType, 'percent');
      expect(merged.discountValue, 10, reason: 'خصمُ الرئيسية يبقى وحده');
    });

    test('يرفض الدمجَ إن دُفع من أيٍّ منهما شيء', () async {
      final t5 = await newTable('ط٣٤');
      final t6 = await newTable('ط٣٥');
      final o5 = await service.openTable(
          tableId: t5, guestCount: 2, userId: null, userName: 'أحمد');
      await service.openTable(
          tableId: t6, guestCount: 2, userId: null, userName: 'أحمد');
      await (db.update(db.tableOrders)..where((o) => o.id.equals(o5)))
          .write(const TableOrdersCompanion(
              total: Value(50), paidAmount: Value(20)));

      expect(
        () => service.mergeOrders(
            sourceTableId: t6,
            targetTableId: t5,
            userId: null,
            userName: 'أحمد'),
        throwsA(isA<TableTransitionException>()),
      );
    });

    test('يرفض دمجَ الطاولة في نفسها ولا يمسّ طلبها', () async {
      final t = await newTable('ط٣٦');
      final orderId = await service.openTable(
          tableId: t, guestCount: 2, userId: null, userName: 'أحمد');

      await expectLater(
        () => service.mergeOrders(
            sourceTableId: t,
            targetTableId: t,
            userId: null,
            userName: 'أحمد'),
        throwsA(isA<TableTransitionException>()),
      );

      final order = await db.getActiveOrderForTable(t);
      expect(order!.id, orderId,
          reason: 'الطلبُ لم يُغلَق ولم يُدمَج في نفسه');
      expect((await readTable(t)).status, TableStatus.occupied);
    });

    test('يحفظ أصلَ البندِ الحقيقيَّ عبر دمجٍ متسلسل', () async {
      final tA = await newTable('ط٤٠');
      final tB = await newTable('ط٤١');
      final tC = await newTable('ط٤٢');
      final oA = await service.openTable(
          tableId: tA, guestCount: 2, userId: null, userName: 'أحمد');
      final oB = await service.openTable(
          tableId: tB, guestCount: 2, userId: null, userName: 'أحمد');
      final oC = await service.openTable(
          tableId: tC, guestCount: 2, userId: null, userName: 'أحمد');
      await addItem(oC, 1, 1, 10);

      await service.mergeOrders(
          sourceTableId: tC,
          targetTableId: tB,
          userId: null,
          userName: 'أحمد');
      await service.mergeOrders(
          sourceTableId: tB,
          targetTableId: tA,
          userId: null,
          userName: 'أحمد');

      final items = await db.getTableOrderItems(oA);
      expect(items, hasLength(1));
      expect(items.single.sourceTableOrderId, oC,
          reason: 'الأصلُ الحقيقيُّ (ج) يبقى لا الوسيط (ب)');
    });
  });

  group('setOrderDiscount', () {
    test('خصمٌ نسبيٌّ يُثبَّت ويُسجَّل بقيمته القديمة والجديدة', () async {
      final t = await newTable('ط٤٠');
      final orderId = await service.openTable(
          tableId: t, guestCount: 2, userId: null, userName: 'أحمد');

      await service.setOrderDiscount(
          orderId: orderId,
          type: 'percent',
          value: 10,
          userId: null,
          userName: 'أحمد');

      final order = await db.getActiveOrderForTable(t);
      expect(order!.discountType, 'percent');
      expect(order.discountValue, 10);

      final logs = await (db.select(db.activityLogs)
            ..where((l) => l.action.equals('table_discount')))
          .get();
      expect(logs.single.newValue, 'percent:10.0');
    });

    test('نسبةٌ فوق ١٠٠٪ تُرفض', () async {
      final t = await newTable('ط٤١');
      final orderId = await service.openTable(
          tableId: t, guestCount: 2, userId: null, userName: 'أحمد');
      expect(
        () => service.setOrderDiscount(
            orderId: orderId,
            type: 'percent',
            value: 120,
            userId: null,
            userName: 'أحمد'),
        throwsA(isA<TableTransitionException>()),
      );
    });

    test('خصمٌ يتجاوز الإجماليَّ يُرفض', () async {
      final t = await newTable('ط٤٢');
      final orderId = await service.openTable(
          tableId: t, guestCount: 2, userId: null, userName: 'أحمد');
      await (db.update(db.tableOrders)..where((o) => o.id.equals(orderId)))
          .write(const TableOrdersCompanion(total: Value(50)));

      expect(
        () => service.setOrderDiscount(
            orderId: orderId,
            type: 'amount',
            value: 60,
            userId: null,
            userName: 'أحمد'),
        throwsA(isA<TableTransitionException>()),
      );
    });

    test('يرفض تعديلَ خصمِ طلبٍ دُفع منه شيء', () async {
      final t = await newTable('ط٤٣');
      final orderId = await service.openTable(
          tableId: t, guestCount: 2, userId: null, userName: 'أحمد');
      await (db.update(db.tableOrders)..where((o) => o.id.equals(orderId)))
          .write(const TableOrdersCompanion(
              total: Value(100), paidAmount: Value(30)));

      expect(
        () => service.setOrderDiscount(
            orderId: orderId,
            type: 'percent',
            value: 10,
            userId: null,
            userName: 'أحمد'),
        throwsA(isA<TableTransitionException>()),
      );
    });
  });

  group('effectiveTotal', () {
    test('النسبةُ تُطبَّق على الإجمالي', () async {
      final t = await newTable('ط٤٤');
      final orderId = await service.openTable(
          tableId: t, guestCount: 2, userId: null, userName: 'أحمد');
      await (db.update(db.tableOrders)..where((o) => o.id.equals(orderId)))
          .write(const TableOrdersCompanion(
        total: Value(100),
        discountType: Value('percent'),
        discountValue: Value(10),
      ));
      expect(await service.effectiveTotal(orderId), 90);
    });

    test('المبلغُ يُطرح كما هو', () async {
      final t = await newTable('ط٤٥');
      final orderId = await service.openTable(
          tableId: t, guestCount: 2, userId: null, userName: 'أحمد');
      await (db.update(db.tableOrders)..where((o) => o.id.equals(orderId)))
          .write(const TableOrdersCompanion(
        total: Value(100),
        discountType: Value('amount'),
        discountValue: Value(15),
      ));
      expect(await service.effectiveTotal(orderId), 85);
    });
  });

  group('requestTableBill', () {
    test('طلبُ الفاتورة يغيّر الطلبَ لا الطاولة', () async {
      final t = await newTable('ط٦٠');
      final orderId = await service.openTable(
          tableId: t, guestCount: 2, userId: null, userName: 'أحمد');

      await db.requestTableBill(orderId);

      expect((await readTable(t)).status, TableStatus.occupied,
          reason: 'billing حالةٌ مشطوبةٌ من الطاولة');
      final order = await db.getActiveOrderForTable(t);
      expect(order!.status, 'bill_requested');
    });
  });

  group('setItemNotes', () {
    test('الملاحظةُ تُحفظ على البند', () async {
      final t = await newTable('ط٤٦');
      final orderId = await service.openTable(
          tableId: t, guestCount: 2, userId: null, userName: 'أحمد');
      // tableOrderItems.productId مفتاحٌ خارجيٌّ إلى products، وforTesting()
      // تُنفِذ القيودَ الخارجية — فلا بدّ من صنفٍ موجودٍ قبل الإدراج بـ
      // productId: 1 (نفسُ نمط setUp في مجموعة mergeOrders).
      await db
          .into(db.products)
          .insert(ProductsCompanion.insert(code: 'NOTE-1', name: 'صنفُ الملاحظة'));
      final itemId = await db.into(db.tableOrderItems).insert(
            TableOrderItemsCompanion.insert(
              tableOrderId: orderId,
              productId: 1,
              quantity: 1,
              unitPrice: 10,
              total: 10,
            ),
          );

      await service.setItemNotes(orderItemId: itemId, notes: 'بلا بصل');

      final item = await (db.select(db.tableOrderItems)
            ..where((i) => i.id.equals(itemId)))
          .getSingle();
      expect(item.notes, 'بلا بصل');
    });
  });

  group('recordPayment', () {
    // table_order_payments.invoice_id يتبع sales_invoices، والقيدُ الأجنبي
    // مُفعَّلٌ في اختبارات forTesting() — فتُزرع فواتيرُ حقيقيّةٌ بمعرّفاتٍ
    // صريحة (١، ٢، ٧، ٨) تغطّي كلَّ invoiceId تستخدمه اختباراتُ هذه
    // المجموعة، بدل الاعتماد على الترقيم التلقائي (نفسُ نمط
    // table_service_schema_test.dart). المخزنُ والمستخدمُ مبذوران سلفاً في
    // beforeOpen فيُعاد استخدامهما.
    setUp(() async {
      final warehouseId = (await db.select(db.warehouses).get()).first.id;
      final userId = (await db.select(db.users).get()).first.id;
      for (final id in [1, 2, 7, 8]) {
        await db.into(db.salesInvoices).insert(
              SalesInvoicesCompanion.insert(
                id: Value(id),
                invoiceNumber: 'INV-TEST-$id',
                warehouseId: warehouseId,
                userId: userId,
                invoiceDate: DateTime.now(),
              ),
            );
      }
    });

    Future<int> orderWithTotal(int tableId, double total) async {
      final orderId = await service.openTable(
          tableId: tableId, guestCount: 4, userId: null, userName: 'أحمد');
      await (db.update(db.tableOrders)..where((o) => o.id.equals(orderId)))
          .write(TableOrdersCompanion(total: Value(total)));
      return orderId;
    }

    test('دفعةٌ جزئيّةٌ تُبقي الطاولة مشغولة', () async {
      final t = await newTable('ط٥٠');
      final orderId = await orderWithTotal(t, 100);

      await service.recordPayment(
          orderId: orderId, invoiceId: 1, amount: 40, splitLabel: 'ضيف ١');

      expect((await readTable(t)).status, TableStatus.occupied);
      final order = await db.getActiveOrderForTable(t);
      expect(order!.paidAmount, 40);
    });

    test('اكتمالُ المبلغ يقلب الطاولة إلى مدفوعة', () async {
      final t = await newTable('ط٥١');
      final orderId = await orderWithTotal(t, 100);

      await service.recordPayment(
          orderId: orderId, invoiceId: 1, amount: 40, splitLabel: 'ضيف ١');
      await service.recordPayment(
          orderId: orderId, invoiceId: 2, amount: 60, splitLabel: 'ضيف ٢');

      expect((await readTable(t)).status, TableStatus.paid);
    });

    test('ثلاثُ حصصٍ من ١٠٠÷٣ تُكمل المبلغ ولا تترك مليماً', () async {
      final t = await newTable('ط٥٢');
      final orderId = await orderWithTotal(t, 100);

      for (final amount in [33.333, 33.333, 33.334]) {
        await service.recordPayment(
            orderId: orderId, invoiceId: 1, amount: amount);
      }

      expect((await readTable(t)).status, TableStatus.paid,
          reason: 'المقارنةُ بالوحدات لا بـdouble');
    });

    test('الخصمُ يخفض المبلغَ الواجب', () async {
      final t = await newTable('ط٥٣');
      final orderId = await orderWithTotal(t, 100);
      await service.setOrderDiscount(
          orderId: orderId,
          type: 'percent',
          value: 10,
          userId: null,
          userName: 'أحمد');

      await service.recordPayment(
          orderId: orderId, invoiceId: 1, amount: 90);

      expect((await readTable(t)).status, TableStatus.paid);
    });

    test('دفعةٌ تتجاوز المتبقّي تُرفض', () async {
      final t = await newTable('ط٥٤');
      final orderId = await orderWithTotal(t, 100);
      await service.recordPayment(
          orderId: orderId, invoiceId: 1, amount: 60);

      expect(
        () => service.recordPayment(
            orderId: orderId, invoiceId: 2, amount: 50),
        throwsA(isA<TableTransitionException>()),
      );
    });

    test('الدفعاتُ تُقرأ مرتّبةً بحصصها', () async {
      final t = await newTable('ط٥٥');
      final orderId = await orderWithTotal(t, 100);
      await service.recordPayment(
          orderId: orderId, invoiceId: 7, amount: 40, splitLabel: 'ضيف ١');
      await service.recordPayment(
          orderId: orderId, invoiceId: 8, amount: 60, splitLabel: 'ضيف ٢');

      final payments = await service.paymentsFor(orderId);
      expect(payments, hasLength(2));
      expect(payments.first.invoiceId, 7);
      expect(payments.last.splitLabel, 'ضيف ٢');
    });

    test('الإغلاقُ يصير مسموحاً بعد اكتمال الدفع', () async {
      final t = await newTable('ط٥٦');
      final orderId = await orderWithTotal(t, 100);
      await service.recordPayment(
          orderId: orderId, invoiceId: 1, amount: 100);

      await service.closeTable(tableId: t, userId: null, userName: 'أحمد');
      expect((await readTable(t)).status, TableStatus.available);
    });

    test('يرفض الدفعَ على طلبٍ مُلغًى ولا يقلب الطاولة', () async {
      final t = await newTable('ط٥٧');
      final orderId = await orderWithTotal(t, 100);
      await service.cancelOrder(tableId: t, userId: null, userName: 'أحمد');

      expect(
        () => service.recordPayment(
            orderId: orderId, invoiceId: 1, amount: 100),
        throwsA(isA<TableTransitionException>()),
      );
      expect((await readTable(t)).status, TableStatus.available,
          reason: 'الطاولةُ لم تُقلَب رغم أنّ الدفعةَ سُجِّلت على طلبٍ باطل');
    });

    test('يكتب سطراً واحداً في السجل بنوع الكيان ومعرّفه ومبلغه', () async {
      final t = await newTable('ط٥٨');
      final orderId = await orderWithTotal(t, 100);

      await service.recordPayment(
          orderId: orderId, invoiceId: 1, amount: 40, splitLabel: 'ضيف ١');

      final logs = await (db.select(db.activityLogs)
            ..where((l) => l.action.equals('table_payment')))
          .get();
      expect(logs, hasLength(1));
      expect(logs.single.entityType, 'table');
      expect(logs.single.entityId, t);
      expect(logs.single.amount, 40);
    });
  });
}
