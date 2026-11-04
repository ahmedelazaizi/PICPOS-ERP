// R1 / T1 — إعادة محاولة failed_autoposts: فاتورة مثبَّتة بلا قيد ⇒ بعد المعاد
// يوجد القيد والصف محلول، والاستدعاء الثاني لا يكرر، والفشل المستمر يعدّ ولا يرمي.
import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int warehouseId;
  late int userId;

  setUp(() async {
    // الإقلاع يجدول المرحلة المؤجلة (وفيها المُعيد نفسه) في الاختبارات أيضاً؛
    // ننتظر انتهاءها كي لا تتداخل مع الاستدعاءات الصريحة أدناه.
    final deferredDone = Completer<void>();
    final originalDebugPrint = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) {
      if (m != null &&
          m.contains('Deferred phase 6 complete') &&
          !deferredDone.isCompleted) {
        deferredDone.complete();
      }
    };
    db = AppDatabase.forTesting();
    await db.customSelect('SELECT 1').get();
    await deferredDone.future.timeout(const Duration(seconds: 60));
    debugPrint = originalDebugPrint;
    warehouseId = await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(name: 'مخزن'),
        );
    userId = await db.into(db.users).insert(
          UsersCompanion.insert(
              username: 'cashier1', passwordHash: 'x', displayName: 'كاشير'),
        );
  });

  tearDown(() => db.close());

  Future<int> insertInvoice({required String saleType}) =>
      db.into(db.salesInvoices).insert(
            SalesInvoicesCompanion.insert(
              invoiceNumber: 'INV-$saleType',
              warehouseId: warehouseId,
              userId: userId,
              invoiceDate: DateTime(2026, 8, 4),
              subtotal: const Value(100),
              total: const Value(100),
              paid: const Value(100),
              cashPaid: const Value(100),
              paymentMethod: const Value('cash'),
              saleType: Value(saleType),
            ),
          );

  Future<int> logFailure(int invoiceId, String type) =>
      db.into(db.failedAutoposts).insert(FailedAutopostsCompanion.insert(
            invoiceId: invoiceId,
            referenceType: type,
            errorMessage: 'simulated failure',
          ));

  Future<int> jeCount(String type, int refId) async => (await (db
              .select(db.journalEntries)
            ..where(
                (e) => e.referenceType.equals(type) & e.referenceId.equals(refId)))
          .get())
      .length;

  test('بيع: يُنشأ القيد ويُعلَّم الصف محلولاً، والاستدعاء الثاني لا يكرر',
      () async {
    final id = await insertInvoice(saleType: 'default');
    final rowId = await logFailure(id, 'sale');
    expect(await jeCount('sale', id), 0);

    final r1 = await db.retryFailedAutoposts();
    expect(r1.resolved, 1);
    expect(await jeCount('sale', id), 1);
    final row = await (db.select(db.failedAutoposts)
          ..where((f) => f.id.equals(rowId)))
        .getSingle();
    expect(row.isResolved, isTrue);
    expect(row.resolvedAt, isNotNull);

    final r2 = await db.retryFailedAutoposts();
    expect(r2.resolved, 0);
    expect(await jeCount('sale', id), 1);
  });

  test('قيد موجود مسبقاً: لا تكرار ويُحلّ الصف', () async {
    final id = await insertInvoice(saleType: 'default');
    final sale = await (db.select(db.salesInvoices)
          ..where((i) => i.id.equals(id)))
        .getSingle();
    await db.autoPostCashSale(sale);
    final rowId = await logFailure(id, 'sale');

    await db.retryFailedAutoposts();

    expect(await jeCount('sale', id), 1);
    final row = await (db.select(db.failedAutoposts)
          ..where((f) => f.id.equals(rowId)))
        .getSingle();
    expect(row.isResolved, isTrue);
  });

  test('مرتجع بيع سريع: يُنشأ قيد sales_return مرة واحدة', () async {
    final id = await insertInvoice(saleType: 'return');
    await logFailure(id, 'sales_return');

    final r1 = await db.retryFailedAutoposts();
    expect(r1.resolved, 1);
    expect(await jeCount('sales_return', id), 1);

    await db.retryFailedAutoposts();
    expect(await jeCount('sales_return', id), 1);
  });

  test('فشل مستمر: يزيد العدّاد ولا يرمي، ويتوقف عند السقف', () async {
    final rowId = await logFailure(1, 'unsupported_type');

    for (var i = 1; i <= 3; i++) {
      final r = await db.retryFailedAutoposts();
      expect(r.failed, 1);
      final row = await (db.select(db.failedAutoposts)
            ..where((f) => f.id.equals(rowId)))
          .getSingle();
      expect(row.isResolved, isFalse);
      expect(row.errorMessage, startsWith('[attempts=$i] '));
      expect(row.errorMessage, contains('unsupported_type'));
    }

    final capped = await db.retryFailedAutoposts(maxAttempts: 3);
    expect(capped.failed, 0);
    expect(capped.skippedAtCap, 1);
  });
}
