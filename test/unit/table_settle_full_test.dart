import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/table_checkout_coordinator.dart';
import 'package:ural_erp/services/table_session_service.dart';

/// حلقةُ التحصيل: حجزٌ → ترحيلٌ → تثبيت.
///
/// كانت تعيش في `_checkoutTable` داخل ودجت، فلم يكن لها اختبارٌ واحد —
/// وشاشاتُ هذا المستودع لا تُركَّب في اختبارات الويدجت (‏`db.close()` ينتظر
/// مؤقّت drift في المنطقة الوهميّة). نُقلت إلى المنسّق ليُقاد بلا واجهة:
/// الترحيلُ يُمرَّر دالّةً، فيُقاد بدالّةٍ وهميّةٍ تنجح أو تفشل أو تتراجع.
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

  Future<int> seedInvoice(String number) async {
    final warehouseId = await db
        .into(db.warehouses)
        .insert(WarehousesCompanion.insert(name: 'م-$number'));
    final roleId =
        await db.into(db.roles).insert(RolesCompanion.insert(name: 'د-$number'));
    final userId = await db.createUser(
        username: 'u-$number',
        password: 'pw',
        displayName: 'م',
        roleId: roleId);
    return db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
          invoiceNumber: number,
          warehouseId: warehouseId,
          userId: userId,
          invoiceDate: DateTime.now(),
        ));
  }

  Future<int> openOrderWorth(double amount) async {
    final tableId = await db.createTable(name: 'ط');
    final orderId = await session.openTable(
        tableId: tableId, guestCount: 2, userId: null, userName: 'أحمد');
    final productId = await db
        .into(db.products)
        .insert(ProductsCompanion.insert(code: 'S-1', name: 'مشويّ'));
    await db.addOrUpdateTableOrderItem(
      orderId: orderId,
      productId: productId,
      quantity: 1,
      unitPrice: amount,
      taxRate: 0,
    );
    return orderId;
  }

  Future<TableOrder> orderRow(int id) =>
      (db.select(db.tableOrders)..where((o) => o.id.equals(id))).getSingle();

  Future<int> paymentCount() async =>
      (await db.select(db.tableOrderPayments).get()).length;

  test('المسارُ السعيد: الفاتورةُ تُرحَّل بين الحجز والتثبيت', () async {
    final orderId = await openOrderWorth(100);
    var postedWhilePaidWas = -1.0;

    final outcome = await coordinator.settleFull(
      orderId: orderId,
      amount: 100,
      postInvoice: () async {
        // لحظةَ الترحيل يكون المبلغُ محجوزاً بالفعل — وهذا هو الفرق كلُّه:
        // الحراسُ عملت قبل أن يُرحَّل شيء.
        postedWhilePaidWas = (await orderRow(orderId)).paidAmount;
        return seedInvoice('INV-OK');
      },
      userName: 'أحمد',
    );

    expect(outcome.status, TableSettleStatus.success);
    expect(postedWhilePaidWas, 100);
    final row = (await db.select(db.tableOrderPayments).get()).single;
    expect(row.status, 'settled');
    expect(row.invoiceId, isNotNull);
  });

  test('حارسٌ يرفض ⇒ لا تُنادى دالّةُ الترحيل أصلاً', () async {
    final orderId = await openOrderWorth(100);
    var posted = false;

    final outcome = await coordinator.settleFull(
      orderId: orderId,
      amount: 150, // يتجاوز المستحقّ
      postInvoice: () async {
        posted = true;
        return seedInvoice('INV-NEVER');
      },
      userName: 'أحمد',
    );

    expect(outcome.status, TableSettleStatus.rejected);
    expect(posted, isFalse, reason: 'النافذةُ مغلقة: لا فاتورةَ صدرت');
    expect(await paymentCount(), 0);
    expect((await orderRow(orderId)).paidAmount, 0);
  });

  test('الترحيلُ يتراجع ⇒ الحجزُ يُحرَّر ولا أثرَ يبقى', () async {
    final orderId = await openOrderWorth(100);

    final outcome = await coordinator.settleFull(
      orderId: orderId,
      amount: 100,
      postInvoice: () async => null, // الكاشيرُ أغلق ورقةَ الدفع
      userName: 'أحمد',
    );

    expect(outcome.status, TableSettleStatus.aborted);
    expect(await paymentCount(), 0);
    expect((await orderRow(orderId)).paidAmount, 0);
  });

  test('الترحيلُ يرمي ⇒ الحجزُ يُحرَّر كذلك', () async {
    final orderId = await openOrderWorth(100);

    final outcome = await coordinator.settleFull(
      orderId: orderId,
      amount: 100,
      postInvoice: () async => throw StateError('انقطع الاتصال'),
      userName: 'أحمد',
    );

    expect(outcome.status, TableSettleStatus.aborted);
    expect(await paymentCount(), 0);
    expect((await orderRow(orderId)).paidAmount, 0);
  });

  test('فشلُ التثبيت ⇒ المالُ مسجَّلٌ والرابطُ وحدَه ناقص', () async {
    final orderId = await openOrderWorth(100);

    final outcome = await coordinator.settleFull(
      orderId: orderId,
      amount: 100,
      // رقمُ فاتورةٍ لا وجودَ له: التثبيتُ يفشل على المفتاح الخارجيّ.
      postInvoice: () async => 999999,
      userName: 'أحمد',
    );

    expect(outcome.status, TableSettleStatus.reconcileNeeded);
    expect(outcome.invoiceId, 999999);
    // وهذا أفضلُ ممّا كان: الطاولةُ تحمل المالَ بمبلغه الصحيح، والناقصُ
    // رابطُ الفاتورة — إصلاحُه `UPDATE` واحد، لا فاتورةٌ يتيمةٌ وطاولةٌ صفر.
    expect((await orderRow(orderId)).paidAmount, 100);
    final row = (await db.select(db.tableOrderPayments).get()).single;
    expect(row.status, 'pending');
    expect(row.amount, 100);
  });
}
