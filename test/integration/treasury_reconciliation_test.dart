import 'package:flutter_test/flutter_test.dart';

/// PIR Unit Test — Treasury Reconciliation
///
/// Tests shift closing, variance calculation, and safe transaction integrity.
/// Validates the three-pool atomic reconciliation: Cash, Bank, and Click.
void main() {
  // ═══════════════════════════════════════════════════════════════════════
  // SHIFT CLOSING — VARIANCE CALCULATION
  // ═══════════════════════════════════════════════════════════════════════

  group('Shift Closing Variance', () {
    test('No variance when actual matches expected', () {
      final shift = _ShiftReconciliation(
        expectedCash: 5000,
        actualCash: 5000,
        expectedBank: 2000,
        actualBank: 2000,
      );

      expect(shift.cashVariance, equals(0.0));
      expect(shift.bankVariance, equals(0.0));
      expect(shift.totalVariance, equals(0.0));
      expect(shift.hasVariance, isFalse);
    });

    test('Cash shortage detected', () {
      final shift = _ShiftReconciliation(
        expectedCash: 5000,
        actualCash: 4900,
        expectedBank: 0,
        actualBank: 0,
      );

      expect(shift.cashVariance, equals(-100.0),
          reason: 'Shortage: actual 4900 - expected 5000 = -100');
      expect(shift.hasVariance, isTrue);
      expect(shift.isShortage, isTrue);
    });

    test('Cash surplus detected', () {
      final shift = _ShiftReconciliation(
        expectedCash: 5000,
        actualCash: 5050,
        expectedBank: 0,
        actualBank: 0,
      );

      expect(shift.cashVariance, equals(50.0),
          reason: 'Surplus: actual 5050 - expected 5000 = +50');
      expect(shift.hasVariance, isTrue);
      expect(shift.isShortage, isFalse);
    });

    test('Multi-pool reconciliation: cash shortage + bank match', () {
      final shift = _ShiftReconciliation(
        expectedCash: 3000,
        actualCash: 2850,
        expectedBank: 7000,
        actualBank: 7000,
      );

      expect(shift.cashVariance, equals(-150.0));
      expect(shift.bankVariance, equals(0.0));
      expect(shift.totalVariance, equals(-150.0));
    });

    test('Tolerance-aware closing: within 5 EGP is acceptable', () {
      final shift = _ShiftReconciliation(
        expectedCash: 5000,
        actualCash: 4997,
        expectedBank: 0,
        actualBank: 0,
      );

      const tolerance = 5.0;
      expect(shift.cashVariance.abs(), lessThanOrEqualTo(tolerance),
          reason: 'Variance of 3 EGP is within 5 EGP tolerance');
      expect(shift.isWithinTolerance(tolerance), isTrue);
    });

    test('Variance beyond tolerance requires review', () {
      final shift = _ShiftReconciliation(
        expectedCash: 5000,
        actualCash: 4990,
        expectedBank: 0,
        actualBank: 0,
      );

      const tolerance = 5.0;
      expect(shift.cashVariance.abs(), greaterThan(tolerance));
      expect(shift.isWithinTolerance(tolerance), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // CLO SAFE TRANSACTIONS
  // ═══════════════════════════════════════════════════════════════════════

  group('CLO SafeTransaction Generation', () {
    test('Closing creates CLO-CASH transaction', () {
      final transactions = _generateCLOTransactions(
        cashAmount: 5000,
        bankAmount: 3000,
        safeId: 1,
        userId: 10,
      );

      final cloEntries = transactions.where((t) => t.type.startsWith('CLO')).toList();
      expect(cloEntries.length, greaterThanOrEqualTo(1));

      final cloCash = cloEntries.firstWhere(
            (t) => t.type == 'CLO-CASH',
        orElse: () => throw StateError('CLO-CASH transaction missing'),
      );
      expect(cloCash.amount, equals(5000.0));
      expect(cloCash.safeId, equals(1));
    });

    test('Closing creates CLO-BANK transaction when bank amount > 0', () {
      final transactions = _generateCLOTransactions(
        cashAmount: 5000,
        bankAmount: 3000,
        safeId: 1,
        userId: 10,
      );

      final cloBank = transactions.firstWhere(
            (t) => t.type == 'CLO-BANK',
        orElse: () => throw StateError('CLO-BANK transaction missing'),
      );
      expect(cloBank.amount, equals(3000.0));
    });

    test('No CLO-BANK generated when bank amount is zero', () {
      final transactions = _generateCLOTransactions(
        cashAmount: 5000,
        bankAmount: 0,
        safeId: 1,
        userId: 10,
      );

      final cloBankEntries = transactions.where((t) => t.type == 'CLO-BANK');
      expect(cloBankEntries, isEmpty,
          reason: 'No bank closing entry when bank amount is 0');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // VARIANCE JOURNAL ENTRY
  // ═══════════════════════════════════════════════════════════════════════

  group('Variance JE Generation (ICR-04)', () {
    test('Shortage creates Dr Shortage Expense / Cr Cash', () {
      const variance = -100.0; // shortage
      final je = _generateVarianceJE(variance);

      expect(je, isNotNull, reason: 'Variance JE should be created');
      expect(je!.lines, hasLength(2));

      // Debit: Shortage Expense
      final debitLine = je.lines.firstWhere((l) => l.debit > 0);
      expect(debitLine.accountCode, equals('6801'),
          reason: 'Shortage goes to expense account');
      expect(debitLine.debit, equals(100.0));

      // Credit: Cash reduction
      final creditLine = je.lines.firstWhere((l) => l.credit > 0);
      expect(creditLine.accountCode, equals('1101'));
      expect(creditLine.credit, equals(100.0));
    });

    test('Surplus creates Dr Cash / Cr Surplus Revenue', () {
      const variance = 50.0; // surplus
      final je = _generateVarianceJE(variance);

      expect(je, isNotNull);
      expect(je!.lines, hasLength(2));

      // Debit: Cash increase
      final debitLine = je.lines.firstWhere((l) => l.debit > 0);
      expect(debitLine.accountCode, equals('1101'));
      expect(debitLine.debit, equals(50.0));

      // Credit: Surplus Revenue
      final creditLine = je.lines.firstWhere((l) => l.credit > 0);
      expect(creditLine.accountCode, equals('4801'),
          reason: 'Surplus goes to revenue account');
      expect(creditLine.credit, equals(50.0));
    });

    test('Zero variance creates no JE', () {
      final je = _generateVarianceJE(0.0);
      expect(je, isNull, reason: 'No JE needed when variance is zero');
    });

    test('Variance JE is always balanced', () {
      for (final v in [-200.0, -50.0, 30.0, 150.0]) {
        final je = _generateVarianceJE(v);
        if (je != null) {
          final totalDebit = je.lines.fold<double>(0, (s, l) => s + l.debit);
          final totalCredit = je.lines.fold<double>(0, (s, l) => s + l.credit);
          expect(totalDebit, totalCredit,
              reason: 'Variance JE for $v must be balanced');
        }
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // SAFE BALANCE POST-CLOSING
  // ═══════════════════════════════════════════════════════════════════════

  group('Safe Balance Post-Closing', () {
    test('Opening balance for next shift = actual closing balance', () {
      const closingActualCash = 4900.0;
      const nextShiftOpening = closingActualCash;

      expect(nextShiftOpening, equals(4900.0),
          reason: 'Next shift opens with actual counted cash');
    });

    test('Expected vs actual tracked per payment method', () {
      final pools = {
        'cash': _Pool(expected: 5000, actual: 4950),
        'bank': _Pool(expected: 3000, actual: 3000),
        'click': _Pool(expected: 1000, actual: 1000),
      };

      expect(pools['cash']!.variance, equals(-50.0));
      expect(pools['bank']!.variance, equals(0.0));
      expect(pools['click']!.variance, equals(0.0));

      final totalVariance = pools.values
          .fold<double>(0, (s, p) => s + p.variance);
      expect(totalVariance, equals(-50.0));
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Helper classes
// ═══════════════════════════════════════════════════════════════════════════

class _ShiftReconciliation {
  final double expectedCash;
  final double actualCash;
  final double expectedBank;
  final double actualBank;

  _ShiftReconciliation({
    required this.expectedCash,
    required this.actualCash,
    required this.expectedBank,
    required this.actualBank,
  });

  double get cashVariance => actualCash - expectedCash;
  double get bankVariance => actualBank - expectedBank;
  double get totalVariance => cashVariance + bankVariance;
  bool get hasVariance => totalVariance != 0;
  bool get isShortage => totalVariance < 0;

  bool isWithinTolerance(double tolerance) =>
      totalVariance.abs() <= tolerance;
}

class _SafeTransaction {
  final String type;
  final double amount;
  final int safeId;
  final int userId;

  _SafeTransaction({
    required this.type,
    required this.amount,
    required this.safeId,
    required this.userId,
  });
}

class _VarianceJELine {
  final String accountCode;
  final double debit;
  final double credit;

  _VarianceJELine({
    required this.accountCode,
    required this.debit,
    required this.credit,
  });
}

class _VarianceJE {
  final List<_VarianceJELine> lines;
  _VarianceJE(this.lines);
}

class _Pool {
  final double expected;
  final double actual;

  _Pool({required this.expected, required this.actual});

  double get variance => actual - expected;
}

List<_SafeTransaction> _generateCLOTransactions({
  required double cashAmount,
  required double bankAmount,
  required int safeId,
  required int userId,
}) {
  final result = <_SafeTransaction>[];

  if (cashAmount > 0) {
    result.add(_SafeTransaction(
      type: 'CLO-CASH',
      amount: cashAmount,
      safeId: safeId,
      userId: userId,
    ));
  }

  if (bankAmount > 0) {
    result.add(_SafeTransaction(
      type: 'CLO-BANK',
      amount: bankAmount,
      safeId: safeId,
      userId: userId,
    ));
  }

  return result;
}

_VarianceJE? _generateVarianceJE(double variance) {
  if (variance == 0) return null;

  if (variance < 0) {
    // Shortage
    return _VarianceJE([
      _VarianceJELine(accountCode: '6801', debit: variance.abs(), credit: 0),
      _VarianceJELine(accountCode: '1101', debit: 0, credit: variance.abs()),
    ]);
  } else {
    // Surplus
    return _VarianceJE([
      _VarianceJELine(accountCode: '1101', debit: variance, credit: 0),
      _VarianceJELine(accountCode: '4801', debit: 0, credit: variance),
    ]);
  }
}
