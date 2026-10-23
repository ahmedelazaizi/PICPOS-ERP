import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/domain/entities/accounting_entities.dart';

/// PIR Integration Test 4 — Fiscal Period Blocking
///
/// Verifies that closing a fiscal year or accounting period prevents:
///   - Creating journal entries in the closed period
///   - Creating sales invoices dated in the closed period
///
/// This is a critical financial control — without it, users could
/// retroactively alter closed books.
void main() {
  late AppDatabase db;
  late int userId;
  late int warehouseId;
  late int productId;

  setUp(() async {
    db = AppDatabase.forTesting();

    final roleId = await db.into(db.roles).insert(
      RolesCompanion.insert(
        name: 'محاسب PIR',
        isSystemRole: const Value(false),
      ),
    );
    userId = await db.createUser(
      username: 'pir_fiscal_test',
      password: 'test123',
      displayName: 'PIR Fiscal Tester',
      roleId: roleId,
    );

    final wh = await db.getDefaultWarehouse();
    warehouseId = wh!.id;

    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'PIR-FP-01',
        name: 'منتج فترة مالية',
        salePrice: const Value(100.0),
        costPrice: const Value(50.0),
        trackInventory: const Value(true),
      ),
    );

    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 100.0,
      type: 'adjustment',
    );
  });

  tearDown(() async => db.close());

  group('PIR: Fiscal Period Blocking', () {
    test('Closed fiscal year blocks journal entry creation', () async {
      // Create and close a fiscal year for 2024
      final yearId = await db.into(db.fiscalYears).insert(
        FiscalYearsCompanion.insert(
          name: 'السنة المالية 2024',
          startDate: DateTime(2024, 1, 1),
          endDate: DateTime(2024, 12, 31),
        ),
      );

      await db.closeFiscalYear(yearId, userId);

      // Verify year is closed
      final closedYear = await (db.select(db.fiscalYears)
            ..where((y) => y.id.equals(yearId)))
          .getSingle();
      expect(closedYear.isClosed, isTrue);

      // Attempt to create a JE dated in the closed year — should throw
      await expectLater(
        db.createJournalEntry(
          description: 'قيد في فترة مغلقة',
          date: DateTime(2024, 6, 15),
          lines: [
            JournalLine(accountId: 1, debit: 100),
            JournalLine(accountId: 2, credit: 100),
          ],
          referenceType: 'manual',
        ),
        throwsA(isA<Exception>()),
        reason: 'Should reject JE creation in a closed fiscal year',
      );
    });

    test('Closed accounting period blocks operations in that month', () async {
      // Create a fiscal year first (required FK)
      final fyId = await db.into(db.fiscalYears).insert(
        FiscalYearsCompanion.insert(
          name: 'السنة المالية 2025',
          startDate: DateTime(2025, 1, 1),
          endDate: DateTime(2025, 12, 31),
        ),
      );

      // Create a closed accounting period for January 2025
      await db.into(db.accountingPeriods).insert(
        AccountingPeriodsCompanion.insert(
          fiscalYearId: fyId,
          name: 'يناير 2025',
          month: 1,
          year: 2025,
          startDate: DateTime(2025, 1, 1),
          endDate: DateTime(2025, 1, 31),
          isClosed: const Value(true),
        ),
      );

      // Attempt to create JE in January 2025 — should be blocked
      await expectLater(
        db.createJournalEntry(
          description: 'قيد في فترة يناير المغلقة',
          date: DateTime(2025, 1, 15),
          lines: [
            JournalLine(accountId: 1, debit: 500),
            JournalLine(accountId: 2, credit: 500),
          ],
          referenceType: 'manual',
        ),
        throwsA(isA<Exception>()),
        reason: 'Should reject JE creation in a closed accounting period',
      );
    });

    test('Open period allows normal operations', () async {
      // Create sale in current open period — should succeed
      final invoiceId = await db.createSalesInvoice(
        invoiceNumber: 'PIR-FP-OPEN-001',
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 100.0,
        discount: 0.0,
        tax: 0.0,
        total: 100.0,
        paid: 100.0,
        paymentMethod: 'cash',
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 1.0,
            unitPrice: 100.0,
            total: 100.0,
          ),
        ],
      );

      expect(invoiceId, isPositive,
          reason: 'Operations should succeed in an open period');
    });

    test('Multiple fiscal years can coexist: closed 2024, open 2025', () async {
      // Close 2024
      final year2024 = await db.into(db.fiscalYears).insert(
        FiscalYearsCompanion.insert(
          name: '2024',
          startDate: DateTime(2024, 1, 1),
          endDate: DateTime(2024, 12, 31),
        ),
      );
      await db.closeFiscalYear(year2024, userId);

      // Open 2025
      await db.into(db.fiscalYears).insert(
        FiscalYearsCompanion.insert(
          name: '2025',
          startDate: DateTime(2025, 1, 1),
          endDate: DateTime(2025, 12, 31),
        ),
      );

      // 2024 is blocked
      await expectLater(
        db.createJournalEntry(
          description: 'قيد 2024',
          date: DateTime(2024, 3, 1),
          lines: [
            JournalLine(accountId: 1, debit: 100),
            JournalLine(accountId: 2, credit: 100),
          ],
          referenceType: 'manual',
        ),
        throwsA(isA<Exception>()),
        reason: 'Closed 2024 should block JE creation',
      );
    });
  });
}
