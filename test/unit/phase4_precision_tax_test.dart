import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/utils/financial_utils.dart';
import 'package:ural_erp/domain/models/purchase_line_discount.dart';
import 'package:ural_erp/services/journal_entry_factory.dart';
import 'package:ural_erp/domain/repositories/accounting_repository.dart';
import 'package:ural_erp/domain/repositories/parties_repository.dart';
import 'package:ural_erp/domain/repositories/i_products_repository.dart';
import 'package:ural_erp/domain/repositories/inventory_repository.dart';
import 'package:ural_erp/domain/repositories/audit_repository_interface.dart';
import 'package:ural_erp/domain/repositories/treasury_repository.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  group('Phase 4 precision and tax engine', () {
    test('rounding is stable around binary floating point boundaries', () {
      for (final value in <double>[0.005, 1.005, 2.675, -1.005, 1000000.005]) {
        expect(FinancialUtils.round(value), value,
            reason: 'value $value must retain configured currency precision');
      }
    });

    test('allocates invoice discount remainder to one line', () {
      final result = FinancialUtils.calculateInvoiceTotals(
        items: [
          (quantity: 1, unitPrice: 33.335, taxRatePercent: 15),
          (quantity: 1, unitPrice: 33.335, taxRatePercent: 15),
          (quantity: 1, unitPrice: 33.33, taxRatePercent: 0),
        ],
        globalDiscountAmount: 1,
      );
      expect(result.lineNets.fold<double>(0, (s, v) => s + v),
          result.subtotal - result.totalDiscount);
      expect(result.totalTax, 9.9);
    });

    test('sales invoice discount allocates rounded nets and taxes on net', () {
      final result = FinancialUtils.calculateInvoiceTotals(
        items: [
          (quantity: 1, unitPrice: 33.335, taxRatePercent: 15),
          (quantity: 1, unitPrice: 33.335, taxRatePercent: 15),
          (quantity: 1, unitPrice: 33.33, taxRatePercent: 0),
        ],
        globalDiscountAmount: 1,
      );
      expect(result.lineNets.fold<double>(0, (sum, value) => sum + value),
          result.subtotal - result.totalDiscount);
      expect(result.totalTax,
          result.lineNets.asMap().entries.fold<double>(
              0, (sum, entry) => sum + FinancialUtils.round(entry.value *
                  ([15, 15, 0][entry.key] / 100))));
    });

    test('purchase discount allocation reconciles rounded lines', () {
      final lines = resolvePurchaseLineNets(
        grossPerLine: [33.335, 33.335, 33.33],
        explicitDiscountPerLine: [0, 0, 0],
        documentDiscount: 1,
      );
      expect(lines.fold<double>(0, (sum, value) => sum + value), 99.0);
    });

    test('payroll net salary uses currency rounding', () {
      const gross = 100.0044;
      const deductions = 0.0001;
      const advances = 0.0001;
      final netSalary = FinancialUtils.round(gross - deductions - advances);
      expect(netSalary, 100.004);
    });

    test('tax-inclusive prices reconcile gross, net, and tax', () {
      final result = FinancialUtils.calculateInvoiceTotals(
        items: [
          (quantity: 1, unitPrice: 115, taxRatePercent: 15),
          (quantity: 1, unitPrice: 57.5, taxRatePercent: 15),
        ],
        pricesIncludeTax: true,
      );
      final gross = [115.0, 57.5];
      for (var i = 0; i < gross.length; i++) {
        expect(result.lineNets[i] + result.lineTaxes[i], gross[i]);
      }
      expect(result.grandTotal, 172.5);
    });

    test('sales posting rejects paid and remaining that do not equal total', () async {
      final factory = _buildPhase4Factory();

      expect(
        () => factory.generateSalesAccountingEntry(
          invoiceId: 10,
          invNumber: 'SALE-MISMATCH',
          tax: 0,
          paid: 99.99,
          remaining: 0,
          invoiceTotal: 100,
          paymentMethod: 'cash',
          deliveryFee: 0,
          items: [],
        ),
        throwsA(
          predicate<Object>((error) =>
              error.toString().contains('عدم اتساق فاتورة المبيعات')),
        ),
      );
    });

    test('taxable sales posting rejects unmapped output VAT', () async {
      final factory = _buildPhase4Factory(includeOutputVat: false);

      expect(
        () => factory.generateSalesAccountingEntry(
          invoiceId: 11,
          invNumber: 'SALE-NO-VAT-MAPPING',
          tax: 10,
          paid: 110,
          remaining: 0,
          invoiceTotal: 110,
          paymentMethod: 'cash',
          deliveryFee: 0,
          items: [],
        ),
        throwsA(
          predicate<Object>((error) =>
              error.toString().contains('output_vat')),
        ),
      );
    });

    test('purchase discount posting is balanced and includes purchase discount',
        () async {
      final accountingRepo = _Phase4AccountingRepo(
        purposeMap: _phase4PurposeMap(includeOutputVat: true),
      );
      final factory = _buildPhase4FactoryFrom(accountingRepo);

      await factory.generatePurchaseAccountingEntry(
        invoiceId: 12,
        subtotal: 100,
        discount: 10,
        tax: 9,
        total: 99,
        paid: 99,
        remaining: 0,
        notes: 'شراء مع خصم',
      );

      final lines = accountingRepo.capturedLines.single;
      final debit = lines.fold<double>(0, (sum, line) => sum + line.debit);
      final credit = lines.fold<double>(0, (sum, line) => sum + line.credit);
      expect((debit - credit).abs(), lessThan(0.001));
      expect(lines.any((line) => line.accountId == 11), isTrue);
    });

    test('purchase posting rejects subtotal discount tax mismatch', () async {
      final factory = _buildPhase4Factory();

      expect(
        () => factory.generatePurchaseAccountingEntry(
          invoiceId: 13,
          subtotal: 100,
          discount: 10,
          tax: 9,
          total: 99,
          paid: 98,
          remaining: 0,
          notes: 'شراء غير متسق',
        ),
        throwsA(
          predicate<Object>((error) =>
              error.toString().contains('عدم اتساق فاتورة المشتريات')),
        ),
      );
    });

    test('FinancialUtils.round handles requested precision boundaries', () {
      // The project currency uses 3 minor-unit digits (decimalPlaces = 3,
      // see FinancialUtils.toMinorUnits docs), so the half-way boundaries are
      // at the 4th decimal. Values already at 3 dp must stay unchanged.
      expect(FinancialUtils.round(0.005), 0.005);
      expect(FinancialUtils.round(0.0005), 0.001);
      expect(FinancialUtils.round(1.0005), 1.001);
      expect(FinancialUtils.round(2.6745), 2.675);
      expect(FinancialUtils.round(-1.0005), -1.001);
      expect(FinancialUtils.round(1000000.0005), 1000000.001);
    });
  });
}

JournalEntryFactory _buildPhase4Factory({bool includeOutputVat = true}) {
  return _buildPhase4FactoryFrom(
    _Phase4AccountingRepo(
      purposeMap: _phase4PurposeMap(includeOutputVat: includeOutputVat),
    ),
  );
}

JournalEntryFactory _buildPhase4FactoryFrom(_Phase4AccountingRepo repo) {
  return JournalEntryFactory(
    repo,
    _Phase4PartiesRepo(),
    _Phase4TreasuryRepo(),
    _Phase4ProductRepo(),
    _Phase4InventoryRepo(),
    _Phase4AuditRepo(),
  );
}

Map<String, Account> _phase4PurposeMap({required bool includeOutputVat}) => {
      'cash': _phase4Account(1, 'النقدية'),
      'bank': _phase4Account(2, 'البنك'),
      'receivables': _phase4Account(3, 'العملاء'),
      'cogs': _phase4Account(4, 'تكلفة المبيعات'),
      'sales': _phase4Account(5, 'المبيعات'),
      if (includeOutputVat) 'output_vat': _phase4Account(6, 'ضريبة المخرجات'),
      'inventory': _phase4Account(7, 'المخزون'),
      'input_vat': _phase4Account(8, 'ضريبة المدخلات'),
      'payables': _phase4Account(9, 'الموردين'),
      'purchase_discount': _phase4Account(11, 'خصم المشتريات'),
    };

Account _phase4Account(int id, String name) => Account(
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

class _Phase4AccountingRepo implements IAccountingRepository {
  final Map<String, Account> purposeMap;
  final List<List<JournalLine>> capturedLines = [];

  _Phase4AccountingRepo({required this.purposeMap});

  @override
  Future<Account?> getAccountByPurpose(String purpose, {int? costCenterId}) async =>
      purposeMap[purpose];

  @override
  Future<Account?> getLeafAccountByPurpose(String purpose, {int? costCenterId}) async =>
      purposeMap[purpose];

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
    bool asDraft = false,
    int? createdBy,
    String? reference,
  }) async {
    capturedLines.add(lines);
    return capturedLines.length;
  }

  @override
  Future<FiscalYearData?> getFiscalYearByDate(DateTime date) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Phase4PartiesRepo implements IPartiesRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Phase4TreasuryRepo implements ITreasuryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName.toString().contains('getSafeAccountsForReference')) {
      return Future<List<Map<String, dynamic>>>.value([]);
    }
    return null;
  }
}

class _Phase4ProductRepo implements IProductRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Phase4InventoryRepo implements InventoryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Phase4AuditRepo implements IAuditRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
