import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/domain/models/split_plan.dart';
import 'package:picpos_erp/domain/models/table_status.dart';
import 'package:picpos_erp/services/split_settlement_runner.dart';
import 'package:picpos_erp/services/table_checkout_coordinator.dart';
import 'package:picpos_erp/services/table_session_service.dart';

void main() {
  late AppDatabase db;
  late TableSessionService service;
  late TableCheckoutCoordinator coordinator;
  int? seedProductId;

  setUp(() {
    db = AppDatabase.forTesting();
    service = TableSessionService(db);
    coordinator = TableCheckoutCoordinator(db: db, session: service);
    seedProductId = null;
  });
  tearDown(() => db.close());

  /// طلبٌ إجماليُّه [total] — ببندٍ حقيقيٍّ لا بكتابةٍ على العمود.
  ///
  /// `total` عمودٌ مشتقٌّ من البنود، والإجماليُّ صار يُحسب منها (لكلِّ بندٍ
  /// نسبةُ ضريبته)، فطلبٌ بلا بندٍ إجماليُّه صفرٌ مهما كُتب في العمود.
  /// `tableOrderItems.productId` مفتاحٌ خارجيٌّ إلى `products`، و
  /// `forTesting()` تُنفِذ القيودَ الخارجية — فيُبذَر صنفٌ مرّةً لكلِّ اختبار.
  Future<int> productForSeed() async =>
      seedProductId ??= await db.into(db.products).insert(
            ProductsCompanion.insert(code: 'SEED-1', name: 'صنفُ البذر'),
          );

  /// طلبٌ مفتوحٌ بلا بنود — لمن يزرع بنودَه بنفسه.
  Future<int> openOrder({int guests = 4}) async {
    final t = await db.createTable(name: 'ط');
    return service.openTable(
        tableId: t, guestCount: guests, userId: null, userName: 'أحمد');
  }

  Future<int> orderOf(double total, {int guests = 4}) async {
    final orderId = await openOrder(guests: guests);
    await db.into(db.tableOrderItems).insert(
          TableOrderItemsCompanion.insert(
            tableOrderId: orderId,
            productId: await productForSeed(),
            quantity: 1,
            unitPrice: total,
            total: total,
          ),
        );
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
    // بلا بندِ البذر: هذا الاختبارُ يزرع بنديه بنفسه، ومجموعُهما ١٠٠.
    final orderId = await openOrder();

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

    test('حصّةٌ مسوّاةٌ غابت عن الخطّة تُرفَض لا تُهمَل', () async {
      final orderId = await orderOf(100, guests: 4);
      final four = await coordinator.buildSplitPlan(
          orderId: orderId, mode: SplitMode.equal);
      await seedInvoice(44);
      await coordinator.settlePart(
          orderId: orderId, part: four.parts[3], invoiceId: 44);

      // ٤ حصصٍ ← ٣: «ضيف ٤» المسوّاةُ لم تعد في الخطّة، فلا تُقارَن بشيء.
      // بلا هذا الحارس تعود الحصصُ الثلاثُ كلُّها «باقية» بمجموع ١٠٠، فتُشحَن
      // أصنافُ الطلب كلُّها في فاتورةٍ ثانيةٍ ويُحصَّل ما حُصِّل.
      final three = await coordinator.buildSplitPlan(
          orderId: orderId, mode: SplitMode.equal, ways: 3);

      await expectLater(
        coordinator.unsettledParts(orderId: orderId, plan: three),
        throwsA(isA<StateError>()),
      );
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

  // ── استئنافُ تقسيمٍ سُوِّي جزئيّاً ثم أُغلقت شاشتُه ─────────────────────
  //
  // الحالةُ التي كان قفلُ التركيبة يجعلها بلا مخرج: `SplitTableDialog` لا
  // يستعيد الإسنادَ ولا المبالغَ عند إعادة الفتح (التركيبةُ لا تُحفَظ مع
  // الدفعات)، وكان يُعطّل القوائمَ والخاناتِ ما دام `paidAmount > 0` — فلا
  // سبيلَ إلى التعبير عن التركيبة التي سُوِّيت عليها الحصص، ولا إلى الإغلاق
  // أو الإلغاء أو التحصيل من أيّ بابٍ آخر. الأمانُ كان — ولا يزال — في
  // `unsettledParts` وحدَه، والاختباران التاليان يُثبتان الطرفين معاً.
  group('استئنافُ تقسيمٍ بالأصناف سُوِّي جزئيّاً', () {
    /// طلبٌ ببندَين: ٦٠ + ٤٠ = ١٠٠، بمعرّفاتِ بنودٍ حقيقيّةٍ لأن ما يجب
    /// إعادةُ إدخاله هو الإسنادُ `itemId → دافع` نفسُه.
    Future<TableOrder> orderWithTwoItems() async {
      final t = await db.createTable(name: 'ط-استئناف');
      final orderId = await service.openTable(
          tableId: t, guestCount: 2, userId: null, userName: 'أحمد');
      final productA = await db.into(db.products).insert(
          ProductsCompanion.insert(code: 'SPL-A', name: 'صنفُ الستّين'));
      final productB = await db.into(db.products).insert(
          ProductsCompanion.insert(code: 'SPL-B', name: 'صنفُ الأربعين'));
      await db.addOrUpdateTableOrderItem(
          orderId: orderId, productId: productA, quantity: 1, unitPrice: 60);
      await db.addOrUpdateTableOrderItem(
          orderId: orderId, productId: productB, quantity: 1, unitPrice: 40);
      return (db.select(db.tableOrders)..where((o) => o.id.equals(orderId)))
          .getSingle();
    }

    Future<double> paidOf(int orderId) async =>
        (await (db.select(db.tableOrders)..where((o) => o.id.equals(orderId)))
                .getSingle())
            .paidAmount;

    Future<String> statusOf(int tableId) async =>
        (await (db.select(db.restaurantTables)
                  ..where((t) => t.id.equals(tableId)))
                .getSingle())
            .status;

    test('إلغاءُ الدفع عند الضيف الثاني ثم إعادةُ نفسِ الإسناد تُكمل التحصيل',
        () async {
      final order = await orderWithTwoItems();
      final items = await db.getTableOrderItems(order.id);
      final assignment = {items[0].id: 0, items[1].id: 1};

      Future<SplitPlan> planOf(Map<int, int> a) => coordinator.buildSplitPlan(
            orderId: order.id,
            mode: SplitMode.byItems,
            ways: 2,
            assignment: a,
          );

      // ── الجولةُ الأولى: ضيف١ يدفع ٦٠، والكاشيرُ يُلغي ورقةَ دفع ضيف٢.
      //    هذا هو المسارُ العاديُّ لا حالةً حدّيّة.
      await seedInvoice(701);
      final first = _FakeSplitPort(
        db: db,
        coordinator: coordinator,
        orderId: order.id,
        plan: await planOf(assignment),
        payer: (charge) async => charge == 60 ? 701 : null,
      );
      final round1 = await SplitSettlementRunner(first).run(previewSum: 100);

      expect(round1.status, SplitRunStatus.aborted);
      expect(round1.settledCount, 1);
      expect(await paidOf(order.id), 60);
      expect(await statusOf(order.tableId), TableStatus.occupied,
          reason: 'الطاولةُ عالقةٌ بين «دُفع منها شيء» و«ليست مدفوعةً بالكامل»');

      // ── الشاشةُ أُغلقت فضاع الإسناد. الكاشيرُ يُعيد إدخالَه كما كان —
      //    وهو ما كان القفلُ يمنعه.
      await seedInvoice(702);
      final second = _FakeSplitPort(
        db: db,
        coordinator: coordinator,
        orderId: order.id,
        plan: await planOf(assignment),
        payer: (_) async => 702,
      );
      final round2 = await SplitSettlementRunner(second).run(previewSum: 100);

      expect(round2.status, SplitRunStatus.success);
      expect(second.unsettledSeen.map((p) => p.label).toList(),
          [splitPartLabel(1)],
          reason: 'الحصّةُ الباقيةُ وحدَها — لا إعادةَ تحصيلٍ لضيف١');
      expect(second.unsettledSeen.single.amount, 40);
      expect(second.charges, [40], reason: 'لم يُشحَن إلا الباقي');

      expect(await paidOf(order.id), 100);
      expect(await statusOf(order.tableId), TableStatus.paid,
          reason: 'الطاولةُ خرجت من العلوق وصارت قابلةً للإغلاق');
    });

    test('إسنادٌ مقلوبٌ بنفس الإجمالي يُرفَض قبل إصدار أيّ فاتورة', () async {
      final order = await orderWithTwoItems();
      final items = await db.getTableOrderItems(order.id);

      await seedInvoice(711);
      final first = _FakeSplitPort(
        db: db,
        coordinator: coordinator,
        orderId: order.id,
        plan: await coordinator.buildSplitPlan(
          orderId: order.id,
          mode: SplitMode.byItems,
          ways: 2,
          assignment: {items[0].id: 0, items[1].id: 1},
        ),
        payer: (charge) async => charge == 60 ? 711 : null,
      );
      await SplitSettlementRunner(first).run(previewSum: 100);
      expect(await paidOf(order.id), 60);

      // البندان تبادلا صاحبَيهما: «ضيف ١» صارت ٤٠ وقد سُوِّيت ٦٠. الإجماليُّ
      // ١٠٠ كما هو فحارسُ freshSum/previewSum يمرّ صامتاً — وهذا بالضبط ما
      // يمسكه فحصُ المبلغ لكلّ تسميةٍ على حدة.
      final swapped = await coordinator.buildSplitPlan(
        orderId: order.id,
        mode: SplitMode.byItems,
        ways: 2,
        assignment: {items[0].id: 1, items[1].id: 0},
      );
      final second = _FakeSplitPort(
        db: db,
        coordinator: coordinator,
        orderId: order.id,
        plan: swapped,
        payer: (_) async => 712,
      );

      await expectLater(
        SplitSettlementRunner(second).run(previewSum: 100),
        throwsA(isA<StateError>()),
      );
      expect(second.charges, isEmpty,
          reason: 'الرفضُ قبل الترحيل — لا فاتورةَ يتيمة');
      expect(await paidOf(order.id), 60,
          reason: 'لم يُسجَّل شيءٌ فوق ما سُوِّي');
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

/// منفذُ تسويةٍ يقود [SplitSettlementRunner] بمنسّقٍ **حقيقيّ** على قاعدةٍ
/// حقيقيّة — الوهميُّ فيه شيئان فقط: السلّةُ وورقةُ الدفع.
///
/// [fillCart] يحسب ما تحسبه السلّةُ الحقيقيّة (مجموعُ الكميّة × سعرِ الوحدة
/// للبنود المطلوبة) لا رقماً مُلفَّقاً، وإلّا لما اختُبر الفحصُ القبليُّ
/// أصلاً. و[payer] يقرّر: رقمُ فاتورةٍ صدرت، أو `null` = تراجَع الكاشير.
class _FakeSplitPort implements SplitSettlementPort {
  _FakeSplitPort({
    required this.db,
    required this.coordinator,
    required this.orderId,
    required this.plan,
    required this.payer,
  });

  final AppDatabase db;
  final TableCheckoutCoordinator coordinator;
  final int orderId;
  final SplitPlan plan;
  final Future<int?> Function(double chargeTotal) payer;

  /// آخرُ ما أعادته [unsettledParts] — الدليلُ على أن الاستئنافَ استئنافٌ.
  final List<SplitPart> unsettledSeen = [];

  /// كلُّ مبلغٍ طُلب ترحيلُه. فراغُها = لم تصدر فاتورة.
  final List<double> charges = [];

  @override
  Future<SplitPlan> buildPlan() async => plan;

  @override
  Future<List<SplitPart>> unsettledParts(SplitPlan p) async {
    final parts = await coordinator.unsettledParts(orderId: orderId, plan: p);
    unsettledSeen
      ..clear()
      ..addAll(parts);
    return parts;
  }

  @override
  Future<int?> settledInvoiceId() => coordinator.settledInvoiceId(orderId);

  @override
  Future<int> reservePart(SplitPart part) =>
      coordinator.reservePart(orderId: orderId, part: part);

  @override
  Future<void> confirmPart(int reservationId, int invoiceId) => coordinator
      .confirmPart(reservationId: reservationId, invoiceId: invoiceId);

  @override
  Future<void> releaseReservations(List<int> reservationIds) =>
      coordinator.releaseReservations(reservationIds);

  @override
  Future<double> fillCart(Map<int, double>? itemQuantities) async {
    var total = 0.0;
    for (final item in await db.getTableOrderItems(orderId)) {
      if (itemQuantities != null && !itemQuantities.containsKey(item.id)) {
        continue;
      }
      total += (itemQuantities?[item.id] ?? item.quantity) * item.unitPrice;
    }
    return total;
  }

  @override
  Future<int?> payFilledCart(double chargeTotal) {
    charges.add(chargeTotal);
    return payer(chargeTotal);
  }

  @override
  void onPartSettled(SplitPart part) {}
}
