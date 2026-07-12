import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';

/// PIR Integration Test 5: Trial Balance Dr=Cr Verification
/// Verifies that every journal entry maintains debit=credit balance.
void main() {
  late AppDatabase db;
  late int warehouseId;
  late int userId;
  late int productId;

  setUp(() async {
    db = AppDatabase.forTesting();

    final roleId = await db.into(db.roles).insert(
      RolesCompanion.insert(name: 'محاسب', isSystemRole: const Value(false)),
    );
    userId = await db.createUser(
      username: 'tb_test',
      password: 'test123',
      displayName: 'TB Tester',
      roleId: roleId,
    );

    // Spec 062: grant the void-paid-invoice critical-op permission so the
    // gate in voidSalesInvoice allows voiding fully-paid invoices.
    final voidPerm = await (db.select(db.permissions)
          ..where((p) => p.code.equals(PermissionCodes.voidPaidInvoice))
          ..limit(1))
        .getSingle();
    await db.addPermissionToRole(roleId, voidPerm.id);

    final wh = await db.getDefaultWarehouse();
    warehouseId = wh!.id;

    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'TB-01',
        name: 'منتج ميزان المراجعة',
        salePrice: const Value(100.0),
        costPrice: const Value(60.0),
        trackInventory: const Value(true),
      ),
    );

    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 50.0,
      type: 'adjustment',
    );
  });

  tearDown(() async => db.close());

  group('PIR: Trial Balance Integrity', () {
    test('Journal entry lines always balance (Dr=Cr)', () async {
      // Create a sale to trigger auto-posting
      await db.createSalesInvoice(
        invoiceNumber: 'TB-001',
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 500.0,
        discount: 0.0,
        tax: 70.0,
        total: 570.0,
        paid: 570.0,
        paymentMethod: 'cash',
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 5.0,
            unitPrice: 100.0,
            total: 500.0,
            taxRate: const Value(14.0),
            taxAmount: const Value(70.0),
          ),
        ],
      );

      // Fetch ALL journal entries
      final entries = await db.select(db.journalEntries).get();

      for (final entry in entries) {
        final lines = await (db.select(db.journalEntryLines)
              ..where((l) => l.entryId.equals(entry.id)))
            .get();

        double totalDebit = 0;
        double totalCredit = 0;
        for (final line in lines) {
          totalDebit += line.debit;
          totalCredit += line.credit;
        }

        // Allow for floating point tolerance
        expect(
          (totalDebit - totalCredit).abs(),
          lessThan(0.01),
          reason: 'JE #${entry.id} (${entry.description}): '
              'Debit=$totalDebit != Credit=$totalCredit — IMBALANCED!',
        );
      }
    });

    test('Global trial balance sums to zero net', () async {
      // Create multiple transactions
      await db.createSalesInvoice(
        invoiceNumber: 'TB-002',
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 200.0,
        discount: 0.0,
        tax: 0.0,
        total: 200.0,
        paid: 200.0,
        paymentMethod: 'cash',
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 2.0,
            unitPrice: 100.0,
            total: 200.0,
          ),
        ],
      );

      // Sum all JE lines globally
      final result = await db.customSelect(
        'SELECT '
        'COALESCE(SUM(debit), 0) as total_debit, '
        'COALESCE(SUM(credit), 0) as total_credit '
        'FROM journal_entry_lines',
        readsFrom: {db.journalEntryLines},
      ).getSingle();

      final totalDebit = (result.data['total_debit'] as num).toDouble();
      final totalCredit = (result.data['total_credit'] as num).toDouble();

      expect(
        (totalDebit - totalCredit).abs(),
        lessThan(0.01),
        reason: 'Global trial balance must equal zero: '
            'Total Dr=$totalDebit, Total Cr=$totalCredit',
      );
    });

    test('Void invoice also maintains Dr=Cr after reversal JE', () async {
      final invoiceId = await db.createSalesInvoice(
        invoiceNumber: 'TB-003',
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 300.0,
        discount: 0.0,
        tax: 0.0,
        total: 300.0,
        paid: 300.0,
        paymentMethod: 'cash',
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 3.0,
            unitPrice: 100.0,
            total: 300.0,
          ),
        ],
      );

      // Void it
      await db.voidSalesInvoice(invoiceId, reason: 'TB test', deletedBy: userId);

      // ALL entries including reversals must balance
      final entries = await db.select(db.journalEntries).get();
      for (final entry in entries) {
        final lines = await (db.select(db.journalEntryLines)
              ..where((l) => l.entryId.equals(entry.id)))
            .get();

        double totalDebit = 0;
        double totalCredit = 0;
        for (final line in lines) {
          totalDebit += line.debit;
          totalCredit += line.credit;
        }

        expect(
          (totalDebit - totalCredit).abs(),
          lessThan(0.01),
          reason: 'JE #${entry.id} after void: Dr=$totalDebit Cr=$totalCredit',
        );
      }
    });
  });
}
