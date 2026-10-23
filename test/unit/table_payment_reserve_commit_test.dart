import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/table_session_service.dart';

/// حجزٌ ثم تثبيت — إغلاقُ نافذة «الترحيلُ قبل التسجيل».
///
/// `processPayment` يُرحّل الفاتورة (قيوداً ومخزوناً وخزنة) **قبل** أن تعمل
/// حراسُ `recordPayment`. فإن رمى الحارس، بقيت الفاتورةُ مُرحَّلةً بلا صفِّ
/// دفعٍ ولا `paidAmount` محدَّث: الدفاترُ تقول «بِيعَ» والطاولةُ تقول «لم
/// يُدفَع». والحراسُ لا ترمي إلّا لتغيّرٍ متزامنٍ في أثناء النافذة — سباقُ
/// TOCTOU لا خطأَ حساب.
///
/// العلاجُ أن تعمل كلُّ الحراس **قبل** أيِّ ترحيل، في معاملةٍ واحدةٍ تحجز
/// المبلغ. وبعد الترحيل لا يبقى إلّا كتابةُ رقم الفاتورة — خطوةٌ لا تردّها
/// قاعدةُ عمل.
void main() {
  late AppDatabase db;
  late TableSessionService service;

  setUp(() {
    db = AppDatabase.forTesting();
    service = TableSessionService(db);
  });
  tearDown(() => db.close());

  Future<int> seedProduct() => db.into(db.products).insert(
        ProductsCompanion.insert(code: 'RSV-1', name: 'مشويّ'),
      );

  /// طلبٌ مفتوحٌ بإجماليٍّ معلوم: صنفٌ واحدٌ بسعرٍ محدَّد.
  Future<int> openOrderWorth(double amount, {String table = 'ط'}) async {
    final tableId = await db.createTable(name: table);
    final orderId = await service.openTable(
      tableId: tableId,
      guestCount: 2,
      userId: null,
      userName: 'أحمد',
    );
    await db.addOrUpdateTableOrderItem(
      orderId: orderId,
      productId: await seedProduct(),
      quantity: 1,
      unitPrice: amount,
      taxRate: 0,
    );
    return orderId;
  }

  Future<TableOrder> orderRow(int id) =>
      (db.select(db.tableOrders)..where((o) => o.id.equals(id))).getSingle();

  /// فاتورةٌ حقيقيّة — `tableOrderPayments.invoiceId` مفتاحٌ خارجيٌّ مُنفَذ،
  /// فرقمٌ مخترَعٌ يُرفض بحقّ.
  Future<int> seedInvoice(String number) async {
    final warehouseId = await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(name: 'م-$number'),
        );
    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(name: 'دور-$number'),
        );
    final userId = await db.createUser(
      username: 'u-$number',
      password: 'pw',
      displayName: 'مستخدم',
      roleId: roleId,
    );
    return db.into(db.salesInvoices).insert(
          SalesInvoicesCompanion.insert(
            invoiceNumber: number,
            warehouseId: warehouseId,
            userId: userId,
            invoiceDate: DateTime.now(),
          ),
        );
  }

  Future<int> paymentRowCount() async =>
      (await db.select(db.tableOrderPayments).get()).length;

  // ═══════════════════════════════════════════════════════════════════════
  group('الحجزُ يُجري كلَّ الحراس قبل أن يُرحَّل شيء', () {
    test('الحجزُ يرفع المدفوعَ ويُدرج صفّاً معلّقاً بلا رقم فاتورة', () async {
      final orderId = await openOrderWorth(100);

      final reservationId = await service.reservePayment(
        orderId: orderId,
        amount: 100,
        userId: null,
        userName: 'أحمد',
      );

      expect(reservationId, greaterThan(0));
      final row = await (db.select(db.tableOrderPayments)
            ..where((p) => p.id.equals(reservationId)))
          .getSingle();
      expect(row.invoiceId, isNull, reason: 'الحجزُ لا فاتورةَ له بعد');
      expect(row.status, 'pending');
      expect(row.amount, 100);
      expect((await orderRow(orderId)).paidAmount, 100);
    });

    test('الحجزُ يرفض ما يتجاوز المستحقَّ — قبل الترحيل لا بعده', () async {
      final orderId = await openOrderWorth(100);
      await expectLater(
        service.reservePayment(
            orderId: orderId, amount: 150, userId: null, userName: 'أحمد'),
        throwsA(isA<TableTransitionException>()),
      );
      expect(await paymentRowCount(), 0);
      expect((await orderRow(orderId)).paidAmount, 0);
    });

    test('الحجزُ يرفض المبلغَ غيرَ الموجب', () async {
      final orderId = await openOrderWorth(100);
      await expectLater(
        service.reservePayment(
            orderId: orderId, amount: 0, userId: null, userName: 'أحمد'),
        throwsA(isA<TableTransitionException>()),
      );
    });

    test('لا حجزَ ثانٍ على طلبٍ له حجزٌ معلّق — كي لا يتراكم', () async {
      final orderId = await openOrderWorth(100);
      await service.reservePayment(
          orderId: orderId, amount: 40, userId: null, userName: 'أحمد');
      await expectLater(
        service.reservePayment(
            orderId: orderId, amount: 30, userId: null, userName: 'أحمد'),
        throwsA(isA<TableTransitionException>()),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  group('التثبيتُ لا تردُّه قاعدةُ عمل', () {
    test('التثبيتُ يكتب رقمَ الفاتورة ويقلب الحالة', () async {
      final orderId = await openOrderWorth(100);
      final reservationId = await service.reservePayment(
          orderId: orderId, amount: 100, userId: null, userName: 'أحمد');

      final invoiceId = await seedInvoice('INV-77');
      await service.confirmPayment(
          reservationId: reservationId, invoiceId: invoiceId);

      final row = await (db.select(db.tableOrderPayments)
            ..where((p) => p.id.equals(reservationId)))
          .getSingle();
      expect(row.invoiceId, invoiceId);
      expect(row.status, 'settled');
      // المالُ كان مسجَّلاً منذ الحجز — التثبيتُ لا يُحرّكه.
      expect((await orderRow(orderId)).paidAmount, 100);
    });

    test('الطاولةُ تصير مدفوعةً حين يبلغ المحجوزُ الإجماليَّ', () async {
      final orderId = await openOrderWorth(100);
      final order = await orderRow(orderId);
      await service.reservePayment(
          orderId: orderId, amount: 100, userId: null, userName: 'أحمد');
      final table = await (db.select(db.restaurantTables)
            ..where((t) => t.id.equals(order.tableId)))
          .getSingle();
      expect(table.status, 'paid');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  group('التحريرُ يردّ الحالةَ كما كانت', () {
    test('تحريرُ الحجز يُسقط الصفَّ ويردّ المدفوع', () async {
      final orderId = await openOrderWorth(100);
      final reservationId = await service.reservePayment(
          orderId: orderId, amount: 100, userId: null, userName: 'أحمد');

      await service.releaseReservation(
        reservationId: reservationId,
        reason: 'فشلَ الترحيل',
        userId: null,
        userName: 'أحمد',
      );

      expect(await paymentRowCount(), 0);
      expect((await orderRow(orderId)).paidAmount, 0);
    });

    test('التحريرُ يُعيد الطاولةَ من «مدفوعة» إلى مشغولة', () async {
      final orderId = await openOrderWorth(100);
      final order = await orderRow(orderId);
      final reservationId = await service.reservePayment(
          orderId: orderId, amount: 100, userId: null, userName: 'أحمد');
      await service.releaseReservation(
          reservationId: reservationId,
          reason: 'تراجُع',
          userId: null,
          userName: 'أحمد');

      final table = await (db.select(db.restaurantTables)
            ..where((t) => t.id.equals(order.tableId)))
          .getSingle();
      expect(table.status, isNot('paid'));
    });

    test('التحريرُ يُتيح حجزاً جديداً — الطلبُ لا يبقى مقفلاً', () async {
      final orderId = await openOrderWorth(100);
      final first = await service.reservePayment(
          orderId: orderId, amount: 100, userId: null, userName: 'أحمد');
      await service.releaseReservation(
          reservationId: first,
          reason: 'تراجُع',
          userId: null,
          userName: 'أحمد');
      final second = await service.reservePayment(
          orderId: orderId, amount: 100, userId: null, userName: 'أحمد');
      expect(second, greaterThan(0));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  group('`recordPayment` أُعيد بناؤه فوقهما ولم يتغيّر سلوكُه', () {
    test('يُدرج صفّاً مثبَّتاً برقم فاتورةٍ ويرفع المدفوع', () async {
      final orderId = await openOrderWorth(100);
      final invoiceId = await seedInvoice('INV-99');
      await service.recordPayment(
        orderId: orderId,
        invoiceId: invoiceId,
        amount: 100,
        userId: null,
        userName: 'أحمد',
      );
      final row = (await db.select(db.tableOrderPayments).get()).single;
      expect(row.invoiceId, invoiceId);
      expect(row.status, 'settled');
      expect((await orderRow(orderId)).paidAmount, 100);
    });

    test('ما زال يرفض التجاوز', () async {
      final orderId = await openOrderWorth(100);
      await expectLater(
        service.recordPayment(
            orderId: orderId,
            invoiceId: await seedInvoice('INV-OVER'),
            amount: 150,
            userName: 'أحمد'),
        throwsA(isA<TableTransitionException>()),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  group('نصفُ الحالة مستحيلُ التمثيل', () {
    test('مثبَّتٌ بلا فاتورةٍ يُرفض في الجدول نفسِه', () async {
      final orderId = await openOrderWorth(100);
      await expectLater(
        db.into(db.tableOrderPayments).insert(
              TableOrderPaymentsCompanion.insert(
                tableOrderId: orderId,
                amount: 10,
                status: const Value('settled'),
              ),
            ),
        throwsA(predicate((e) =>
            e.toString().toLowerCase().contains('check constraint failed'))),
      );
    });

    test('محجوزٌ ومعه فاتورةٌ يُرفض كذلك', () async {
      final orderId = await openOrderWorth(100);
      await expectLater(
        db.into(db.tableOrderPayments).insert(
              TableOrderPaymentsCompanion.insert(
                tableOrderId: orderId,
                amount: 10,
                invoiceId: const Value(5),
                status: const Value('pending'),
              ),
            ),
        throwsA(predicate((e) =>
            e.toString().toLowerCase().contains('check constraint failed'))),
      );
    });
  });
}
