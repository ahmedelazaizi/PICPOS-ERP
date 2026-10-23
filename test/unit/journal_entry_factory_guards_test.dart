// ═══════════════════════════════════════════════════════════════════════════
// PIR PHASE 0 — JournalEntryFactory Guard Tests
// ═══════════════════════════════════════════════════════════════════════════
//
// Tests for ISS-01 (balance validation), ISS-02 (account guard),
// ISS-04 (purchase payment method), ISS-05 (costPrice warning),
// ISS-10 (period lock).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/journal_entry_factory.dart';
import 'package:picpos_erp/domain/repositories/accounting_repository.dart';
import 'package:picpos_erp/domain/repositories/parties_repository.dart';
import 'package:picpos_erp/domain/repositories/i_products_repository.dart';
import 'package:picpos_erp/domain/repositories/inventory_repository.dart';
import 'package:picpos_erp/domain/repositories/audit_repository_interface.dart';
import 'package:picpos_erp/domain/repositories/treasury_repository.dart';
import 'package:picpos_erp/data/database/database.dart';

// ── Minimal Mock for IAccountingRepository ──────────────────────────────

class _MockAccountingRepo implements IAccountingRepository {
  /// Map of purpose -> Account.  If a purpose is absent, getAccountByPurpose returns null.
  final Map<String, Account> purposeMap;
  final Map<String, Account> codeMap = const {};
  final bool periodClosed;

  /// Captured journal entries for verification
  final List<_CapturedJE> capturedEntries = [];

  _MockAccountingRepo({
    this.purposeMap = const {},
    this.periodClosed = false,
  });

  @override
  Future<Account?> getAccountByPurpose(String purpose, {int? costCenterId}) async =>
      purposeMap[purpose];

  /// Added 2026-05-15: matches the new IAccountingRepository method
  /// (accounting_repository.dart:79). Mock semantics same as
  /// getAccountByPurpose — the purpose→account map already represents
  /// "the leaf account for this purpose" for test fixtures.
  @override
  Future<Account?> getLeafAccountByPurpose(String purpose, {int? costCenterId}) async =>
      purposeMap[purpose];

  @override
  Future<Account?> getAccountByCode(String code) async => codeMap[code];

  @override
  Future<int> createJournalEntry({
    required String description,
    required DateTime date,
    required List<JournalLine> lines,
    String? referenceType,
    int? referenceId,
    bool isAutoPosted = false,
    int? costCenterId,
    int? branchId,
    // القيدُ الآليُّ لا يكون مسودّةً ولا منشئَ له — والمُعامِلان هنا
    // للمطابقة وحدَها.
    bool asDraft = false,
    int? createdBy,
    // v174: «المرجع» صار يُكتَب من سند القيد — راجع الواجهة.
    String? reference,
  }) async {
    capturedEntries.add(_CapturedJE(
      description: description,
      lines: lines,
      referenceType: referenceType,
    ));
    return capturedEntries.length;
  }

  @override
  Future<FiscalYearData?> getFiscalYearByDate(DateTime date) async {
    if (periodClosed) {
      // Return a FiscalYearData with isClosed = true
      return FiscalYearData(
        id: 1,
        name: '2026',
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 12, 31),
        isClosed: true,
        isCurrent: false,
        createdAt: DateTime.now(),
        rowVersion: 0,
      );
    }
    return null; // No fiscal year setup
  }

  // ── Stubs for remaining interface methods ──
  @override dynamic noSuchMethod(Invocation invocation) => null;
}

class _CapturedJE {
  final String description;
  final List<JournalLine> lines;
  final String? referenceType;
  _CapturedJE({required this.description, required this.lines, this.referenceType});
}

// Minimal stubs for other repositories
class _StubPartiesRepo implements IPartiesRepository {
  @override dynamic noSuchMethod(Invocation invocation) => null;
}
class _StubTreasuryRepo implements ITreasuryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    // Methods returning Future<List<...>> need an empty list, not null
    final memberName = invocation.memberName.toString();
    if (memberName.contains('getSafeAccountsForReference') ||
        memberName.contains('getTransactions')) {
      return Future<List<Map<String, dynamic>>>.value([]);
    }
    return null;
  }
}
class _StubProductRepo implements IProductRepository {
  @override dynamic noSuchMethod(Invocation invocation) => null;
}
class _StubInventoryRepo implements InventoryRepository {
  @override dynamic noSuchMethod(Invocation invocation) => null;
}
class _StubAuditRepo implements IAuditRepository {
  @override dynamic noSuchMethod(Invocation invocation) => null;
}

/// Helper: create an Account with given id and name
Account _makeAccount(int id, String name) => Account(
      id: id,
      code: '$id',
      name: name,
      accountType: 'asset',
      accountNature: 'debit',
      normalBalance: 'debit',
      level: 1,
      balance: 0,
      isSystem: false,
      isActive: true,
      isHiddenFromEntries: false,
      rowVersion: 0,
    );

/// Helper: full purpose map for sales flow
Map<String, Account> _fullSalesPurposeMap() => {
      'cash': _makeAccount(1, 'النقدية'),
      'bank': _makeAccount(2, 'البنك'),
      'receivables': _makeAccount(3, 'العملاء'),
      'cogs': _makeAccount(4, 'تكلفة المبيعات'),
      'sales': _makeAccount(5, 'المبيعات'),
      'output_vat': _makeAccount(6, 'ضريبة المخرجات'),
      'inventory': _makeAccount(7, 'المخزون'),
      'input_vat': _makeAccount(8, 'ضريبة المدخلات'),
      'payables': _makeAccount(9, 'الموردين'),
      'sales_return': _makeAccount(10, 'مرتجع المبيعات'),
    };

void main() {
  late _MockAccountingRepo accountingRepo;
  late JournalEntryFactory factory;

  JournalEntryFactory buildFactory(_MockAccountingRepo repo) {
    return JournalEntryFactory(
      repo,
      _StubPartiesRepo(),
      _StubTreasuryRepo(),
      _StubProductRepo(),
      _StubInventoryRepo(),
      _StubAuditRepo(),
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // ISS-02: MissingAccountException
  // ───────────────────────────────────────────────────────────────────────
  group('ISS-02: Account-not-found guard', () {
    test('throws MissingAccountException when cash account is not mapped', () async {
      accountingRepo = _MockAccountingRepo(purposeMap: {});
      factory = buildFactory(accountingRepo);

      expect(
        () => factory.generateSalesAccountingEntry(
          invoiceId: 1,
          invNumber: 'INV001',
          tax: 0,
          paid: 100,
          remaining: 0,
          invoiceTotal: 100,
          paymentMethod: 'cash',
          deliveryFee: 0,
          items: [],
        ),
        throwsA(isA<MissingAccountException>()),
      );
    });

    test('throws MissingAccountException when sales account is not mapped', () async {
      accountingRepo = _MockAccountingRepo(purposeMap: {
        'cash': _makeAccount(1, 'النقدية'),
      });
      factory = buildFactory(accountingRepo);

      expect(
        () => factory.generateSalesAccountingEntry(
          invoiceId: 1,
          invNumber: 'INV001',
          tax: 0,
          paid: 100,
          remaining: 0,
          invoiceTotal: 100,
          paymentMethod: 'cash',
          deliveryFee: 0,
          items: [],
        ),
        throwsA(isA<MissingAccountException>()),
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // ISS-01: Balance validation
  // ───────────────────────────────────────────────────────────────────────
  group('ISS-01: JE Balance validation', () {
    test('creates balanced JE successfully', () async {
      accountingRepo = _MockAccountingRepo(purposeMap: _fullSalesPurposeMap());
      factory = buildFactory(accountingRepo);

      await factory.generateSalesAccountingEntry(
        invoiceId: 1,
        invNumber: 'INV001',
        tax: 14,
        paid: 114,
        remaining: 0,
        paymentMethod: 'cash',
        deliveryFee: 0,
        items: [
          // Simulate a SalesInvoiceItem with costPrice = 50
          _FakeSalesItem(productId: 1, quantity: 1, costPrice: 50),
        ],
        costCenterId: null,
      );

      expect(accountingRepo.capturedEntries.length, 1);
      final je = accountingRepo.capturedEntries.first;
      final totalDebit = je.lines.fold<double>(0, (s, l) => s + l.debit);
      final totalCredit = je.lines.fold<double>(0, (s, l) => s + l.credit);
      expect((totalDebit - totalCredit).abs(), lessThan(0.01));
    });

    test('Spec 136 — inconsistent invoice (total ≠ subtotal+tax) still BALANCES',
        () async {
      accountingRepo = _MockAccountingRepo(purposeMap: _fullSalesPurposeMap());
      factory = buildFactory(accountingRepo);

      // Field case (2026-06-08): the invoice numbers do NOT reconcile — paid
      // carries more than subtotal+tax. Pre-fix the JE was off by exactly the
      // tax ("خطأ في قيد اليومية: المدين لا يساوي الدائن") and the sale
      // dead-lettered. The net-sales credit derived from total must keep it
      // balanced.
      await factory.generateSalesAccountingEntry(
        invoiceId: 2,
        invNumber: 'INV-INCONSISTENT',
        tax: 14,
        paid: 120, // deliberately inconsistent total — net-from-total must still balance
        remaining: 0,
        paymentMethod: 'cash',
        deliveryFee: 0,
        items: [_FakeSalesItem(productId: 1, quantity: 1, costPrice: 50)],
        costCenterId: null,
      );

      expect(accountingRepo.capturedEntries.length, 1,
          reason: 'inconsistent invoice must still post (no imbalance throw)');
      final je = accountingRepo.capturedEntries.first;
      final d = je.lines.fold<double>(0, (s, l) => s + l.debit);
      final c = je.lines.fold<double>(0, (s, l) => s + l.credit);
      expect((d - c).abs(), lessThan(0.01),
          reason: 'JE must balance by construction (Dr=$d, Cr=$c)');
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // ISS-04: Purchase payment method routing
  // ───────────────────────────────────────────────────────────────────────
  group('ISS-04: Purchase JE payment method', () {
    test('routes payment to bank account when paymentMethod is bank', () async {
      accountingRepo = _MockAccountingRepo(purposeMap: _fullSalesPurposeMap());
      factory = buildFactory(accountingRepo);

      await factory.generatePurchaseAccountingEntry(
        invoiceId: 1,
        subtotal: 200,
        tax: 28,
        total: 228,
        paid: 228,
        remaining: 0,
        notes: 'شراء بضاعة',
        paymentMethod: 'bank', // ISS-04: should use bank account
      );

      expect(accountingRepo.capturedEntries.length, 1);
      final je = accountingRepo.capturedEntries.first;
      // Verify the credit line uses the bank account (id = 2)
      final creditLines = je.lines.where((l) => l.credit > 0).toList();
      expect(creditLines.any((l) => l.accountId == 2), isTrue,
          reason: 'Should credit bank account (id=2) for bank payment');
    });

    test('routes payment to cash account by default', () async {
      accountingRepo = _MockAccountingRepo(purposeMap: _fullSalesPurposeMap());
      factory = buildFactory(accountingRepo);

      await factory.generatePurchaseAccountingEntry(
        invoiceId: 2,
        subtotal: 100,
        tax: 0,
        total: 100,
        paid: 100,
        remaining: 0,
        notes: null,
        // paymentMethod defaults to 'cash'
      );

      expect(accountingRepo.capturedEntries.length, 1);
      final je = accountingRepo.capturedEntries.first;
      final creditLines = je.lines.where((l) => l.credit > 0).toList();
      expect(creditLines.any((l) => l.accountId == 1), isTrue,
          reason: 'Should credit cash account (id=1) by default');
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // ISS-10: Period lock
  // ───────────────────────────────────────────────────────────────────────
  group('ISS-10: Period lock enforcement', () {
    test('throws PeriodLockedException when fiscal year is closed', () async {
      accountingRepo = _MockAccountingRepo(
        purposeMap: _fullSalesPurposeMap(),
        periodClosed: true,
      );
      factory = buildFactory(accountingRepo);

      expect(
        () => factory.generateSalesAccountingEntry(
          invoiceId: 1,
          invNumber: 'INV001',
          tax: 0,
          paid: 100,
          remaining: 0,
          invoiceTotal: 100,
          paymentMethod: 'cash',
          deliveryFee: 0,
          items: [],
        ),
        throwsA(isA<PeriodLockedException>()),
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // Exception classes
  // ───────────────────────────────────────────────────────────────────────
  group('Exception message formatting', () {
    test('MissingAccountException has readable message', () {
      final e = MissingAccountException('cash');
      expect(e.toString(), contains('cash'));
      expect(e.toString(), contains('MissingAccountException'));
    });

    test('UnbalancedJournalException has debit/credit info', () {
      final e = UnbalancedJournalException(100.0, 90.0, 'test');
      expect(e.toString(), contains('100'));
      expect(e.toString(), contains('90'));
      expect(e.toString(), contains('10'));
    });

    test('PeriodLockedException has date info', () {
      final date = DateTime(2026, 1, 15);
      final e = PeriodLockedException(date);
      expect(e.toString(), contains('2026'));
    });
  });
}

// ── Fake SalesInvoiceItem for testing ───────────────────────────────────

class _FakeSalesItem implements SalesInvoiceItem {
  @override final int productId;
  @override final double quantity;
  @override final double costPrice;
  // SAL-1: journal_entry_factory now reads quantityInBase (non-nullable on
  // the real SalesInvoiceItem, DB default 1.0) when computing COGS. Without
  // an explicit override here, noSuchMethod would return null and the
  // multiplication in generateSalesAccountingEntry would throw.
  @override final double quantityInBase = 1.0;

  _FakeSalesItem({
    required this.productId,
    required this.quantity,
    required this.costPrice,
  });

  // Stubs for remaining SalesInvoiceItem fields
  @override dynamic noSuchMethod(Invocation invocation) => null;
}
