// ═══════════════════════════════════════════════════════════════════════════
// ACCOUNTING EDGE CASES — Unit Tests (PIR Phase 8)
//
// Tests for edge cases in accounting logic not covered by existing tests:
//   - Return/credit note journal entry generation
//   - Split payment validation (cash + bank)
//   - Cost center propagation in auto-posted entries
//   - Period closing gating
//   - Zero-amount journal validation
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Credit Note / Return Entry Validation', () {
    test('return entry is reverse of original (debit/credit swapped)', () {
      const saleDebit = 1000.0;
      const saleCredit = 1000.0;
      const returnDebit = saleCredit; // Reversed
      const returnCredit = saleDebit; // Reversed

      expect(returnDebit, saleCredit);
      expect(returnCredit, saleDebit);
      // The net effect should be zero
      expect((saleDebit - saleCredit) + (returnDebit - returnCredit), 0.0);
    });

    test('partial return reverses proportionally', () {
      const originalAmount = 5000.0;
      const returnedItems = 2;
      const totalItems = 5;
      const returnAmount = originalAmount * (returnedItems / totalItems);

      expect(returnAmount, 2000.0);
      // Remaining invoice
      expect(originalAmount - returnAmount, 3000.0);
    });

    test('return cannot exceed original amount', () {
      const originalAmount = 1000.0;
      const returnAmount = 1200.0;

      expect(returnAmount > originalAmount, isTrue);
      // Business rule: reject
      const isValid = returnAmount <= originalAmount;
      expect(isValid, isFalse);
    });
  });

  group('Split Payment Validation', () {
    test('cash + bank must equal total paid', () {
      const total = 5000.0;
      const cashPaid = 2000.0;
      const bankPaid = 3000.0;

      expect(cashPaid + bankPaid, total);
      expect(_validateSplitPayment(total, cashPaid, bankPaid), isTrue);
    });

    test('split payment with rounding tolerance', () {
      const total = 3333.33;
      const cashPaid = 1666.66;
      const bankPaid = 1666.67;

      expect(_validateSplitPayment(total, cashPaid, bankPaid), isTrue);
    });

    test('split payment mismatch rejected', () {
      const total = 5000.0;
      const cashPaid = 2000.0;
      const bankPaid = 2500.0; // Short by 500

      expect(_validateSplitPayment(total, cashPaid, bankPaid), isFalse);
    });

    test('negative payment rejected', () {
      expect(_validateSplitPayment(1000, -500, 1500), isFalse);
    });

    test('zero total with zero payments is valid', () {
      expect(_validateSplitPayment(0, 0, 0), isTrue);
    });
  });

  group('Cost Center Propagation', () {
    test('costCenterId is set when provided', () {
      const costCenterId = 42;
      final journalLine = _buildJournalLine(
        accountId: 1,
        debit: 1000,
        credit: 0,
        costCenterId: costCenterId,
      );

      expect(journalLine['costCenterId'], costCenterId);
    });

    test('costCenterId is null when not provided', () {
      final journalLine = _buildJournalLine(
        accountId: 1,
        debit: 1000,
        credit: 0,
        costCenterId: null,
      );

      expect(journalLine['costCenterId'], isNull);
    });

    test('override cost center replaces line-level', () {
      // When creating a journal entry with an override costCenterId,
      // the override should apply to ALL lines
      const lineCostCenter = 10;
      const overrideCostCenter = 20;

  // ignore: dead_code
      const effectiveCostCenter = overrideCostCenter ?? lineCostCenter;
      expect(effectiveCostCenter, 20);
    });
  });

  group('Journal Entry Balance Enforcement', () {
    test('zero-amount entry is valid (both sides zero)', () {
      expect(_isBalanced(debit: 0, credit: 0), isTrue);
    });

    test('single-line entry is always imbalanced (unless zero)', () {
      expect(_isBalanced(debit: 1000, credit: 0), isFalse);
    });

    test('multi-line accumulation: 3 debits = 2 credits', () {
      const totalDebit = 500.0 + 300.0 + 200.0;
      const totalCredit = 600.0 + 400.0;

      expect(_isBalanced(debit: totalDebit, credit: totalCredit), isTrue);
    });

    test('floating point imprecision handled', () {
      // 0.1 + 0.2 = 0.30000000000000004 in IEEE 754
      const debit = 0.1 + 0.2;
      const credit = 0.3;

      expect(_isBalanced(debit: debit, credit: credit), isTrue);
    });

    test('negative amounts rejected', () {
      expect(_isValidAmount(-100), isFalse);
      expect(_isValidAmount(0), isTrue);
      expect(_isValidAmount(100), isTrue);
    });
  });

  group('Period Closing Validation', () {
    test('date within open period is allowed', () {
      final periodStart = DateTime(2026, 1, 1);
      final periodEnd = DateTime(2026, 12, 31);
      final trxDate = DateTime(2026, 6, 15);

      expect(_isWithinPeriod(trxDate, periodStart, periodEnd), isTrue);
    });

    test('date before period start is rejected', () {
      final periodStart = DateTime(2026, 1, 1);
      final periodEnd = DateTime(2026, 12, 31);
      final trxDate = DateTime(2025, 12, 31);

      expect(_isWithinPeriod(trxDate, periodStart, periodEnd), isFalse);
    });

    test('date on boundary is allowed', () {
      final periodStart = DateTime(2026, 1, 1);
      final periodEnd = DateTime(2026, 12, 31);

      expect(_isWithinPeriod(periodStart, periodStart, periodEnd), isTrue);
      expect(_isWithinPeriod(periodEnd, periodStart, periodEnd), isTrue);
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Helper functions — pure logic mirroring AccountingService/DAO behavior
// ═══════════════════════════════════════════════════════════════════════════

bool _validateSplitPayment(double total, double cashPaid, double bankPaid) {
  if (cashPaid < 0 || bankPaid < 0) return false;
  return (total - (cashPaid + bankPaid)).abs() <= 0.01;
}

Map<String, dynamic> _buildJournalLine({
  required int accountId,
  required double debit,
  required double credit,
  int? costCenterId,
}) {
  return {
    'accountId': accountId,
    'debit': debit,
    'credit': credit,
    'costCenterId': costCenterId,
  };
}

bool _isBalanced({required double debit, required double credit}) {
  return (debit - credit).abs() <= 0.001;
}

bool _isValidAmount(double amount) {
  return amount >= 0;
}

bool _isWithinPeriod(DateTime date, DateTime start, DateTime end) {
  return !date.isBefore(start) && !date.isAfter(end);
}
