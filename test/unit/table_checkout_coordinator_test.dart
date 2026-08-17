import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/models/split_plan.dart';
import 'package:ural_erp/services/table_checkout_coordinator.dart';
import 'package:ural_erp/services/table_session_service.dart';

void main() {
  late AppDatabase db;
  late TableSessionService service;
  late TableCheckoutCoordinator coordinator;

  setUp(() {
    db = AppDatabase.forTesting();
    service = TableSessionService(db);
    coordinator = TableCheckoutCoordinator(db: db, session: service);
  });
  tearDown(() => db.close());

  Future<int> orderOf(double total, {int guests = 4}) async {
    final t = await db.createTable(name: 'ط');
    final orderId = await service.openTable(
        tableId: t, guestCount: guests, userId: null, userName: 'أحمد');
    await (db.update(db.tableOrders)..where((o) => o.id.equals(orderId)))
        .write(TableOrdersCompanion(total: Value(total)));
    return orderId;
  }

  test('التقسيمُ بالتساوي يستعمل عددَ الضيوف مقاماً', () async {
    final orderId = await orderOf(100, guests: 4);
    final plan = await coordinator.buildSplitPlan(
        orderId: orderId, mode: SplitMode.equal);
    expect(plan.parts, hasLength(4));
    expect(plan.parts.every((p) => p.amount == 25), isTrue);
  });

  test('التقسيمُ بالتساوي يحترم الخصم', () async {
    final orderId = await orderOf(100);
    await service.setOrderDiscount(
        orderId: orderId,
        type: 'percent',
        value: 20,
        userId: null,
        userName: 'أحمد');
    final plan = await coordinator.buildSplitPlan(
        orderId: orderId, mode: SplitMode.equal);
    expect(plan.parts.fold<double>(0, (s, p) => s + p.amount), 80);
  });

  test('تسويةُ حصّةٍ تسجّل الدفعةَ وتُقدّم المدفوع', () async {
    final orderId = await orderOf(100);
    final plan = await coordinator.buildSplitPlan(
        orderId: orderId, mode: SplitMode.equal);

    // table_order_payments.invoice_id يتبع sales_invoices، والقيدُ الأجنبي
    // مُفعَّلٌ في اختبارات forTesting() — فتُزرع فاتورةٌ حقيقيةٌ بمعرّفٍ صريح
    // ١١ ليطابق `invoiceId: 11` أدناه (نفسُ نمط table_service_schema_test.dart).
    // المخزنُ والمستخدمُ مبذوران سلفاً في beforeOpen فيُعاد استخدامهما.
    final warehouseId = (await db.select(db.warehouses).get()).first.id;
    final userId = (await db.select(db.users).get()).first.id;
    await db.into(db.salesInvoices).insert(
          SalesInvoicesCompanion.insert(
            id: const Value(11),
            invoiceNumber: 'INV-TEST-11',
            warehouseId: warehouseId,
            userId: userId,
            invoiceDate: DateTime.now(),
          ),
        );

    await coordinator.settlePart(
        orderId: orderId, part: plan.parts.first, invoiceId: 11);

    final payments = await service.paymentsFor(orderId);
    expect(payments, hasLength(1));
    expect(payments.single.amount, 25);
    expect(payments.single.invoiceId, 11);
    expect(payments.single.splitLabel, plan.parts.first.label);
    final order = await (db.select(db.tableOrders)
          ..where((o) => o.id.equals(orderId)))
        .getSingle();
    expect(order.paidAmount, 25);
  });

  test('التقسيمُ بالأصناف يُصدر فواتيرَ منفصلة', () async {
    final orderId = await orderOf(100);

    // table_order_items.product_id يتبع products، والقيدُ الأجنبي مُفعَّلٌ في
    // اختبارات forTesting() — فتُزرع سلعتان حقيقيتان (نفسُ نمط
    // table_service_schema_test.dart). products فارغٌ في قاعدةٍ جديدة فتحمل
    // الأولى id=1 والثانية id=2، فتطابقان `productId: 1` و`productId: 2` أدناه.
    await db.into(db.products).insert(
          ProductsCompanion.insert(code: 'TEST-1', name: 'صنفٌ أوّل'),
        );
    await db.into(db.products).insert(
          ProductsCompanion.insert(code: 'TEST-2', name: 'صنفٌ ثانٍ'),
        );

    await db.into(db.tableOrderItems).insert(
          TableOrderItemsCompanion.insert(
            tableOrderId: orderId,
            productId: 1,
            quantity: 1,
            unitPrice: 60,
            total: 60,
          ),
        );
    await db.into(db.tableOrderItems).insert(
          TableOrderItemsCompanion.insert(
            tableOrderId: orderId,
            productId: 2,
            quantity: 1,
            unitPrice: 40,
            total: 40,
          ),
        );
    final items = await db.getTableOrderItems(orderId);

    final plan = await coordinator.buildSplitPlan(
      orderId: orderId,
      mode: SplitMode.byItems,
      assignment: {items[0].id: 0, items[1].id: 1},
      ways: 2,
    );

    expect(plan.producesSeparateInvoices, isTrue);
    expect(plan.parts[0].amount, 60);
    expect(plan.parts[1].itemQuantities[items[1].id], 1);
  });

  test('التقسيمُ بمبلغ يحترم الخصم ولا يُصدر فواتيرَ منفصلة', () async {
    final orderId = await orderOf(100);
    await service.setOrderDiscount(
        orderId: orderId,
        type: 'percent',
        value: 20,
        userId: null,
        userName: 'أحمد');

    // الإجماليُّ الخام ١٠٠ والمخصومُ ٨٠ — فالمبالغُ هنا تجمع ٨٠ لا ١٠٠،
    // لإثبات أن المنسّق يمرّر الإجماليَّ بعد الخصم لا الخام.
    final plan = await coordinator.buildSplitPlan(
      orderId: orderId,
      mode: SplitMode.byAmounts,
      amounts: [30, 50],
    );

    expect(plan.parts.map((p) => p.amount), [30, 50]);
    expect(plan.producesSeparateInvoices, isFalse);
  });

  test('التقسيمُ بمبلغ يرفض مبالغَ تجمع الإجماليَّ الخامَ لا المخصوم',
      () async {
    final orderId = await orderOf(100);
    await service.setOrderDiscount(
        orderId: orderId,
        type: 'percent',
        value: 20,
        userId: null,
        userName: 'أحمد');

    // مبالغُ تجمع ١٠٠ (الخام) بدل ٨٠ (المخصوم) يجب أن تُرفَض — وإلا مرّ
    // خللٌ يُمرّر `order.total` مكان `effectiveTotal` بصمت.
    await expectLater(
      coordinator.buildSplitPlan(
        orderId: orderId,
        mode: SplitMode.byAmounts,
        amounts: [60, 40],
      ),
      throwsA(isA<SplitPlanException>()),
    );
  });

  Future<void> seedInvoice(int id) async {
    final warehouseId = (await db.select(db.warehouses).get()).first.id;
    final userId = (await db.select(db.users).get()).first.id;
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

  group('unsettledParts', () {
    test('لا شيءَ مسوًّى بعد ⇒ كلُّ الحصص باقية', () async {
      final orderId = await orderOf(100, guests: 4);
      final plan = await coordinator.buildSplitPlan(
          orderId: orderId, mode: SplitMode.equal);

      final unsettled =
          await coordinator.unsettledParts(orderId: orderId, plan: plan);

      expect(unsettled, plan.parts);
    });

    test('حصّتان من أربعٍ سُوِّيتا ⇒ الباقيتان فقط، بترتيبهما', () async {
      final orderId = await orderOf(100, guests: 4);
      final plan = await coordinator.buildSplitPlan(
          orderId: orderId, mode: SplitMode.equal);
      await seedInvoice(21);
      // سُوِّيت الأولى والثالثة عمداً — لإثبات أن الترتيب في النتيجة
      // ترتيبُ الخطّة نفسِها لا ترتيبُ التسوية.
      await coordinator.settlePart(
          orderId: orderId, part: plan.parts[0], invoiceId: 21);
      await coordinator.settlePart(
          orderId: orderId, part: plan.parts[2], invoiceId: 21);

      final unsettled =
          await coordinator.unsettledParts(orderId: orderId, plan: plan);

      expect(unsettled, [plan.parts[1], plan.parts[3]]);
    });

    test('كلُّ الحصص سُوِّيت ⇒ لا شيء يبقى', () async {
      final orderId = await orderOf(100, guests: 2);
      final plan = await coordinator.buildSplitPlan(
          orderId: orderId, mode: SplitMode.equal);
      await seedInvoice(22);
      for (final part in plan.parts) {
        await coordinator.settlePart(
            orderId: orderId, part: part, invoiceId: 22);
      }

      final unsettled =
          await coordinator.unsettledParts(orderId: orderId, plan: plan);

      expect(unsettled, isEmpty);
    });

    test('تغييرُ المقام بعد تسويةٍ جزئيّةٍ يُرفَض', () async {
      final orderId = await orderOf(100, guests: 4);
      final four = await coordinator.buildSplitPlan(
          orderId: orderId, mode: SplitMode.equal);
      await seedInvoice(41);
      await coordinator.settlePart(
          orderId: orderId, part: four.parts.first, invoiceId: 41);

      // نفسُ التسمية «ضيف ١» بمبلغٍ آخر: سُوِّيت ٢٥ والخطّةُ الجديدة تجعلها
      // ٥٠. لو مرّت لعُدَّت مسوّاةً فذهب فرقُها بلا تحصيل.
      final two = await coordinator.buildSplitPlan(
          orderId: orderId, mode: SplitMode.equal, ways: 2);

      await expectLater(
        coordinator.unsettledParts(orderId: orderId, plan: two),
        throwsA(isA<StateError>()),
      );
    });

    test('إعادةُ توزيعٍ بنفس الإجمالي تُرفَض أيضاً', () async {
      final orderId = await orderOf(100, guests: 2);
      final even = await coordinator.buildSplitPlan(
          orderId: orderId, mode: SplitMode.equal);
      await seedInvoice(42);
      await coordinator.settlePart(
          orderId: orderId, part: even.parts.first, invoiceId: 42);

      // ٥٠+٥٠ ⟵ ٧٠+٣٠: الإجماليُّ لم يتغيّر، فحارسُ freshSum/previewSum
      // يمرّ صامتاً. المقارنةُ على مستوى الحصّة وحدَها تكشفها.
      final reshuffled = await coordinator.buildSplitPlan(
        orderId: orderId,
        mode: SplitMode.byAmounts,
        amounts: [70, 30],
      );

      await expectLater(
        coordinator.unsettledParts(orderId: orderId, plan: reshuffled),
        throwsA(isA<StateError>()),
      );
    });

    test('تقسيمٌ لم يتغيّر يمرّ رغم التسوية الجزئيّة', () async {
      final orderId = await orderOf(100, guests: 4);
      final plan = await coordinator.buildSplitPlan(
          orderId: orderId, mode: SplitMode.equal);
      await seedInvoice(43);
      await coordinator.settlePart(
          orderId: orderId, part: plan.parts.first, invoiceId: 43);

      final again = await coordinator.buildSplitPlan(
          orderId: orderId, mode: SplitMode.equal);
      expect(await coordinator.unsettledParts(orderId: orderId, plan: again),
          hasLength(3));
    });

    test('تسمياتٌ متكرّرةٌ في الخطّة تُرفَض لا تُسقَط بصمت', () async {
      final orderId = await orderOf(100, guests: 2);
      final plan = await coordinator.buildSplitPlan(
          orderId: orderId, mode: SplitMode.equal);
      // تلاعبٌ متعمَّدٌ لمحاكاة خطّةٍ فاسدة — مصانعُ `SplitPlan` العامّة لا
      // تُنتج تسمياتٍ متكرّرةً أبداً؛ هذا يثبت أن الحارس يُرفض لا يُسقط بصمت
      // لو حدث ذلك بأيّ طريقٍ أخرى مستقبلاً.
      plan.parts[1] =
          SplitPart(amount: plan.parts[0].amount, label: plan.parts[0].label);

      await expectLater(
        coordinator.unsettledParts(orderId: orderId, plan: plan),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('settledInvoiceId', () {
    test('لا دفعاتٍ بعد ⇒ null', () async {
      final orderId = await orderOf(100);
      expect(await coordinator.settledInvoiceId(orderId), isNull);
    });

    test('بعد تسوية حصّةٍ ⇒ رقمُ فاتورتها', () async {
      final orderId = await orderOf(100);
      final plan = await coordinator.buildSplitPlan(
          orderId: orderId, mode: SplitMode.equal);
      await seedInvoice(33);
      await coordinator.settlePart(
          orderId: orderId, part: plan.parts.first, invoiceId: 33);

      expect(await coordinator.settledInvoiceId(orderId), 33);
    });
  });
}
