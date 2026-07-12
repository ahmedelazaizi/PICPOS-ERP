import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/reconciliation_service.dart';
import 'providers.dart';

/// Provider for ReconciliationService
final reconciliationServiceProvider = Provider<ReconciliationService>((ref) {
  final db = ref.watch(databaseProvider);
  return ReconciliationService(
    accountingRepo: ref.watch(accountingRepositoryProvider),
    partiesRepo: ref.watch(partiesRepositoryProvider),
    treasuryRepo: ref.watch(treasuryRepositoryProvider),
    productRepo: ref.watch(productRepositoryProvider),
    db: db,
  );
});

/// Provider to run full reconciliation and get the report
final reconciliationReportProvider =
    FutureProvider<List<ReconciliationReport>>((ref) {
  final service = ref.watch(reconciliationServiceProvider);
  return service.runFullReconciliation();
});

// ─── AR Reconciliation Scheduled Check (PIR P2-02) ────────────────────────

/// Runs the AR sub-ledger vs GL reconciliation check.
///
/// Compares SUM(parties.balance WHERE is_customer=1) against GL Account 1121
/// (receivables). When the difference exceeds 0.01, an alert row is written
/// to field_audit_logs automatically.
///
/// Usage:
///   // Trigger on app startup:
///   ref.read(arReconciliationCheckProvider);
///
///   // Refresh manually (e.g. from a button):
///   ref.invalidate(arReconciliationCheckProvider);
final arReconciliationCheckProvider =
    FutureProvider<ArReconciliationCheckResult>((ref) {
  final service = ref.watch(reconciliationServiceProvider);
  return service.scheduleArReconciliationCheck();
});

// ─── Inventory-vs-GL Reconciliation Scheduled Check (Spec 153 م-2) ─────────

/// Runs the inventory-perpetual vs GL-1136 reconciliation check. Emits a
/// diagnostic-log alert when |delta| >= 0.01. Read-only — posts nothing.
///
/// Usage:
///   ref.read(inventoryGlReconciliationCheckProvider);      // trigger
///   ref.invalidate(inventoryGlReconciliationCheckProvider); // refresh
final inventoryGlReconciliationCheckProvider =
    FutureProvider<InventoryGlReconciliationCheckResult>((ref) {
  final service = ref.watch(reconciliationServiceProvider);
  return service.scheduleInventoryGlReconciliationCheck();
});
