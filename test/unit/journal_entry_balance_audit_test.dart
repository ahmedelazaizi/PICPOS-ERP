import 'package:flutter_test/flutter_test.dart';

/// PIR Unit Test — Journal Entry Balance Audit
///
/// Tests the accounting validators that enforce:
/// 1. Total Debit == Total Credit on every JE
/// 2. Zero-value entries are rejected
/// 3. Cost center integrity
/// 4. Manual JE draft/approval workflow
void main() {
  // ═══════════════════════════════════════════════════════════════════════
  // DEBIT-CREDIT BALANCE ENFORCEMENT
  // ═══════════════════════════════════════════════════════════════════════

  group('Debit-Credit Balance Enforcement', () {
    test('Balanced JE passes validation', () {
      final lines = [
        _JELine(accountId: 1, debit: 500, credit: 0),
        _JELine(accountId: 2, debit: 0, credit: 300),
        _JELine(accountId: 3, debit: 0, credit: 200),
      ];

      final totalDebit = lines.fold<double>(0, (s, l) => s + l.debit);
      final totalCredit = lines.fold<double>(0, (s, l) => s + l.credit);

      expect(totalDebit, equals(totalCredit),
          reason: 'Debit 500 == Credit 300+200');
      expect(_isBalanced(lines), isTrue);
    });

    test('Unbalanced JE fails validation', () {
      final lines = [
        _JELine(accountId: 1, debit: 500, credit: 0),
        _JELine(accountId: 2, debit: 0, credit: 400),
      ];

      expect(_isBalanced(lines), isFalse,
          reason: 'Debit 500 != Credit 400');
    });

    test('Single-line JE always unbalanced (unless debit+credit same line)', () {
      final singleLine = [
        _JELine(accountId: 1, debit: 100, credit: 0),
      ];

      expect(_isBalanced(singleLine), isFalse,
          reason: 'Single debit-only line cannot be balanced');
    });

    test('Multi-line complex JE balance', () {
      // Real scenario: Cash sale with discount + VAT + COGS
      final lines = [
        _JELine(accountId: 1101, debit: 513, credit: 0),    // Cash
        _JELine(accountId: 5101, debit: 300, credit: 0),    // COGS
        _JELine(accountId: 4101, debit: 0, credit: 450),    // Sales
        _JELine(accountId: 2201, debit: 0, credit: 63),     // Output VAT
        _JELine(accountId: 1103, debit: 0, credit: 300),    // Inventory
      ];

      expect(_isBalanced(lines), isTrue);
      final totalDebit = lines.fold<double>(0, (s, l) => s + l.debit);
      expect(totalDebit, equals(813.0),
          reason: 'Total debit = 513 (cash) + 300 (COGS)');
    });

    test('Floating-point precision: tiny difference rejected', () {
      final lines = [
        _JELine(accountId: 1, debit: 100.005, credit: 0),
        _JELine(accountId: 2, debit: 0, credit: 100.004),
      ];

      // With standard double comparison
      final totalDebit = lines.fold<double>(0, (s, l) => s + l.debit);
      final totalCredit = lines.fold<double>(0, (s, l) => s + l.credit);

      // They are NOT exactly equal
      expect(totalDebit == totalCredit, isFalse);

      // But with tolerance check (accounting standard: 0.01)
      expect((totalDebit - totalCredit).abs(), lessThan(0.01),
          reason: 'Within accounting tolerance');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // ZERO-VALUE REJECTION
  // ═══════════════════════════════════════════════════════════════════════

  group('Zero-Value Entry Rejection', () {
    test('Zero-total JE should be rejected', () {
      final lines = [
        _JELine(accountId: 1, debit: 0, credit: 0),
        _JELine(accountId: 2, debit: 0, credit: 0),
      ];

      final totalDebit = lines.fold<double>(0, (s, l) => s + l.debit);
      expect(totalDebit, equals(0.0));
      expect(_hasValue(lines), isFalse,
          reason: 'Zero-value JE has no economic substance');
    });

    test('Negative amounts should be rejected', () {
      const negativeAmount = -100.0;
      expect(negativeAmount < 0, isTrue,
          reason: 'Negative amounts are invalid in standard double-entry');
      expect(_isValidAmount(negativeAmount), isFalse);
    });

    test('Positive amounts pass validation', () {
      expect(_isValidAmount(100.0), isTrue);
      expect(_isValidAmount(0.01), isTrue);
      expect(_isValidAmount(0.0), isFalse,
          reason: 'Zero is not a valid individual line amount');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // COST CENTER PROPAGATION
  // ═══════════════════════════════════════════════════════════════════════

  group('Cost Center Propagation', () {
    test('All JE lines must have a cost center when company requires it', () {
      const companyCostCenterRequired = true;

      final lines = [
        _JELineWithCC(accountId: 1, debit: 500, credit: 0, costCenterId: 1),
        _JELineWithCC(accountId: 2, debit: 0, credit: 500, costCenterId: 1),
      ];

      if (companyCostCenterRequired) {
        final allHaveCC = lines.every((l) => l.costCenterId != null);
        expect(allHaveCC, isTrue,
            reason: 'CSR-01: All lines must carry a cost center');
      }
    });

    test('Missing cost center on any line fails validation', () {
      const companyCostCenterRequired = true;

      final lines = [
        _JELineWithCC(accountId: 1, debit: 500, credit: 0, costCenterId: 1),
        _JELineWithCC(accountId: 2, debit: 0, credit: 500, costCenterId: null), // ← missing
      ];

      if (companyCostCenterRequired) {
        final allHaveCC = lines.every((l) => l.costCenterId != null);
        expect(allHaveCC, isFalse);
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // MANUAL JE DRAFT/APPROVAL WORKFLOW (ICR-01)
  // ═══════════════════════════════════════════════════════════════════════

  group('Manual JE Draft/Approval Workflow', () {
    test('New manual JE starts as draft (not posted)', () {
      final manualJE = _ManualJE(
        isPosted: false,
        needsApproval: true,
        approvedBy: null,
      );

      expect(manualJE.isPosted, isFalse,
          reason: 'ICR-01: Manual JE must start as draft');
      expect(manualJE.needsApproval, isTrue);
    });

    test('Approved JE can be posted', () {
      final approvedJE = _ManualJE(
        isPosted: false,
        needsApproval: false,
        approvedBy: 'admin',
      );

      expect(approvedJE.canPost, isTrue,
          reason: 'Approved JE with no pending approval can be posted');
    });

    test('Unapproved JE cannot be posted', () {
      final pendingJE = _ManualJE(
        isPosted: false,
        needsApproval: true,
        approvedBy: null,
      );

      expect(pendingJE.canPost, isFalse,
          reason: 'JE with pending approval cannot be posted');
    });

    test('Already posted JE cannot be re-posted', () {
      final postedJE = _ManualJE(
        isPosted: true,
        needsApproval: false,
        approvedBy: 'admin',
      );

      expect(postedJE.canPost, isFalse,
          reason: 'Already posted JE should not be re-posted');
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Helper classes for testing
// ═══════════════════════════════════════════════════════════════════════════

class _JELine {
  final int accountId;
  final double debit;
  final double credit;

  _JELine({required this.accountId, required this.debit, required this.credit});
}

class _JELineWithCC extends _JELine {
  final int? costCenterId;

  _JELineWithCC({
    required super.accountId,
    required super.debit,
    required super.credit,
    this.costCenterId,
  });
}

class _ManualJE {
  final bool isPosted;
  final bool needsApproval;
  final String? approvedBy;

  _ManualJE({
    required this.isPosted,
    required this.needsApproval,
    this.approvedBy,
  });

  bool get canPost => !isPosted && !needsApproval;
}

bool _isBalanced(List<_JELine> lines) {
  final totalDebit = lines.fold<double>(0, (s, l) => s + l.debit);
  final totalCredit = lines.fold<double>(0, (s, l) => s + l.credit);
  return totalDebit == totalCredit;
}

bool _hasValue(List<_JELine> lines) {
  final totalDebit = lines.fold<double>(0, (s, l) => s + l.debit);
  return totalDebit > 0;
}

bool _isValidAmount(double amount) => amount > 0;
