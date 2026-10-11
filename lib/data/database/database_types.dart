part of 'database.dart';

// Top-level types that used to sit at the top of database.dart: the industry
// mode enum, the Spec 130 PG-parity exception/snapshot types and the
// numbering-gap report row. Pure move — kept ABOVE `@DriftDatabase` in the
// original, which still holds: none of them sits between the annotation and
// `AppDatabase`.

/// The primary industry mode for the application, controlling which
/// screens and features are available (e.g. restaurant tables, café menus).
enum IndustryMode { supermarket, restaurant, cafe, retail }

// ═══════════════════════════════════════════════════════════════════════════
// SPEC 130 — PG SCHEMA PARITY EXCEPTION
// ═══════════════════════════════════════════════════════════════════════════
//
// Thrown by `_ensurePostgresSchemaParity()` when the parity pass cannot
// close schema gaps because of an unrecoverable error (DDL permission
// denied, connection lost, etc.). Caller (main_desktop.dart) MUST route
// to FatalSetupErrorApp per Spec 130 Clarification Q2 (Block-all):
// no reads + no writes until resolved or user clicks "إعادة محاولة".
//
// Distinct from runtime DDL errors that the pass tolerates (e.g.,
// column type drift, extra PG tables) — those are warn-only.
// ═══════════════════════════════════════════════════════════════════════════
class PgSchemaParityException implements Exception {
  /// Arabic message for FatalSetupErrorApp display.
  final String reasonAr;

  /// English details for DiagnosticLogger / support call-in.
  final List<String> details;

  /// Entity names that the pass couldn't heal (e.g., table names).
  final List<String> failedEntities;

  const PgSchemaParityException({
    required this.reasonAr,
    this.details = const [],
    this.failedEntities = const [],
  });

  @override
  String toString() =>
      'PgSchemaParityException(reasonAr=$reasonAr, '
      'failedEntities=$failedEntities, details=$details)';
}

/// In-memory snapshot of a single PG column from `information_schema.columns`.
/// Lowercased everywhere for case-insensitive comparison.
class _PgLiveColumn {
  final String pgType;
  final bool nullable;
  const _PgLiveColumn({required this.pgType, required this.nullable});
}

/// Captured DDL failure during the parity pass. Aggregated and converted to
/// [PgSchemaParityException] at end-of-pass.
class _PgParityFatal {
  final String entity;
  final String detail;
  const _PgParityFatal({required this.entity, required this.detail});
}

/// 066 (D5-001) — read-only audit result row from
/// [AppDatabase.auditNumberingGaps]. Egyptian VAT prohibits auto-renumbering;
/// callers display this to the accountant, who decides whether to post
/// compensating void rows. See
/// specs/066-voucher-numbering-atomicity/contracts/numbering-atomicity.md.
///
/// NOTE: kept ABOVE `@DriftDatabase(...)` so the annotation binds to
/// `AppDatabase` (the very next class declaration) and not to this one.
/// drift_dev attaches each `@DriftDatabase` to the next class in source
/// order — placing this class between the annotation and `AppDatabase`
/// caused build_runner to emit `_$NumberingGapReport extends GeneratedDatabase`
/// instead of `_$AppDatabase`, breaking every `flutter analyze` call.
class NumberingGapReport {
  final String prefix;
  final int counterNext;
  final int maxUsedNumber;
  final int gapCount;
  const NumberingGapReport({
    required this.prefix,
    required this.counterNext,
    required this.maxUsedNumber,
    required this.gapCount,
  });
}
