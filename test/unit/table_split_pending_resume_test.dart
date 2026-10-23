import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/domain/models/split_plan.dart';
import 'package:picpos_erp/services/table_checkout_coordinator.dart';
import 'package:picpos_erp/services/table_session_service.dart';

/// فخُّ الاستئناف — الحصّةُ صارت ثلاثَ حالاتٍ لا اثنتين.
///
/// قبل v158 كانت الحصّةُ إمّا مسوّاةً أو باقية. والآن بينهما حالةٌ ثالثة:
/// **محجوزةٌ تنتظر رقمَ فاتورة**. و`settledShares` يقرأ `paymentsFor` الذي
/// يُرشِّح `settled` — فالمحجوزةُ لا تظهر فيه.
///
/// فلو عوملت المحجوزةُ معاملةَ «باقية» لَحُجزت ثانيةً فتضاعف `paidAmount`؛
/// ولو عوملت معاملةَ «مسوّاة» لَبقي رابطُ فاتورتها فارغاً للأبد.
///
/// وصفٌّ معلّقٌ يعني — بحكم ترتيب [TableCheckoutCoordinator.settleFull] —
/// أن الفاتورةَ **رُحّلت** وفشل ربطُها وحدَه (فشلُ الترحيل يُحرِّر الحجز).
/// فلا يُخمَّن: يُرفَض الاستئنافُ صراحةً حتى يحسمه إنسان.
void main() {
  late AppDatabase db;
  late TableSessionService session;
  late TableCheckoutCoordinator coordinator;

  setUp(() {
    db = AppDatabase.forTesting();
    session = TableSessionService(db);
    coordinator = TableCheckoutCoordinator(db: db, session: session);
  });
  tearDown(() => db.close());

  Future<int> openOrderWorth(double amount) async {
    final tableId = await db.createTable(name: 'ط');
    final orderId = await session.openTable(
        tableId: tableId, guestCount: 2, userId: null, userName: 'أحمد');
    final productId = await db
        .into(db.products)
        .insert(ProductsCompanion.insert(code: 'SP-1', name: 'مشويّ'));
    await db.addOrUpdateTableOrderItem(
      orderId: orderId,
      productId: productId,
      quantity: 1,
      unitPrice: amount,
      taxRate: 0,
    );
    return orderId;
  }

  test('حصّةٌ محجوزةٌ لا تُعَدّ باقيةً — وإلّا حُجزت ثانيةً', () async {
    final orderId = await openOrderWorth(100);
    final plan = await coordinator.buildSplitPlan(
        orderId: orderId, mode: SplitMode.equal, ways: 2);

    // حصّةٌ حُجزت ولم تُثبَّت — الفاتورةُ رُحّلت وفشل الربط.
    await session.reservePayment(
      orderId: orderId,
      amount: plan.parts.first.amount,
      splitLabel: plan.parts.first.label,
      userName: 'أحمد',
    );

    // الاستئنافُ لا يجوز أن يعيدها في «الباقية».
    await expectLater(
      coordinator.unsettledParts(orderId: orderId, plan: plan),
      throwsA(isA<StateError>()),
    );
  });

  test('الرفضُ يُسمّي الحجزَ ومبلغَه — لا رسالةً عامّة', () async {
    final orderId = await openOrderWorth(100);
    final plan = await coordinator.buildSplitPlan(
        orderId: orderId, mode: SplitMode.equal, ways: 2);
    final reservationId = await session.reservePayment(
      orderId: orderId,
      amount: plan.parts.first.amount,
      splitLabel: plan.parts.first.label,
      userName: 'أحمد',
    );

    try {
      await coordinator.unsettledParts(orderId: orderId, plan: plan);
      fail('كان يجب أن يُرفض');
    } on StateError catch (e) {
      expect(e.message, contains('$reservationId'));
      expect(e.message, contains(plan.parts.first.label));
    }
  });

  test('بلا حجزٍ معلّقٍ يعمل الاستئنافُ كما كان', () async {
    final orderId = await openOrderWorth(100);
    final plan = await coordinator.buildSplitPlan(
        orderId: orderId, mode: SplitMode.equal, ways: 2);

    final remaining =
        await coordinator.unsettledParts(orderId: orderId, plan: plan);
    expect(remaining, hasLength(2));
  });

  test('تحريرُ الحجز يُعيد الاستئنافَ إلى العمل', () async {
    final orderId = await openOrderWorth(100);
    final plan = await coordinator.buildSplitPlan(
        orderId: orderId, mode: SplitMode.equal, ways: 2);
    final reservationId = await session.reservePayment(
      orderId: orderId,
      amount: plan.parts.first.amount,
      splitLabel: plan.parts.first.label,
      userName: 'أحمد',
    );

    await session.releaseReservation(
        reservationId: reservationId, reason: 'حُسمت يدويّاً', userName: 'أحمد');

    final remaining =
        await coordinator.unsettledParts(orderId: orderId, plan: plan);
    expect(remaining, hasLength(2));
  });

  test('حصّةٌ ثُبِّتت تُعَدّ مسوّاةً ولا تُحجَز ثانية', () async {
    final orderId = await openOrderWorth(100);
    final plan = await coordinator.buildSplitPlan(
        orderId: orderId, mode: SplitMode.equal, ways: 2);

    final warehouseId = await db
        .into(db.warehouses)
        .insert(WarehousesCompanion.insert(name: 'م'));
    final roleId =
        await db.into(db.roles).insert(RolesCompanion.insert(name: 'د'));
    final userId = await db.createUser(
        username: 'usr', password: 'pw', displayName: 'م', roleId: roleId);
    final invoiceId =
        await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
              invoiceNumber: 'INV-SP',
              warehouseId: warehouseId,
              userId: userId,
              invoiceDate: DateTime.now(),
            ));

    final reservationId = await session.reservePayment(
      orderId: orderId,
      amount: plan.parts.first.amount,
      splitLabel: plan.parts.first.label,
      userName: 'أحمد',
    );
    await session.confirmPayment(
        reservationId: reservationId, invoiceId: invoiceId);

    final remaining =
        await coordinator.unsettledParts(orderId: orderId, plan: plan);
    expect(remaining, hasLength(1));
    expect(remaining.single.label, plan.parts[1].label);
  });
}
