// Spec 062 / SC-001 — criticalFinancialOps gate regression tests.
//
// Wires 3 of 6 codes (the ones with concrete DAO call sites today):
//  - voidPaidInvoice    → voidSalesInvoice / voidPurchaseInvoice
//  - modifyLockedInvoice → updateSalesInvoice / updatePurchaseInvoice
//  - overrideCreditLimit → createSalesInvoice / createPurchaseInvoice / etc.
//
// Each op is exercised with two scenarios:
//  1. Bootstrap admin (no explicit critical perm) → action refused.
//  2. Same admin AFTER granting the explicit perm → action succeeds.
//
// QA finding D1-004 (P0). Companion to spec 061's bootstrap_admin_guards.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  group('voidPaidInvoice gate (Spec 062 / US1)', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting();
    });

    tearDown(() async {
      await db.close();
    });

    Future<int> insertPaidInvoice() async {
      // Insert a fully-paid sales invoice for the bootstrap admin.
      return db.into(db.salesInvoices).insert(
            SalesInvoicesCompanion.insert(
              invoiceNumber: 'POS-TEST-1',
              warehouseId: 1,
              userId: 1,
              invoiceDate: DateTime.now(),
              subtotal: const Value(100.0),
              total: const Value(100.0),
              paid: const Value(100.0),
              status: const Value('completed'),
            ),
          );
    }

    test('admin (no perm) cannot void a fully-paid invoice', () async {
      final id = await insertPaidInvoice();
      expect(
        () => db.voidSalesInvoice(id, deletedBy: 1),
        throwsA(isA<PermissionDeniedException>().having(
          (e) => e.code,
          'code',
          PermissionCodes.voidPaidInvoice,
        )),
      );
    });

    test('admin WITH voidPaidInvoice permission can void a paid invoice',
        () async {
      final id = await insertPaidInvoice();
      // Grant voidPaidInvoice to the system-admin role (id=1 by convention).
      final permRow = await (db.select(db.permissions)
            ..where((p) => p.code.equals(PermissionCodes.voidPaidInvoice))
            ..limit(1))
          .getSingleOrNull();
      expect(permRow, isNotNull,
          reason: 'voidPaidInvoice must be seeded into the permissions table');
      await db.addPermissionToRole(1, permRow!.id);

      // Should not throw now.
      await db.voidSalesInvoice(id, deletedBy: 1);

      final after = await (db.select(db.salesInvoices)
            ..where((i) => i.id.equals(id)))
          .getSingle();
      expect(after.status, equals('voided'));
    });

    test('partially-paid void runs without permission check (common path)',
        () async {
      final id = await db.into(db.salesInvoices).insert(
            SalesInvoicesCompanion.insert(
              invoiceNumber: 'POS-TEST-2',
              warehouseId: 1,
              userId: 1,
              invoiceDate: DateTime.now(),
              subtotal: const Value(100.0),
              total: const Value(100.0),
              paid: const Value(50.0),
              status: const Value('pending'),
            ),
          );
      // No permission granted, no exception expected.
      await db.voidSalesInvoice(id, deletedBy: 1);
      final after = await (db.select(db.salesInvoices)
            ..where((i) => i.id.equals(id)))
          .getSingle();
      expect(after.status, equals('voided'));
    });
  });

  group('modifyLockedInvoice gate (Spec 062 / US2)', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting();
    });

    tearDown(() async {
      await db.close();
    });

    Future<int> insertLockedInvoice() async {
      return db.into(db.salesInvoices).insert(
            SalesInvoicesCompanion.insert(
              invoiceNumber: 'POS-LOCK-1',
              warehouseId: 1,
              userId: 1,
              invoiceDate: DateTime.now(),
              subtotal: const Value(50.0),
              total: const Value(50.0),
              paid: const Value(50.0),
              status: const Value('completed'),
              isLocked: const Value(true),
            ),
          );
    }

    test('admin (no perm) cannot edit a locked invoice', () async {
      final id = await insertLockedInvoice();
      expect(
        () => db.updateSalesInvoice(
          invoiceId: id,
          subtotal: 60.0,
          discount: 0,
          tax: 0,
          total: 60.0,
          paid: 60.0,
          paymentMethod: 'cash',
          items: [],
          userId: 1,
        ),
        throwsA(isA<PermissionDeniedException>().having(
          (e) => e.code,
          'code',
          PermissionCodes.modifyLockedInvoice,
        )),
      );
    });

    test('admin WITH modifyLockedInvoice can edit a locked invoice',
        () async {
      final id = await insertLockedInvoice();
      final permRow = await (db.select(db.permissions)
            ..where(
                (p) => p.code.equals(PermissionCodes.modifyLockedInvoice))
            ..limit(1))
          .getSingleOrNull();
      expect(permRow, isNotNull);
      await db.addPermissionToRole(1, permRow!.id);

      await db.updateSalesInvoice(
        invoiceId: id,
        subtotal: 60.0,
        discount: 0,
        tax: 0,
        total: 60.0,
        paid: 60.0,
        paymentMethod: 'cash',
        items: [],
        userId: 1,
      );

      final after =
          await (db.select(db.salesInvoices)..where((i) => i.id.equals(id)))
              .getSingle();
      expect(after.total, equals(60.0));
    });

    test('unlocked invoice edits without any permission check', () async {
      final id = await db.into(db.salesInvoices).insert(
            SalesInvoicesCompanion.insert(
              invoiceNumber: 'POS-UNLOCKED-1',
              warehouseId: 1,
              userId: 1,
              invoiceDate: DateTime.now(),
              subtotal: const Value(50.0),
              total: const Value(50.0),
              paid: const Value(50.0),
              status: const Value('completed'),
              isLocked: const Value(false),
            ),
          );
      // No permission granted, but unlocked → edit allowed.
      await db.updateSalesInvoice(
        invoiceId: id,
        subtotal: 70.0,
        discount: 0,
        tax: 0,
        total: 70.0,
        paid: 70.0,
        paymentMethod: 'cash',
        items: [],
        userId: 1,
      );
      final after =
          await (db.select(db.salesInvoices)..where((i) => i.id.equals(id)))
              .getSingle();
      expect(after.total, equals(70.0));
    });
  });

  group('overrideCreditLimit gate (Spec 062 / US3)', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting();
    });

    tearDown(() async {
      await db.close();
    });

    Future<int> insertCustomerWithLimit({
      required double balance,
      required double creditLimit,
    }) async {
      return db.into(db.parties).insert(
            PartiesCompanion.insert(
              name: 'Test Customer',
              isCustomer: const Value(true),
              balance: Value(balance),
              creditLimit: Value(creditLimit),
            ),
          );
    }

    test(
        'admin (no perm) cannot create sales invoice that exceeds credit limit',
        () async {
      final customerId = await insertCustomerWithLimit(
        balance: 800.0,
        creditLimit: 1000.0,
      );
      // Sanity-check: the row is actually present with the values we set.
      final customer = await (db.select(db.parties)
            ..where((p) => p.id.equals(customerId)))
          .getSingle();
      expect(customer.balance, equals(800.0));
      expect(customer.creditLimit, equals(1000.0));

      await expectLater(
        () => db.createSalesInvoice(
          customerId: customerId,
          warehouseId: 1,
          userId: 1,
          subtotal: 500.0,
          discount: 0,
          tax: 0,
          total: 500.0,
          paid: 0, // remaining = 500; projected = 800 + 500 = 1300 > 1000
          paymentMethod: 'cash',
          items: const [],
        ),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('الحد الائتماني'),
        )),
      );
    });

    test(
        'admin WITH overrideCreditLimit can create over-limit sales invoice',
        () async {
      final customerId = await insertCustomerWithLimit(
        balance: 800.0,
        creditLimit: 1000.0,
      );
      final permRow = await (db.select(db.permissions)
            ..where(
                (p) => p.code.equals(PermissionCodes.overrideCreditLimit))
            ..limit(1))
          .getSingleOrNull();
      expect(permRow, isNotNull);
      await db.addPermissionToRole(1, permRow!.id);

      // Should not throw — over-limit but admin holds override.
      final invoiceId = await db.createSalesInvoice(
        customerId: customerId,
        warehouseId: 1,
        userId: 1,
        subtotal: 500.0,
        discount: 0,
        tax: 0,
        total: 500.0,
        paid: 0,
        paymentMethod: 'cash',
        items: const [],
      );
      expect(invoiceId, greaterThan(0));
    });

    test('within-limit sale runs without permission check (common path)',
        () async {
      final customerId = await insertCustomerWithLimit(
        balance: 100.0,
        creditLimit: 1000.0,
      );
      // No permission granted, but within limit → no check.
      final invoiceId = await db.createSalesInvoice(
        customerId: customerId,
        warehouseId: 1,
        userId: 1,
        subtotal: 200.0,
        discount: 0,
        tax: 0,
        total: 200.0,
        paid: 0, // projected = 100 + 200 = 300 < 1000
        paymentMethod: 'cash',
        items: const [],
      );
      expect(invoiceId, greaterThan(0));
    });
  });
}
