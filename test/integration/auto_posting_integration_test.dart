import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/repositories/drift_accounting_repository.dart';
import 'package:ural_erp/services/accounting_service.dart';
import 'package:ural_erp/domain/repositories/parties_repository.dart';
import 'package:ural_erp/domain/repositories/i_products_repository.dart';
import 'package:ural_erp/domain/repositories/inventory_repository.dart';
import 'package:ural_erp/domain/repositories/settings_repository.dart';
import 'package:ural_erp/domain/repositories/audit_repository_interface.dart';
import 'package:ural_erp/domain/repositories/treasury_repository.dart';

/// Integration Test: Auto-Posting Accounting Entries (PIR T02)
///
/// Tests that AccountingService.generateSalesAccountingEntry and
/// generatePurchaseAccountingEntry produce balanced, correct journal entries
/// against a real in-memory database.
void main() {
  late AppDatabase db;
  late DriftAccountingRepository repo;
  late AccountingService svc;

  setUp(() async {
    db = AppDatabase.forTesting();
    repo = DriftAccountingRepository(db);
    // Note: syncDefaultAccounts is called by beforeOpen automatically
    // AccountingService requires 7 params; only accountingRepo is used for auto-posting tests.
    // Other repos are provided as stubs (will throw if accidentally called).
    svc = AccountingService(
      repo, // IAccountingRepository
      _ThrowingPartiesRepo(),
      _ThrowingTreasuryRepo(),
      _ThrowingProductRepo(),
      _ThrowingInventoryRepo(),
      _ThrowingSettingsRepo(),
      _ThrowingAuditRepo(),
    );
  });

  tearDown(() async => db.close());

  // ═══════════════════════════════════════════════════════════════
  // Sales Invoice Auto-Posting
  // ═══════════════════════════════════════════════════════════════

  group('Sales Auto-Posting', () {
    test('Cash sale creates balanced journal entry', () async {
      // Arrange
      await svc.generateSalesAccountingEntry(
        invoiceId: 1,
        invNumber: 'INV-T-001',
        tax: 63, // 14% of (500-50)
        paid: 513,
        remaining: 0,
        paymentMethod: 'cash',
        deliveryFee: 0,
        items: [
          const SalesInvoiceItem(
            id: 1, invoiceId: 1, productId: 1,
            quantity: 5, unitPrice: 100, discount: 0, total: 500,
            // SAL-1: quantityInBase=1 — base-unit sale, no UOM conversion,
            // so cogsLine.debit below (300) is qty×cost with no multiplier.
            costPrice: 60, sortOrder: 0, taxRate: 14, taxAmount: 63, quantityInBase: 1,
            rowVersion: 0,
          ),
        ],
      );

      // Act — query the journal entries
      final entries = await repo.getJournalEntries();
      expect(entries, hasLength(1), reason: 'One journal entry should be created');

      // Verify balanced (sum of debits == sum of credits)
      final entry = entries.first;
      final lines = await (db.select(db.journalEntryLines)
        ..where((l) => l.entryId.equals(entry.id)))
        .get();

      final totalDebit = lines.fold<double>(0, (s, l) => s + l.debit);
      final totalCredit = lines.fold<double>(0, (s, l) => s + l.credit);
      expect(totalDebit, totalCredit,
          reason: 'Debit total must equal Credit total (double-entry balance)');

      // Verify specific accounts
      // Debit: Cash 1101 = 513, COGS 5101 = 300 (60*5)
      // Credit: Sales 4101 = 450 (500-50), Tax 2201 = 63, Inventory 1103 = 300
      final cashAcc = await repo.getAccountByCode('1111');
      final cogsAcc = await repo.getAccountByCode('5211');
      final salesAcc = await repo.getAccountByCode('4121');
      final taxAcc = await repo.getAccountByCode('2121');
      final invAcc = await repo.getAccountByCode('1136');

      expect(cashAcc, isNotNull, reason: 'Cash account (1111) must exist');
      expect(cogsAcc, isNotNull, reason: 'COGS account (5211) must exist');
      expect(salesAcc, isNotNull, reason: 'Sales account (4121) must exist');
      expect(taxAcc, isNotNull, reason: 'Tax account (2121) must exist');
      expect(invAcc, isNotNull, reason: 'Inventory account (1136) must exist');

      // Verify amounts
      final cashLine = lines.firstWhere((l) => l.accountId == cashAcc!.id);
      expect(cashLine.debit, 513, reason: 'Cash debit should be paid amount');
      expect(cashLine.credit, 0);

      final cogsLine = lines.firstWhere((l) => l.accountId == cogsAcc!.id);
      expect(cogsLine.debit, 300, reason: 'COGS debit should be 60 × 5 = 300');

      final salesLine = lines.firstWhere((l) => l.accountId == salesAcc!.id);
      expect(salesLine.credit, 450, reason: 'Sales credit = subtotal - discount');

      final taxLine = lines.firstWhere((l) => l.accountId == taxAcc!.id);
      expect(taxLine.credit, 63, reason: 'Tax credit = output VAT');

      final invLine = lines.firstWhere((l) => l.accountId == invAcc!.id);
      expect(invLine.credit, 300, reason: 'Inventory credit = COGS');
    });

    test('Credit sale with remaining balance posts AR', () async {
      await svc.generateSalesAccountingEntry(
        invoiceId: 2,
        invNumber: 'INV-T-002',
        tax: 0,
        paid: 400,
        remaining: 600,
        paymentMethod: 'cash',
        deliveryFee: 0,
        items: [
          const SalesInvoiceItem(
            id: 2, invoiceId: 2, productId: 1,
            quantity: 10, unitPrice: 100, discount: 0, total: 1000,
            costPrice: 50, sortOrder: 0, taxRate: 0, taxAmount: 0, quantityInBase: 10,
            rowVersion: 0,
          ),
        ],
      );

      final entries = await repo.getJournalEntries();
      expect(entries, hasLength(1));

      final lines = await (db.select(db.journalEntryLines)
        ..where((l) => l.entryId.equals(entries.first.id)))
        .get();

      // Verify AR line exists for remaining balance
      final arAcc = await repo.getAccountByCode('1121');
      expect(arAcc, isNotNull, reason: 'AR account (1121) must exist');

      final arLine = lines.firstWhere((l) => l.accountId == arAcc!.id);
      expect(arLine.debit, 600, reason: 'AR debit should be remaining amount');

      // Verify balance
      final totalDebit = lines.fold<double>(0, (s, l) => s + l.debit);
      final totalCredit = lines.fold<double>(0, (s, l) => s + l.credit);
      expect(totalDebit, totalCredit);
    });

    test('Sale with delivery fee credits sales account', () async {
      await svc.generateSalesAccountingEntry(
        invoiceId: 3,
        invNumber: 'INV-T-003',
        tax: 0,
        paid: 230,
        remaining: 0,
        paymentMethod: 'cash',
        deliveryFee: 30,
        items: [
          const SalesInvoiceItem(
            id: 3, invoiceId: 3, productId: 1,
            quantity: 2, unitPrice: 100, discount: 0, total: 200,
            costPrice: 0, sortOrder: 0, taxRate: 0, taxAmount: 0, quantityInBase: 2,
            rowVersion: 0,
          ),
        ],
      );

      final entries = await repo.getJournalEntries();
      expect(entries, hasLength(1));

      final lines = await (db.select(db.journalEntryLines)
        ..where((l) => l.entryId.equals(entries.first.id)))
        .get();

      // Delivery fee is credited to dedicated delivery revenue account (4102) if it exists,
      // otherwise it falls back to sales account (4101).
      final salesAcc = await repo.getAccountByCode('4121');
      final deliveryAcc = await repo.getAccountByCode('414');

      final salesLines = lines.where((l) => l.accountId == salesAcc!.id).toList();
      final deliveryLines = lines.where((l) => l.accountId == deliveryAcc?.id).toList();

      final salesCredit = salesLines.fold<double>(0, (s, l) => s + l.credit);
      final deliveryCredit = deliveryLines.fold<double>(0, (s, l) => s + l.credit);

      expect(salesCredit, 200, reason: 'Main sales revenue should be 200');
      expect(deliveryCredit, 30, reason: 'Delivery revenue should be 30 (H-09 implementation)');

      final totalDebit = lines.fold<double>(0, (s, l) => s + l.debit);
      final totalCredit = lines.fold<double>(0, (s, l) => s + l.credit);
      expect(totalDebit, totalCredit, reason: 'Entry must be balanced');
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Purchase Invoice Auto-Posting
  // ═══════════════════════════════════════════════════════════════

  group('Purchase Auto-Posting', () {
    test('Full cash purchase creates balanced journal entry', () async {
      await svc.generatePurchaseAccountingEntry(
        invoiceId: 100,
        subtotal: 5000,
        tax: 700, // 14%
        total: 5700,
        paid: 5700,
        remaining: 0,
        notes: 'فاتورة مشتريات #100',
      );

      final entries = await repo.getJournalEntries();
      expect(entries, hasLength(1));

      final lines = await (db.select(db.journalEntryLines)
        ..where((l) => l.entryId.equals(entries.first.id)))
        .get();

      // Verify balance
      final totalDebit = lines.fold<double>(0, (s, l) => s + l.debit);
      final totalCredit = lines.fold<double>(0, (s, l) => s + l.credit);
      expect(totalDebit, totalCredit, reason: 'Purchase entry must be balanced');

      // Verify accounts
      // Debit: Inventory 1103 = 5000, Input VAT 2202 = 700
      // Credit: Cash 1101 = 5700
      final invAcc = await repo.getAccountByCode('1136');
      final vatAcc = await repo.getAccountByCode('1141');
      final cashAcc = await repo.getAccountByCode('1111');

      expect(invAcc, isNotNull);
      expect(vatAcc, isNotNull);
      expect(cashAcc, isNotNull);

      final invLine = lines.firstWhere((l) => l.accountId == invAcc!.id);
      expect(invLine.debit, 5000, reason: 'Inventory debit = subtotal');

      final vatLine = lines.firstWhere((l) => l.accountId == vatAcc!.id);
      expect(vatLine.debit, 700, reason: 'Input VAT debit = tax');

      final cashLine = lines.firstWhere((l) => l.accountId == cashAcc!.id);
      expect(cashLine.credit, 5700, reason: 'Cash credit = paid');
    });

    test('Credit purchase with remaining posts payables', () async {
      await svc.generatePurchaseAccountingEntry(
        invoiceId: 101,
        subtotal: 3000,
        tax: 0,
        total: 3000,
        paid: 1000,
        remaining: 2000,
        notes: null,
      );

      final entries = await repo.getJournalEntries();
      expect(entries, hasLength(1));

      final lines = await (db.select(db.journalEntryLines)
        ..where((l) => l.entryId.equals(entries.first.id)))
        .get();

      // Verify payables
      final payAcc = await repo.getAccountByCode('2111');
      expect(payAcc, isNotNull, reason: 'Payables account (2111) must exist');

      final payLine = lines.firstWhere((l) => l.accountId == payAcc!.id);
      expect(payLine.credit, 2000, reason: 'Payables credit = remaining amount');

      // Verify balance
      final totalDebit = lines.fold<double>(0, (s, l) => s + l.debit);
      final totalCredit = lines.fold<double>(0, (s, l) => s + l.credit);
      expect(totalDebit, totalCredit, reason: 'Entry must be balanced');
    });

    test('Purchase with no tax skips VAT line', () async {
      await svc.generatePurchaseAccountingEntry(
        invoiceId: 102,
        subtotal: 800,
        tax: 0,
        total: 800,
        paid: 800,
        remaining: 0,
        notes: null,
      );

      final entries = await repo.getJournalEntries();
      final lines = await (db.select(db.journalEntryLines)
        ..where((l) => l.entryId.equals(entries.first.id)))
        .get();

      // Should NOT have a VAT line
      final vatAcc = await repo.getAccountByCode('1141');
      final vatLines = lines.where((l) => l.accountId == vatAcc?.id).toList();
      expect(vatLines, isEmpty, reason: 'No VAT line when tax is 0');

      // Should have exactly 2 lines: Inventory debit, Cash credit
      expect(lines, hasLength(2));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Edge Cases
  // ═══════════════════════════════════════════════════════════════

  group('Edge Cases', () {
    test('Zero-value sale creates no journal entry', () async {
      await svc.generateSalesAccountingEntry(
        invoiceId: 200,
        invNumber: 'INV-ZERO',
        tax: 0,
        paid: 0,
        remaining: 0,
        paymentMethod: 'cash',
        deliveryFee: 0,
        items: [],
      );

      final entries = await repo.getJournalEntries();
      expect(entries, isEmpty, reason: 'No journal entry for zero-value sale');
    });

    test('Bank payment uses account 1102 instead of 1101', () async {
      await svc.generateSalesAccountingEntry(
        invoiceId: 201,
        invNumber: 'INV-BANK',
        tax: 0,
        paid: 100,
        remaining: 0,
        paymentMethod: 'bank',
        deliveryFee: 0,
        items: [
          const SalesInvoiceItem(
            id: 201, invoiceId: 201, productId: 1,
            quantity: 1, unitPrice: 100, discount: 0, total: 100,
            costPrice: 0, sortOrder: 0, taxRate: 0, taxAmount: 0, quantityInBase: 1,
            rowVersion: 0,
          ),
        ],
      );

      final entries = await repo.getJournalEntries();
      final lines = await (db.select(db.journalEntryLines)
        ..where((l) => l.entryId.equals(entries.first.id)))
        .get();

      final bankAcc = await repo.getAccountByCode('1113');
      expect(bankAcc, isNotNull, reason: 'Bank account (1113) must exist');

      final bankLine = lines.where((l) => l.accountId == bankAcc!.id).toList();
      expect(bankLine, hasLength(1), reason: 'Bank debit line should exist');
      expect(bankLine.first.debit, 100);
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Throwing stubs — only IAccountingRepository is used in these tests.
// Others throw UnsupportedError if actually invoked.
// ═══════════════════════════════════════════════════════════════════════════

class _ThrowingPartiesRepo implements IPartiesRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError(
      'Stub: ${inv.memberName} not expected in auto-posting tests');
}

class _ThrowingTreasuryRepo implements ITreasuryRepository {
  @override
  Future<List<Map<String, dynamic>>> getSafeAccountsForReference(String referenceType, int referenceId) async => [];

  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError(
      'Stub: ${inv.memberName} not expected in auto-posting tests');
}

class _ThrowingProductRepo implements IProductRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError(
      'Stub: ${inv.memberName} not expected in auto-posting tests');
}

class _ThrowingInventoryRepo implements InventoryRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError(
      'Stub: ${inv.memberName} not expected in auto-posting tests');
}

class _ThrowingSettingsRepo implements ISettingsRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError(
      'Stub: ${inv.memberName} not expected in auto-posting tests');
}

class _ThrowingAuditRepo implements IAuditRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError(
      'Stub: ${inv.memberName} not expected in auto-posting tests');
}
