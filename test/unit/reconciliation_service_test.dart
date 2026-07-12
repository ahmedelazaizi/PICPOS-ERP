// ═══════════════════════════════════════════════════════════════════════════
// RECONCILIATION SERVICE — Unit Tests (PIR Sprint 4)
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/services/reconciliation_service.dart';

/// Tests for ReconciliationService data models and logic.
///
/// Note: Full integration tests require a live AppDatabase instance.
/// These tests validate the model layer and discrepancy detection logic.
void main() {
  group('BalanceDiscrepancy Model', () {
    test('hasDiscrepancy returns true for significant difference', () {
      const d = BalanceDiscrepancy(
        entityId: 1,
        entityName: 'Test Account',
        entityType: 'account',
        cachedValue: 100.0,
        calculatedValue: 95.0,
        difference: 5.0,
      );
      expect(d.hasDiscrepancy, isTrue);
    });

    test('hasDiscrepancy returns false for negligible difference', () {
      const d = BalanceDiscrepancy(
        entityId: 1,
        entityName: 'Test Account',
        entityType: 'account',
        cachedValue: 100.0,
        calculatedValue: 100.005,
        difference: -0.005,
      );
      expect(d.hasDiscrepancy, isFalse);
    });

    test('hasDiscrepancy boundary at 0.01', () {
      const d = BalanceDiscrepancy(
        entityId: 1,
        entityName: 'Test Account',
        entityType: 'account',
        cachedValue: 100.0,
        calculatedValue: 99.99,
        difference: 0.01,
      );
      expect(d.hasDiscrepancy, isFalse);
    });

    test('hasDiscrepancy boundary just above 0.01', () {
      const d = BalanceDiscrepancy(
        entityId: 1,
        entityName: 'Test',
        entityType: 'account',
        cachedValue: 100.0,
        calculatedValue: 99.98,
        difference: 0.02,
      );
      expect(d.hasDiscrepancy, isTrue);
    });

    test('toString contains entity info', () {
      const d = BalanceDiscrepancy(
        entityId: 42,
        entityName: 'Cash Account',
        entityType: 'account',
        cachedValue: 1000.0,
        calculatedValue: 950.0,
        difference: 50.0,
      );
      final s = d.toString();
      expect(s, contains('account'));
      expect(s, contains('42'));
      expect(s, contains('Cash Account'));
      expect(s, contains('1000'));
      expect(s, contains('950'));
    });
  });

  group('ReconciliationReport Model', () {
    test('creates report with correct fields', () {
      final report = ReconciliationReport(
        entityType: 'الحسابات',
        totalChecked: 100,
        discrepanciesFound: 3,
        fixed: 2,
        discrepancies: const [
          BalanceDiscrepancy(
            entityId: 1,
            entityName: 'A',
            entityType: 'account',
            cachedValue: 100,
            calculatedValue: 90,
            difference: 10,
          ),
        ],
      );
      expect(report.entityType, 'الحسابات');
      expect(report.totalChecked, 100);
      expect(report.discrepanciesFound, 3);
      expect(report.fixed, 2);
      expect(report.discrepancies.length, 1);
      expect(report.timestamp, isNotNull);
    });

    test('timestamp defaults to now', () {
      final before = DateTime.now();
      final report = ReconciliationReport(
        entityType: 'test',
        totalChecked: 0,
        discrepanciesFound: 0,
        fixed: 0,
        discrepancies: const [],
      );
      final after = DateTime.now();
      expect(report.timestamp.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
      expect(report.timestamp.isBefore(after.add(const Duration(seconds: 1))), isTrue);
    });
  });

  group('Entity Type Coverage', () {
    test('BalanceDiscrepancy supports all 4 entity types', () {
      for (final type in ['account', 'party', 'safe', 'product']) {
        final d = BalanceDiscrepancy(
          entityId: 1,
          entityName: 'Test',
          entityType: type,
          cachedValue: 100,
          calculatedValue: 90,
          difference: 10,
        );
        expect(d.entityType, type);
        expect(d.hasDiscrepancy, isTrue);
      }
    });
  });
}
