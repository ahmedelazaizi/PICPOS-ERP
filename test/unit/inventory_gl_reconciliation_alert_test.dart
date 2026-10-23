// ═══════════════════════════════════════════════════════════════════════════
// م-2 alert layer (Spec 153) — the pure decision behind
// ReconciliationService.scheduleInventoryGlReconciliationCheck(): given an
// InventoryGlReconciliation (or null), decide skipped / OK / ALERT and build the
// operator-facing message. Mirrors scheduleArReconciliationCheck, but the
// decision lives in a pure factory so it is unit-testable without a live service.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/reconciliation_service.dart';

InventoryGlReconciliation _recon({required double delta}) {
  return InventoryGlReconciliation(
    glBalance: 1000,
    reportValue: 1000 + delta,
    perpetualBalancesAtCostPrice: 0,
    perpetualBalancesAtAvgCost: 0,
    delta: delta,
    costBasisDivergence: 0,
    stockVsLedgerDivergence: 0,
    zeroCostItemCount: 0,
    zeroCostStockQty: 0,
    inventoryAccountCode: '1136',
    inventoryAccountName: 'مخزون',
  );
}

void main() {
  group('InventoryGlReconciliationCheckResult.evaluate', () {
    test('null reconciliation → skipped, no alert', () {
      final r = InventoryGlReconciliationCheckResult.evaluate(null);
      expect(r.reconciliation, isNull);
      expect(r.alertLogged, isFalse);
      expect(r.isBalanced, isTrue);
      expect(r.message.toLowerCase(), contains('skip'));
    });

    test('balanced (|delta| < 0.01) → OK, no alert', () {
      final r =
          InventoryGlReconciliationCheckResult.evaluate(_recon(delta: 0.005));
      expect(r.alertLogged, isFalse);
      expect(r.isBalanced, isTrue);
      expect(r.message, contains('OK'));
    });

    test('drift (|delta| >= 0.01) → alert, delta surfaced in message', () {
      final r =
          InventoryGlReconciliationCheckResult.evaluate(_recon(delta: 5.0));
      expect(r.alertLogged, isTrue);
      expect(r.isBalanced, isFalse);
      expect(r.message, contains('ALERT'));
      expect(r.message, contains('5.0'));
    });

    test('boundary: delta exactly 0.01 is NOT balanced → alert', () {
      // isBalanced uses delta.abs() < 0.01, so exactly 0.01 trips the alert.
      final r =
          InventoryGlReconciliationCheckResult.evaluate(_recon(delta: 0.01));
      expect(r.isBalanced, isFalse);
      expect(r.alertLogged, isTrue);
    });
  });
}
