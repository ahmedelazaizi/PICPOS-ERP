/// Day-19 Integration Tests — watchSalesInvoices() date-range filter
///
/// Verifies that the new [from] / [to] parameters correctly narrow the
/// stream to invoices whose `invoice_date` falls within the requested
/// window, and that omitting the parameters leaves the stream unfiltered.
library;

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int userId;
  late int warehouseId;

  setUp(() async {
    db = AppDatabase.forTesting();

    final roleId = await db.into(db.roles).insert(
      RolesCompanion.insert(name: 'cashier', isSystemRole: const Value(false)),
    );
    userId = await db.createUser(
      username: 'cashier1',
      password: 'pw',
      displayName: 'Cashier 1',
      roleId: roleId,
    );
    warehouseId = await db.into(db.warehouses).insert(
      WarehousesCompanion.insert(
        name: 'Main',
        isActive: const Value(true),
        isDefault: const Value(true),
      ),
    );
  });

  tearDown(() async => db.close());

  // ─────────────────────────────────────────────────────────────────────────
  // Helper: insert an invoice for a specific date
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> insertInvoice(DateTime date, {String suffix = ''}) async {
    await db.into(db.salesInvoices).insert(
      SalesInvoicesCompanion.insert(
        invoiceNumber: 'TEST-${date.month}-${date.day}$suffix',
        invoiceDate: date,
        warehouseId: warehouseId,
        userId: userId,
        total: const Value(100),
        paid: const Value(100),
        paymentMethod: const Value('cash'),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Test 1 — No filter returns all invoices
  // ─────────────────────────────────────────────────────────────────────────

  test('no date range returns all non-return, non-deleted invoices', () async {
    await insertInvoice(DateTime(2026, 1, 10));
    await insertInvoice(DateTime(2026, 3, 15));
    await insertInvoice(DateTime(2026, 6, 1));

    final result = await db.watchSalesInvoices().first;
    expect(result.length, 3);
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Test 2 — [from] filters out older invoices
  // ─────────────────────────────────────────────────────────────────────────

  test('from parameter excludes invoices before the start date', () async {
    await insertInvoice(DateTime(2026, 1, 10)); // before
    await insertInvoice(DateTime(2026, 3, 15)); // on start
    await insertInvoice(DateTime(2026, 6, 1)); // after

    final result = await db.watchSalesInvoices(from: DateTime(2026, 3, 15)).first;
    expect(result.length, 2);
    expect(result.every((i) => !i.invoiceDate.isBefore(DateTime(2026, 3, 15))), true);
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Test 3 — [to] filters out later invoices (inclusive of the end day)
  // ─────────────────────────────────────────────────────────────────────────

  test('to parameter excludes invoices after the end date (inclusive end day)',
      () async {
    await insertInvoice(DateTime(2026, 1, 10)); // before end
    await insertInvoice(DateTime(2026, 3, 15)); // on end day
    await insertInvoice(DateTime(2026, 6, 1)); // after

    final result = await db.watchSalesInvoices(to: DateTime(2026, 3, 15)).first;
    expect(result.length, 2);
    expect(
      result.every((i) => !i.invoiceDate.isAfter(DateTime(2026, 3, 15, 23, 59, 59))),
      true,
    );
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Test 4 — Both bounds applied together
  // ─────────────────────────────────────────────────────────────────────────

  test('from + to together narrow stream to the exact window', () async {
    await insertInvoice(DateTime(2026, 1, 5));  // outside — before
    await insertInvoice(DateTime(2026, 2, 1));  // inside
    await insertInvoice(DateTime(2026, 2, 28)); // inside — end day
    await insertInvoice(DateTime(2026, 3, 5));  // outside — after

    final result = await db
        .watchSalesInvoices(from: DateTime(2026, 2, 1), to: DateTime(2026, 2, 28))
        .first;

    expect(result.length, 2,
        reason: 'only the two February invoices should be in the window');
    for (final inv in result) {
      expect(inv.invoiceDate.isAfter(DateTime(2026, 1, 31)), true);
      expect(inv.invoiceDate.isBefore(DateTime(2026, 3, 1)), true);
    }
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Test 5 — Empty window returns empty stream event
  // ─────────────────────────────────────────────────────────────────────────

  test('window with no matching invoices emits an empty list', () async {
    await insertInvoice(DateTime(2026, 1, 10));
    await insertInvoice(DateTime(2026, 6, 1));

    final result = await db
        .watchSalesInvoices(from: DateTime(2026, 3, 1), to: DateTime(2026, 3, 31))
        .first;

    expect(result, isEmpty, reason: 'no invoices in March 2026');
  });
}
