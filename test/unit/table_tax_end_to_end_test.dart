import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/entities/cart_item_entity.dart';
import 'package:ural_erp/domain/models/split_plan.dart';
import 'package:ural_erp/domain/models/table_charge_check.dart';
import 'package:ural_erp/domain/models/table_status.dart';
import 'package:ural_erp/presentation/pos/providers/cart_controller.dart';
import 'package:ural_erp/services/table_checkout_coordinator.dart';
import 'package:ural_erp/services/table_session_service.dart';

/// ضريبةُ المبيعات على طلبات الطاولات — البرهانُ الطرفيّ.
///
/// ملاحظاتُ الدمج §١ سجّلت القدرةَ المفقودة بصراحة: «الضريبةُ مفعَّلة ⇐
/// **كلُّ تحصيلِ طاولةٍ يُرفض**». والسببُ محرّكان لا واحد: السلّةُ تحسب
/// بـ`CalculateInvoiceTotalsUseCase` (ضريبةٌ فوق الصافي)، والطلبُ يحسب
/// `SUM(quantity × unitPrice)` بلا ضريبة. فحارسُ [checkTableCharge] كان
/// يرفض — **بحقّ**، لأن الرقمين كانا مختلفين فعلاً.
///
/// هذا الملفُّ يقيس أن الرقمين صارا واحداً. وهو يبني السلّةَ بالضبط كما
/// تبنيها `_checkoutTable`، ثم يقرأ `CartState.total` — الحسابَ الحقيقيَّ
/// لا محاكاةً له — ويمرّره على الحارس نفسِه الذي يحرس الإنتاج.
void main() {
  late AppDatabase db;
  late TableSessionService service;
  int? seedProductId;

  setUp(() {
    db = AppDatabase.forTesting();
    service = TableSessionService(db);
    seedProductId = null;
  });
  tearDown(() => db.close());

  /// صنفٌ حقيقيٌّ — `tableOrderItems.productId` مفتاحٌ خارجيٌّ مُنفَذ.
  Future<int> product() async =>
      seedProductId ??= await db.into(db.products).insert(
            ProductsCompanion.insert(code: 'TAX-1', name: 'مشويّ'),
          );

  Future<void> addItem(
    int orderId, {
    required double quantity,
    required double unitPrice,
    required double taxRate,
  }) async {
    await db.addOrUpdateTableOrderItem(
      orderId: orderId,
      productId: await product(),
      quantity: quantity,
      unitPrice: unitPrice,
      taxRate: taxRate,
    );
  }

  /// السلّةُ كما تبنيها شاشةُ التحصيل: بنودٌ من الطلب بنِسَبها، وضريبةُ
  /// الطلب ونسبتُه. أيُّ انحرافٍ هنا عن `_checkoutTable` يُبطل البرهان.
  Future<double> chargedByCheckout(int orderId) async {
    final order = await (db.select(db.tableOrders)
          ..where((o) => o.id.equals(orderId)))
        .getSingle();
    final items = await db.getTableOrderItems(orderId);
    final cart = CartState(
      items: [
        for (final i in items)
          CartItemEntity(
            productId: i.productId,
            productName: 'مشويّ',
            productCode: 'TAX-1',
            quantity: i.quantity,
            unitPrice: i.unitPrice,
            customPrice: i.unitPrice,
            taxRate: i.taxRate,
          ),
      ],
      taxEnabled: order.taxEnabled,
      taxRate: order.taxRate,
    );
    return cart.total;
  }

  Future<int> openTaxedTable(String name, {double rate = 0.16}) async {
    final tableId = await db.createTable(name: name);
    final orderId = await service.openTable(
      tableId: tableId,
      guestCount: 2,
      userId: null,
      userName: 'أحمد',
      taxRate: rate,
    );
    await service.setOrderTax(
        orderId: orderId, enabled: true, userId: null, userName: 'أحمد');
    return orderId;
  }

  group('الحارسُ القبليُّ يمرّ والضريبةُ مفعَّلة', () {
    test('نسبةُ الطلب: المشحونُ = المستحقُّ إلى آخر وحدة', () async {
      final orderId = await openTaxedTable('ط١');
      // ثلاثُ وحداتٍ بـ١٩٫٩٩ — كسورٌ تُظهر أيَّ افتراقٍ في التقريب.
      await addItem(orderId, quantity: 3, unitPrice: 19.99, taxRate: 0);

      final charged = await chargedByCheckout(orderId);
      final due = await service.amountDue(orderId);

      expect(checkTableCharge(charged: charged, expected: due), isNull,
          reason: 'هذا الرفضُ بعينه كان يوقف كلَّ تحصيلِ طاولةٍ بضريبة');
      expect(charged, greaterThan(59.97),
          reason: 'بلا ضريبةٍ لكان ٥٩٫٩٧ — فالضريبةُ محسوبةٌ حقّاً');
      expect(due, 69.565); // ٥٩٫٩٧ + ١٦٪
    });

    test('نسبةُ البند تسبق نسبةَ الطلب على الطرفين معاً', () async {
      final orderId = await openTaxedTable('ط٢');
      // البندُ يحمل ٥٪ صراحةً بينما نسبةُ الطلب ١٦٪.
      await addItem(orderId, quantity: 2, unitPrice: 50, taxRate: 5);

      final charged = await chargedByCheckout(orderId);
      final due = await service.amountDue(orderId);

      expect(checkTableCharge(charged: charged, expected: due), isNull);
      expect(due, 105.0, reason: '١٠٠ + ٥٪ لا + ١٦٪');
    });

    test('الخصمُ والضريبةُ معاً — الضريبةُ على الصافي في المحرّكين', () async {
      final orderId = await openTaxedTable('ط٣');
      await addItem(orderId, quantity: 10, unitPrice: 10, taxRate: 0);
      await service.setOrderDiscount(
          orderId: orderId,
          type: 'percent',
          value: 10,
          userId: null,
          userName: 'أحمد');

      final order = await (db.select(db.tableOrders)
            ..where((o) => o.id.equals(orderId)))
          .getSingle();
      final items = await db.getTableOrderItems(orderId);
      // نفسُ ما تفعله `_checkoutTable`: خصمُ الطلب يُنقل إلى السلّة.
      final cart = CartState(
        items: [
          for (final i in items)
            CartItemEntity(
              productId: i.productId,
              productName: 'مشويّ',
              productCode: 'TAX-1',
              quantity: i.quantity,
              unitPrice: i.unitPrice,
              customPrice: i.unitPrice,
              taxRate: i.taxRate,
            ),
        ],
        discountPercent: order.discountValue,
        taxEnabled: order.taxEnabled,
        taxRate: order.taxRate,
      );

      final due = await service.amountDue(orderId);
      expect(checkTableCharge(charged: cart.total, expected: due), isNull);
      expect(due, 104.4, reason: '(١٠٠ − ١٠) + ١٦٪ من ٩٠');
    });

    test('الضريبةُ مطفأةٌ ⇒ الحارسُ يمرّ كما كان قبل هذا العمل', () async {
      final tableId = await db.createTable(name: 'ط٤');
      final orderId = await service.openTable(
        tableId: tableId,
        guestCount: 2,
        userId: null,
        userName: 'أحمد',
        taxRate: 0.16,
      );
      // النسبةُ ملقوطةٌ لكنّ الزرَّ لم يُضغَط — فلا ضريبة.
      await addItem(orderId, quantity: 3, unitPrice: 19.99, taxRate: 16);

      final charged = await chargedByCheckout(orderId);
      final due = await service.amountDue(orderId);

      expect(checkTableCharge(charged: charged, expected: due), isNull);
      expect(due, 59.97, reason: 'الإطفاءُ يعلو على نسبة البند');
    });
  });

  group('الطلبُ المضرَّبُ يُسدَّد ويُغلَق', () {
    test('دفعُ المستحقِّ كاملاً يقلب الطاولة 🟠 ثم تُغلَق', () async {
      final warehouseId = (await db.select(db.warehouses).get()).first.id;
      final userId = (await db.select(db.users).get()).first.id;
      await db.into(db.salesInvoices).insert(
            SalesInvoicesCompanion.insert(
              id: const Value(1),
              invoiceNumber: 'INV-TAX-1',
              warehouseId: warehouseId,
              userId: userId,
              invoiceDate: DateTime.now(),
            ),
          );

      final orderId = await openTaxedTable('ط٥');
      await addItem(orderId, quantity: 3, unitPrice: 19.99, taxRate: 0);
      final order = await (db.select(db.tableOrders)
            ..where((o) => o.id.equals(orderId)))
          .getSingle();

      final due = await service.amountDue(orderId);
      expect(due, 69.565);

      // الدفعُ بالمستحقِّ **شاملَ الضريبة**: لو قاس `recordPayment` على
      // إجماليٍّ بلا ضريبةٍ لَرفض هذه الدفعةَ بعينها لتجاوزها المتبقّي.
      await service.recordPayment(
          orderId: orderId, invoiceId: 1, amount: due);

      final table = await (db.select(db.restaurantTables)
            ..where((t) => t.id.equals(order.tableId)))
          .getSingle();
      expect(table.status, TableStatus.paid);

      await service.closeTable(
          tableId: order.tableId, userId: null, userName: 'أحمد');
      expect(
        (await (db.select(db.restaurantTables)
                  ..where((t) => t.id.equals(order.tableId)))
                .getSingle())
            .status,
        TableStatus.available,
      );
      expect(await db.getActiveOrderForTable(order.tableId), isNull);
    });

    test('دفعُ الإجماليِّ بلا ضريبةٍ لا يُغلق الطاولة', () async {
      final warehouseId = (await db.select(db.warehouses).get()).first.id;
      final userId = (await db.select(db.users).get()).first.id;
      await db.into(db.salesInvoices).insert(
            SalesInvoicesCompanion.insert(
              id: const Value(1),
              invoiceNumber: 'INV-TAX-2',
              warehouseId: warehouseId,
              userId: userId,
              invoiceDate: DateTime.now(),
            ),
          );

      final orderId = await openTaxedTable('ط٦');
      await addItem(orderId, quantity: 3, unitPrice: 19.99, taxRate: 0);
      final order = await (db.select(db.tableOrders)
            ..where((o) => o.id.equals(orderId)))
          .getSingle();

      // ٥٩٫٩٧ هو الإجماليُّ قبل الضريبة — دفعةٌ ناقصةٌ لا مكتملة.
      await service.recordPayment(
          orderId: orderId, invoiceId: 1, amount: 59.97);

      expect(
        (await (db.select(db.restaurantTables)
                  ..where((t) => t.id.equals(order.tableId)))
                .getSingle())
            .status,
        TableStatus.occupied,
        reason: 'الضريبةُ جزءٌ من المستحقّ، فالطاولةُ لم تُسدَّد بعد',
      );
      expect(await service.amountDue(orderId), 9.595);
      expect(
        () => service.closeTable(
            tableId: order.tableId, userId: null, userName: 'أحمد'),
        throwsA(isA<TableTransitionException>()),
      );
    });
  });

  group('setOrderTax', () {
    test('يكتب سطرَه في السجل بالقيمة القديمة والجديدة', () async {
      final tableId = await db.createTable(name: 'ط٧');
      final orderId = await service.openTable(
          tableId: tableId,
          guestCount: 2,
          userId: null,
          userName: 'أحمد',
          taxRate: 0.16);

      await service.setOrderTax(
          orderId: orderId, enabled: true, userId: null, userName: 'أحمد');

      final order = await (db.select(db.tableOrders)
            ..where((o) => o.id.equals(orderId)))
          .getSingle();
      expect(order.taxEnabled, isTrue);
      expect(order.taxRate, 0.16, reason: 'النسبةُ ملقوطةٌ عند الفتح');

      final logs = await (db.select(db.activityLogs)
            ..where((l) => l.action.equals('table_tax')))
          .get();
      expect(logs, hasLength(1));
      expect(logs.single.entityType, 'table');
      expect(logs.single.entityId, tableId);
      expect(logs.single.oldValue, 'off');
      expect(logs.single.newValue, 'on');
    });

    test('لا سطرَ لتغييرٍ لا يغيّر شيئاً', () async {
      final tableId = await db.createTable(name: 'ط٨');
      final orderId = await service.openTable(
          tableId: tableId, guestCount: 2, userId: null, userName: 'أحمد');

      await service.setOrderTax(
          orderId: orderId, enabled: false, userId: null, userName: 'أحمد');

      expect(
        await (db.select(db.activityLogs)
              ..where((l) => l.action.equals('table_tax')))
            .get(),
        isEmpty,
      );
    });

    test('يرفض تعديلَ ضريبةِ طلبٍ دُفع منه شيء', () async {
      final warehouseId = (await db.select(db.warehouses).get()).first.id;
      final userId = (await db.select(db.users).get()).first.id;
      await db.into(db.salesInvoices).insert(
            SalesInvoicesCompanion.insert(
              id: const Value(1),
              invoiceNumber: 'INV-TAX-3',
              warehouseId: warehouseId,
              userId: userId,
              invoiceDate: DateTime.now(),
            ),
          );

      final tableId = await db.createTable(name: 'ط٩');
      final orderId = await service.openTable(
          tableId: tableId,
          guestCount: 2,
          userId: null,
          userName: 'أحمد',
          taxRate: 0.16);
      await addItem(orderId, quantity: 1, unitPrice: 100, taxRate: 0);
      await service.recordPayment(
          orderId: orderId, invoiceId: 1, amount: 40);

      // تغييرُ الضريبة الآن يُعيد تسعيرَ حصّةٍ صدرت فاتورتُها وحُصِّلت.
      expect(
        () => service.setOrderTax(
            orderId: orderId, enabled: true, userId: null, userName: 'أحمد'),
        throwsA(isA<TableTransitionException>()),
      );
      expect(
        (await (db.select(db.tableOrders)..where((o) => o.id.equals(orderId)))
                .getSingle())
            .taxEnabled,
        isFalse,
      );
    });
  });

  group('التقسيمُ على طاولةٍ مضرَّبة', () {
    test('بالتساوي: مجموعُ الحصص = المستحقُّ بالضبط', () async {
      final orderId = await openTaxedTable('ط١٢');
      await addItem(orderId, quantity: 3, unitPrice: 19.99, taxRate: 0);

      final coordinator =
          TableCheckoutCoordinator(db: db, session: service);
      final plan = await coordinator.buildSplitPlan(
          orderId: orderId, mode: SplitMode.equal, ways: 3);

      final sum = plan.parts.fold<double>(0, (s, p) => s + p.amount);
      expect(tableMoneyUnits(sum),
          tableMoneyUnits(await service.effectiveTotal(orderId)));
    });

    test('بالأصناف: الحصصُ تحمل الضريبةَ فتبلغ المستحقّ', () async {
      final tableId = await db.createTable(name: 'ط١٣');
      final orderId = await service.openTable(
          tableId: tableId,
          guestCount: 2,
          userId: null,
          userName: 'أحمد',
          taxRate: 0.16);
      await service.setOrderTax(
          orderId: orderId, enabled: true, userId: null, userName: 'أحمد');

      final p2 = await db.into(db.products).insert(
            ProductsCompanion.insert(code: 'TAX-2', name: 'عصير'),
          );
      await db.addOrUpdateTableOrderItem(
          orderId: orderId,
          productId: await product(),
          quantity: 1,
          unitPrice: 60,
          taxRate: 0);
      await db.addOrUpdateTableOrderItem(
          orderId: orderId,
          productId: p2,
          quantity: 1,
          unitPrice: 40,
          taxRate: 0);

      final items = await db.getTableOrderItems(orderId);
      final coordinator =
          TableCheckoutCoordinator(db: db, session: service);
      final plan = await coordinator.buildSplitPlan(
        orderId: orderId,
        mode: SplitMode.byItems,
        assignment: {items[0].id: 0, items[1].id: 1},
        ways: 2,
      );

      final due = await service.effectiveTotal(orderId);
      expect(due, 116.0);
      // ٦٠ + ١٦٪ و٤٠ + ١٦٪ — لا ٦٠ و٤٠ الخامّين.
      expect(plan.parts[0].amount, 69.6);
      expect(plan.parts[1].amount, 46.4);
      expect(
        tableMoneyUnits(plan.parts.fold<double>(0, (s, p) => s + p.amount)),
        tableMoneyUnits(due),
        reason: 'الحصصُ لو نقصت وحدةً لَبقيت الطاولةُ غيرَ مدفوعةٍ للأبد',
      );
    });
  });

  group('لا طلبَ يولد بلا نسبة', () {
    test('createTableOrder يحفظ النسبةَ الممرَّرة', () async {
      // هذا هو المسارُ الذي تسلكه `initTableOrder` حين تُفتح الشاشةُ على
      // طاولةٍ لا طلبَ حيَّ عليها — مسارٌ اعتياديٌّ لا ركنٌ نادر.
      final tableId = await db.createTable(name: 'ط٢٠');
      final orderId = await db.createTableOrder(tableId, taxRate: 0.16);

      final order = await (db.select(db.tableOrders)
            ..where((o) => o.id.equals(orderId)))
          .getSingle();
      expect(order.taxRate, 0.16);
      expect(order.taxEnabled, isFalse, reason: 'التفعيلُ قرارُ الكاشير');
    });

    test('seatReservation يفتح طلباً يحمل النسبة', () async {
      final tableId = await db.createTable(name: 'ط٢١');
      final reservationId = await db.into(db.tableReservations).insert(
            TableReservationsCompanion.insert(
              tableId: tableId,
              customerName: 'ضيف',
              reservationTime: DateTime.now(),
            ),
          );

      final orderId =
          await db.seatReservation(reservationId, taxRate: 0.16);

      final order = await (db.select(db.tableOrders)
            ..where((o) => o.id.equals(orderId)))
          .getSingle();
      expect(order.taxRate, 0.16,
          reason: 'حضورُ الحجز فتحُ طاولةٍ، فيلزمه ما يلزم الفتح');
    });

    test('setOrderTax يرفض التفعيلَ على طلبٍ نسبتُه صفر', () async {
      // الحالةُ المرفوضة هي بعينها ما كان يمرّ صامتاً: زرٌّ يقول «مفعلة»
      // ولا ضريبةَ تُحصَّل ولا حارسَ يُطلق.
      final tableId = await db.createTable(name: 'ط٢٢');
      final orderId = await service.openTable(
          tableId: tableId, guestCount: 2, userId: null, userName: 'أحمد');

      expect(
        () => service.setOrderTax(
            orderId: orderId, enabled: true, userId: null, userName: 'أحمد'),
        throwsA(isA<TableTransitionException>()),
      );

      final order = await (db.select(db.tableOrders)
            ..where((o) => o.id.equals(orderId)))
          .getSingle();
      expect(order.taxEnabled, isFalse, reason: 'الطلبُ يبقى كما كان');
      expect(order.taxRate, 0);
      expect(
        await (db.select(db.activityLogs)
              ..where((l) => l.action.equals('table_tax')))
            .get(),
        isEmpty,
        reason: 'رفضٌ لا يكتب سطراً',
      );
    });

    test('الإطفاءُ على طلبٍ نسبتُه صفرٌ يبقى مسموحاً', () async {
      // الحارسُ على التفعيل وحدَه: إطفاءُ ما هو مطفأٌ ليس كذباً.
      final tableId = await db.createTable(name: 'ط٢٣');
      final orderId = await service.openTable(
          tableId: tableId, guestCount: 2, userId: null, userName: 'أحمد');

      await service.setOrderTax(
          orderId: orderId, enabled: false, userId: null, userName: 'أحمد');

      expect(
        (await (db.select(db.tableOrders)..where((o) => o.id.equals(orderId)))
                .getSingle())
            .taxEnabled,
        isFalse,
      );
    });
  });

  group('نسبةُ الصنف تصل البند', () {
    test('الإضافةُ تكتب النسبة، والإضافةُ الثانيةُ لا تطمسها', () async {
      final tableId = await db.createTable(name: 'ط١٠');
      final orderId = await service.openTable(
          tableId: tableId, guestCount: 2, userId: null, userName: 'أحمد');

      await addItem(orderId, quantity: 1, unitPrice: 10, taxRate: 16);
      // المنتجُ غُيّرت ضريبتُه إلى ٥٪ في منتصف الوجبة.
      await addItem(orderId, quantity: 1, unitPrice: 10, taxRate: 5);

      final items = await db.getTableOrderItems(orderId);
      expect(items, hasLength(1));
      expect(items.single.quantity, 2);
      expect(items.single.taxRate, 16,
          reason: 'اللقطةُ الأولى تبقى — لا يُعاد تسعيرُ ما طُلب');
    });

    test('الخانةُ الفارغةُ تُملأ — صفوفُ ما قبل v155', () async {
      final tableId = await db.createTable(name: 'ط١١');
      final orderId = await service.openTable(
          tableId: tableId, guestCount: 2, userId: null, userName: 'أحمد');

      // صفٌّ قديمٌ بلا نسبة (كما كانت كلُّ الصفوف قبل هذا العمل).
      await addItem(orderId, quantity: 1, unitPrice: 10, taxRate: 0);
      await addItem(orderId, quantity: 1, unitPrice: 10, taxRate: 16);

      final items = await db.getTableOrderItems(orderId);
      expect(items.single.taxRate, 16);
    });
  });
}
