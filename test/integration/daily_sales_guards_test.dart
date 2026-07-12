// D-PERF-3 (A10) — getDailySalesSummary omitted the is_deleted and return
// guards that getDailySalesForRange already applies, so soft-deleted and
// return invoices inflated the daily totals. getDailySalesSimple was a
// byte-identical dead duplicate. getDailySalesSummary now delegates to
// getDailySalesForRange (single source of truth, guards included).

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  test('getDailySalesSummary excludes deleted + return invoices (A10)',
      () async {
    final db = AppDatabase.forTesting();
    final now = DateTime.now();
    final wh = (await db.select(db.warehouses).get()).first.id;
    final role = await db.into(db.roles).insert(
        RolesCompanion.insert(name: 'بائع', isSystemRole: const Value(false)));
    final uid = await db.createUser(
        username: 'seller1', password: 'pass123', displayName: 'Seller', roleId: role);

    await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
        invoiceNumber: 'S1',
        invoiceDate: now,
        warehouseId: wh,
        userId: uid,
        total: const Value(100),
        saleType: const Value('sale')));
    await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
        invoiceNumber: 'S2',
        invoiceDate: now,
        warehouseId: wh,
        userId: uid,
        total: const Value(999),
        isDeleted: const Value(true))); // soft-deleted → must be excluded
    await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
        invoiceNumber: 'S3',
        invoiceDate: now,
        warehouseId: wh,
        userId: uid,
        total: const Value(50),
        saleType: const Value('return'))); // return → must be excluded

    final rows = await db.getDailySalesSummary(7);
    final sum = rows.fold<double>(0, (s, r) => s + r.total);
    expect(sum, 100,
        reason: 'only the live, non-return sale should count toward daily total');

    await db.close();
  });
}
