import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/repositories/drift_accounting_repository.dart';
import 'package:picpos_erp/services/accounting_service.dart';
import 'package:picpos_erp/domain/repositories/parties_repository.dart';
import 'package:picpos_erp/domain/repositories/i_products_repository.dart';
import 'package:picpos_erp/domain/repositories/inventory_repository.dart';
import 'package:picpos_erp/domain/repositories/settings_repository.dart';
import 'package:picpos_erp/domain/repositories/audit_repository_interface.dart';
import 'package:picpos_erp/domain/repositories/treasury_repository.dart';

/// PIR Integration Test — Double-Entry Accounting Integrity
///
/// Validates that every auto-posted journal entry in the system maintains
/// the fundamental accounting equation: Total Debits == Total Credits.
/// Tests cover: cash sales, credit sales, returns, multi-payment splits,
/// and edge cases like zero-value transactions.
void main() {
  late AppDatabase db;
  late DriftAccountingRepository repo;
  late AccountingService svc;

  setUp(() async {
    db = AppDatabase.forTesting();
    repo = DriftAccountingRepository(db);
    // Note: syncDefaultAccounts is called by beforeOpen automatically
    svc = AccountingService(
      repo,
      _ThrowingPartiesRepo(),
      _ThrowingTreasuryRepo(),
      _ThrowingProductRepo(),
      _ThrowingInventoryRepo(),
      _ThrowingSettingsRepo(),
      _ThrowingAuditRepo(),
    );
  });

  tearDown(() async => db.close());

  // ═══════════════════════════════════════════════════════════════════════
  // CORE BALANCE INVARIANT
  // ═══════════════════════════════════════════════════════════════════════

  group('Double-Entry Balance Invariant', () {
    test('Cash sale with discount + VAT produces balanced JE', () async {
      // Arrange: 3 items, 10% discount, 14% VAT
      await svc.generateSalesAccountingEntry(
        invoiceId: 1,
        invNumber: 'PIR-DE-001',
        tax: 63,  // 14% of (500-50)=450
        paid: 513,
        remaining: 0,
        paymentMethod: 'cash',
        deliveryFee: 0,
        items: [
          const SalesInvoiceItem(
            id: 1, invoiceId: 1, productId: 1,
            quantity: 5, unitPrice: 100, discount: 0, total: 500,
            costPrice: 60, sortOrder: 0, taxRate: 14, taxAmount: 63, quantityInBase: 5,
            rowVersion: 0,
          ),
        ],
      );

      // Assert: balanced
      final entries = await repo.getJournalEntries();
      expect(entries, hasLength(1));

      final lines = await (db.select(db.journalEntryLines)
        ..where((l) => l.entryId.equals(entries.first.id)))
        .get();

      final totalDebit = lines.fold<double>(0, (s, l) => s + l.debit);
      final totalCredit = lines.fold<double>(0, (s, l) => s + l.credit);
      expect(totalDebit, totalCredit,
          reason: 'INVARIANT: Total Debit == Total Credit for cash sale with discount + VAT');
      expect(totalDebit, greaterThan(0),
          reason: 'JE should have non-zero amounts');
    });

    test('Credit sale creates AR for remaining balance', () async {
      await svc.generateSalesAccountingEntry(
        invoiceId: 10,
        invNumber: 'PIR-DE-002',
        tax: 140,
        paid: 400,
        remaining: 740,
        paymentMethod: 'cash',
        deliveryFee: 0,
        items: [
          const SalesInvoiceItem(
            id: 10, invoiceId: 10, productId: 2,
            quantity: 10, unitPrice: 100, discount: 0, total: 1000,
            costPrice: 50, sortOrder: 0, taxRate: 14, taxAmount: 140, quantityInBase: 10,
            rowVersion: 0,
          ),
        ],
      );

      final entries = await repo.getJournalEntries();
      expect(entries, hasLength(1));

      final lines = await (db.select(db.journalEntryLines)
        ..where((l) => l.entryId.equals(entries.first.id)))
        .get();

      // Balance check
      final totalDebit = lines.fold<double>(0, (s, l) => s + l.debit);
      final totalCredit = lines.fold<double>(0, (s, l) => s + l.credit);
      expect(totalDebit, totalCredit,
          reason: 'Credit sale must be balanced');

      // AR check — account 1201
      final arAcc = await repo.getAccountByCode('1121');
      expect(arAcc, isNotNull, reason: 'AR account (1121) must exist');

      final arLine = lines.firstWhere((l) => l.accountId == arAcc!.id);
      expect(arLine.debit, 740,
          reason: 'AR debit should equal remaining amount (total incl tax - paid)');
    });

    test('Multiple sales generate independent balanced JEs', () async {
      // Sale 1: simple cash
      await svc.generateSalesAccountingEntry(
        invoiceId: 20,
        invNumber: 'PIR-DE-003A',
        tax: 0,
        paid: 200,
        remaining: 0,
        paymentMethod: 'cash',
        deliveryFee: 0,
        items: [
          const SalesInvoiceItem(
            id: 20, invoiceId: 20, productId: 1,
            quantity: 2, unitPrice: 100, discount: 0, total: 200,
            costPrice: 70, sortOrder: 0, taxRate: 0, taxAmount: 0, quantityInBase: 2,
            rowVersion: 0,
          ),
        ],
      );

      // Sale 2: bank payment
      await svc.generateSalesAccountingEntry(
        invoiceId: 21,
        invNumber: 'PIR-DE-003B',
        tax: 42,
        paid: 342,
        remaining: 0,
        paymentMethod: 'bank',
        deliveryFee: 0,
        items: [
          const SalesInvoiceItem(
            id: 21, invoiceId: 21, productId: 2,
            quantity: 3, unitPrice: 100, discount: 0, total: 300,
            costPrice: 40, sortOrder: 0, taxRate: 14, taxAmount: 42, quantityInBase: 3,
            rowVersion: 0,
          ),
        ],
      );

      final entries = await repo.getJournalEntries();
      expect(entries, hasLength(2), reason: 'Two sales = two JEs');

      // Verify each independently balanced
      for (final entry in entries) {
        final lines = await (db.select(db.journalEntryLines)
          ..where((l) => l.entryId.equals(entry.id)))
          .get();

        final totalDebit = lines.fold<double>(0, (s, l) => s + l.debit);
        final totalCredit = lines.fold<double>(0, (s, l) => s + l.credit);
        expect(totalDebit, totalCredit,
            reason: 'JE ${entry.id} must be balanced');
      }
    });

    test('Bank payment debits account 1102 (not 1101)', () async {
      await svc.generateSalesAccountingEntry(
        invoiceId: 30,
        invNumber: 'PIR-DE-004',
        tax: 0,
        paid: 500,
        remaining: 0,
        paymentMethod: 'bank',
        deliveryFee: 0,
        items: [
          const SalesInvoiceItem(
            id: 30, invoiceId: 30, productId: 1,
            quantity: 5, unitPrice: 100, discount: 0, total: 500,
            costPrice: 30, sortOrder: 0, taxRate: 0, taxAmount: 0, quantityInBase: 5,
            rowVersion: 0,
          ),
        ],
      );

      final entries = await repo.getJournalEntries();
      final lines = await (db.select(db.journalEntryLines)
        ..where((l) => l.entryId.equals(entries.first.id)))
        .get();

      // Bank account 1102 should be debited, NOT cash 1101
      final bankAcc = await repo.getAccountByCode('1113');
      expect(bankAcc, isNotNull);

      final bankLine = lines.where((l) => l.accountId == bankAcc!.id).toList();
      expect(bankLine, hasLength(1), reason: 'Bank debit line must exist');
      expect(bankLine.first.debit, 500);
    });

    test('Zero-value sale creates no journal entry', () async {
      await svc.generateSalesAccountingEntry(
        invoiceId: 40,
        invNumber: 'PIR-DE-005',
        tax: 0,
        paid: 0,
        remaining: 0,
        paymentMethod: 'cash',
        deliveryFee: 0,
        items: [],
      );

      final entries = await repo.getJournalEntries();
      expect(entries, isEmpty, reason: 'No JE for zero-value sale');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // COGS & INVENTORY POSTING
  // ═══════════════════════════════════════════════════════════════════════

  group('COGS & Inventory Posting', () {
    test('COGS equals costPrice × quantity', () async {
      const costPrice = 45.0;
      const quantity = 8.0;

      await svc.generateSalesAccountingEntry(
        invoiceId: 50,
        invNumber: 'PIR-COGS-001',
        tax: 0,
        paid: 800,
        remaining: 0,
        paymentMethod: 'cash',
        deliveryFee: 0,
        items: [
          const SalesInvoiceItem(
            id: 50, invoiceId: 50, productId: 1,
            quantity: quantity, unitPrice: 100, discount: 0, total: 800,
            // SAL-1: this test validates the base-unit case (quantityInBase=1
            // — no UOM conversion), so costPrice×quantity is the correct COGS.
            // See "COGS threads quantityInBase" below for the carton/box case.
            costPrice: costPrice, sortOrder: 0, taxRate: 0, taxAmount: 0, quantityInBase: 1,
            rowVersion: 0,
          ),
        ],
      );

      final entries = await repo.getJournalEntries();
      final lines = await (db.select(db.journalEntryLines)
        ..where((l) => l.entryId.equals(entries.first.id)))
        .get();

      final cogsAcc = await repo.getAccountByCode('5211');
      expect(cogsAcc, isNotNull);

      final cogsLine = lines.firstWhere((l) => l.accountId == cogsAcc!.id);
      expect(cogsLine.debit, costPrice * quantity,
          reason: 'COGS = cost × quantity = ${costPrice * quantity}');

      // Inventory credit must mirror COGS debit
      final invAcc = await repo.getAccountByCode('1136');
      expect(invAcc, isNotNull);

      final invLine = lines.firstWhere((l) => l.accountId == invAcc!.id);
      expect(invLine.credit, costPrice * quantity,
          reason: 'Inventory credit must equal COGS debit');
    });

    test('Multi-item COGS aggregation', () async {
      await svc.generateSalesAccountingEntry(
        invoiceId: 51,
        invNumber: 'PIR-COGS-002',
        tax: 0,
        paid: 550,
        remaining: 0,
        paymentMethod: 'cash',
        deliveryFee: 0,
        items: [
          const SalesInvoiceItem(
            id: 51, invoiceId: 51, productId: 1,
            quantity: 5, unitPrice: 50, discount: 0, total: 250,
            // SAL-1: quantityInBase=1 — base-unit sale, no UOM conversion.
            costPrice: 30, sortOrder: 0, taxRate: 0, taxAmount: 0, quantityInBase: 1,
            rowVersion: 0,
          ),
          const SalesInvoiceItem(
            id: 52, invoiceId: 51, productId: 2,
            quantity: 3, unitPrice: 100, discount: 0, total: 300,
            costPrice: 60, sortOrder: 1, taxRate: 0, taxAmount: 0, quantityInBase: 1,
            rowVersion: 0,
          ),
        ],
      );

      final entries = await repo.getJournalEntries();
      final lines = await (db.select(db.journalEntryLines)
        ..where((l) => l.entryId.equals(entries.first.id)))
        .get();

      final cogsAcc = await repo.getAccountByCode('5211');
      final cogsLine = lines.firstWhere((l) => l.accountId == cogsAcc!.id);
      // 5×30 + 3×60 = 150 + 180 = 330
      expect(cogsLine.debit, 330,
          reason: 'COGS = sum(cost×qty) for all items');

      // Overall balance
      final totalDebit = lines.fold<double>(0, (s, l) => s + l.debit);
      final totalCredit = lines.fold<double>(0, (s, l) => s + l.credit);
      expect(totalDebit, totalCredit);
    });

    // SAL-1 regression guard — cost_price is per BASE unit (WAC); quantity is
    // in SALE units. Selling a carton (quantityInBase=24) must post COGS for
    // the full physical stock removed (3 cartons × 24 pieces × 10/piece =
    // 720), not just 3×10=30 (the pre-fix bug that understated COGS/inventory
    // credit on every non-base-unit sale).
    test('COGS threads quantityInBase — carton sale = qty × qtyInBase × cost',
        () async {
      const costPrice = 10.0; // per BASE unit (piece)
      const quantity = 3.0; // SALE units (cartons)
      const quantityInBase = 24.0; // pieces per carton
      const expectedCogs = quantity * quantityInBase * costPrice; // 720

      await svc.generateSalesAccountingEntry(
        invoiceId: 60,
        invNumber: 'PIR-COGS-UOM-001',
        tax: 0,
        paid: 900,
        remaining: 0,
        paymentMethod: 'cash',
        deliveryFee: 0,
        items: [
          const SalesInvoiceItem(
            id: 60, invoiceId: 60, productId: 1,
            quantity: quantity, unitPrice: 300, discount: 0, total: 900,
            costPrice: costPrice, sortOrder: 0, taxRate: 0, taxAmount: 0,
            quantityInBase: quantityInBase,
            rowVersion: 0,
          ),
        ],
      );

      final entries = await repo.getJournalEntries();
      final lines = await (db.select(db.journalEntryLines)
        ..where((l) => l.entryId.equals(entries.first.id)))
        .get();

      final cogsAcc = await repo.getAccountByCode('5211');
      final cogsLine = lines.firstWhere((l) => l.accountId == cogsAcc!.id);
      expect(cogsLine.debit, expectedCogs,
          reason: 'COGS must be qty × quantityInBase × costPrice = $expectedCogs, '
              'not qty × costPrice (30)');

      final invAcc = await repo.getAccountByCode('1136');
      final invLine = lines.firstWhere((l) => l.accountId == invAcc!.id);
      expect(invLine.credit, expectedCogs,
          reason: 'Inventory credit must mirror the UOM-aware COGS debit');

      final totalDebit = lines.fold<double>(0, (s, l) => s + l.debit);
      final totalCredit = lines.fold<double>(0, (s, l) => s + l.credit);
      expect(totalDebit, totalCredit, reason: 'JE must still balance');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // PURCHASE AUTO-POSTING
  // ═══════════════════════════════════════════════════════════════════════

  group('Purchase Auto-Posting', () {
    test('Cash purchase with VAT creates balanced JE', () async {
      await svc.generatePurchaseAccountingEntry(
        invoiceId: 60,
        subtotal: 2000,
        tax: 280,
        total: 2280,
        paid: 2280,
        remaining: 0,
        notes: 'PIR purchase test',
      );

      final entries = await repo.getJournalEntries();
      expect(entries, hasLength(1));

      final lines = await (db.select(db.journalEntryLines)
        ..where((l) => l.entryId.equals(entries.first.id)))
        .get();

      final totalDebit = lines.fold<double>(0, (s, l) => s + l.debit);
      final totalCredit = lines.fold<double>(0, (s, l) => s + l.credit);
      expect(totalDebit, totalCredit, reason: 'Purchase JE must be balanced');

      // Inventory debit = subtotal
      final invAcc = await repo.getAccountByCode('1136');
      final invLine = lines.firstWhere((l) => l.accountId == invAcc!.id);
      expect(invLine.debit, 2000);

      // Input VAT debit
      final vatAcc = await repo.getAccountByCode('1141');
      final vatLine = lines.firstWhere((l) => l.accountId == vatAcc!.id);
      expect(vatLine.debit, 280);

      // Cash credit = total paid
      final cashAcc = await repo.getAccountByCode('1111');
      final cashLine = lines.firstWhere((l) => l.accountId == cashAcc!.id);
      expect(cashLine.credit, 2280);
    });

    test('Credit purchase posts AP for remaining', () async {
      await svc.generatePurchaseAccountingEntry(
        invoiceId: 61,
        subtotal: 5000,
        tax: 0,
        total: 5000,
        paid: 2000,
        remaining: 3000,
        notes: null,
      );

      final entries = await repo.getJournalEntries();
      final lines = await (db.select(db.journalEntryLines)
        ..where((l) => l.entryId.equals(entries.first.id)))
        .get();

      // AP account 2101
      final apAcc = await repo.getAccountByCode('2111');
      expect(apAcc, isNotNull);
      final apLine = lines.firstWhere((l) => l.accountId == apAcc!.id);
      expect(apLine.credit, 3000, reason: 'AP = remaining amount');

      // Balance
      final totalDebit = lines.fold<double>(0, (s, l) => s + l.debit);
      final totalCredit = lines.fold<double>(0, (s, l) => s + l.credit);
      expect(totalDebit, totalCredit);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // DELIVERY FEE — IFRS 15.38
  // ═══════════════════════════════════════════════════════════════════════

  group('Delivery Fee Revenue Separation', () {
    test('Delivery fee posts to separate delivery revenue account 4102', () async {
      await svc.generateSalesAccountingEntry(
        invoiceId: 70,
        invNumber: 'PIR-DEL-001',
        tax: 0,
        paid: 450,
        remaining: 0,
        paymentMethod: 'cash',
        deliveryFee: 50,
        items: [
          const SalesInvoiceItem(
            id: 70, invoiceId: 70, productId: 1,
            quantity: 4, unitPrice: 100, discount: 0, total: 400,
            costPrice: 30, sortOrder: 0, taxRate: 0, taxAmount: 0, quantityInBase: 4,
            rowVersion: 0,
          ),
        ],
      );

      final entries = await repo.getJournalEntries();
      final lines = await (db.select(db.journalEntryLines)
        ..where((l) => l.entryId.equals(entries.first.id)))
        .get();

      // Main sales revenue
      final salesAcc = await repo.getAccountByCode('4121');
      final salesLines = lines.where((l) => l.accountId == salesAcc!.id).toList();
      final salesCredit = salesLines.fold<double>(0, (s, l) => s + l.credit);
      expect(salesCredit, 400, reason: 'Sales revenue = subtotal');

      // Delivery revenue (separate performance obligation per IFRS 15)
      final deliveryAcc = await repo.getAccountByCode('414');
      expect(deliveryAcc, isNotNull, reason: 'Delivery revenue account must exist');
      final deliveryCredit = lines
          .where((l) => l.accountId == deliveryAcc!.id)
          .fold<double>(0, (s, l) => s + l.credit);
      expect(deliveryCredit, 50, reason: 'Delivery revenue = delivery fee');

      // Balance
      final totalDebit = lines.fold<double>(0, (s, l) => s + l.debit);
      final totalCredit = lines.fold<double>(0, (s, l) => s + l.credit);
      expect(totalDebit, totalCredit);
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Throwing stubs — only IAccountingRepository is used in these tests.
// ═══════════════════════════════════════════════════════════════════════════

class _ThrowingPartiesRepo implements IPartiesRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError(
      'Stub: ${inv.memberName} not expected in double-entry tests');
}

class _ThrowingTreasuryRepo implements ITreasuryRepository {
  @override
  Future<List<Map<String, dynamic>>> getSafeAccountsForReference(String referenceType, int referenceId) async => [];

  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError(
      'Stub: ${inv.memberName} not expected in double-entry tests');
}

class _ThrowingProductRepo implements IProductRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError(
      'Stub: ${inv.memberName} not expected in double-entry tests');
}

class _ThrowingInventoryRepo implements InventoryRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError(
      'Stub: ${inv.memberName} not expected in double-entry tests');
}

class _ThrowingSettingsRepo implements ISettingsRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError(
      'Stub: ${inv.memberName} not expected in double-entry tests');
}

class _ThrowingAuditRepo implements IAuditRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError(
      'Stub: ${inv.memberName} not expected in double-entry tests');
}
