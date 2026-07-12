// =======================================================================
// REPORT PROVIDERS — PIR P1-01
// Centralizes report data fetching so presentation screens do NOT
// call ref.read(databaseProvider) directly.
// =======================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers.dart';

// ─── VAT Reconciliation ────────────────────────────────────────────────────

/// Parameters record for vatReconciliationProvider
typedef VatReconciliationParams = ({int year, int month});

/// Provides VAT reconciliation data for a given year/month.
/// Screens should watch this provider instead of calling the DB directly.
final vatReconciliationProvider = FutureProvider.family<
    VatReconciliationResult, VatReconciliationParams>(
  (ref, params) async {
    final db = ref.watch(databaseProvider);
    return db.getVatReconciliationData(
      year: params.year,
      month: params.month,
    );
  },
);

// ─── AR/AP Aging Report ────────────────────────────────────────────────────

/// Parameters record for arAgingReportProvider
typedef ArAgingParams = ({DateTime asOfDate, bool customersOnly});

/// Provides AR or AP aging rows for a given as-of date.
final arAgingReportProvider =
    FutureProvider.family<List<ArAgingRow>, ArAgingParams>(
  (ref, params) async {
    final db = ref.watch(databaseProvider);
    return db.getArAgingReport(
      asOfDate: params.asOfDate,
      customersOnly: params.customersOnly,
    );
  },
);

// ─── AR Reconciliation (Party Balance vs GL) ───────────────────────────────

/// Provides the AR/AP reconciliation result (party balances vs GL).
/// Refreshable via ref.invalidate(arReconciliationProvider).
final arReconciliationProvider = FutureProvider<ArReconciliation?>(
  (ref) async {
    final db = ref.watch(databaseProvider);
    return db.getArReconciliation();
  },
);
