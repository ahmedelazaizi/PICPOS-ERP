import 'package:drift/drift.dart';
import '../database.dart';

/// Result of the deliberately manual fiscal-year overlap repair.
class FiscalYearOverlapRepairReport {
  const FiscalYearOverlapRepairReport({
    required this.changed,
    required this.targetId,
    required this.linkedRows,
    required this.journalEntryCountBefore,
    required this.journalEntryCountAfter,
    required this.accountBalancesBefore,
    required this.accountBalancesAfter,
  });

  final bool changed;
  final int targetId;
  final Map<String, int> linkedRows;
  final int journalEntryCountBefore;
  final int journalEntryCountAfter;
  final Map<int, double> accountBalancesBefore;
  final Map<int, double> accountBalancesAfter;
}

/// Soft-disables the empty duplicate year only. It never deletes rows and does
/// not run from startup; callers must opt in after reviewing the report.
Future<FiscalYearOverlapRepairReport> repairFiscalYearOverlap(AppDatabase db) {
  const targetId = 2;
  return db.transaction(() async {
    final snapshotBefore = await _financialSnapshot(db);
    final linkedRows = await _fiscalYearReferences(db, targetId);
    _rejectReferencedFiscalYear(targetId, linkedRows);
    final changed = await _softDisableFiscalYear(db, targetId);
    final snapshotAfter = await _financialSnapshot(db);
    _verifyFinancialSnapshot(snapshotBefore, snapshotAfter);
    return FiscalYearOverlapRepairReport(
      changed: changed,
      targetId: targetId,
      linkedRows: linkedRows,
      journalEntryCountBefore: snapshotBefore.journalEntryCount,
      journalEntryCountAfter: snapshotAfter.journalEntryCount,
      accountBalancesBefore: snapshotBefore.accountBalances,
      accountBalancesAfter: snapshotAfter.accountBalances,
    );
  });
}

void _rejectReferencedFiscalYear(int targetId, Map<String, int> references) {
  final nonEmptyReferences = references.entries
      .where((reference) => reference.value != 0)
      .toList();
  if (nonEmptyReferences.isEmpty) return;
  throw StateError(
    'إيقاف الترحيل: السنة $targetId مرتبطة بصفوف: '
    '${nonEmptyReferences.map((e) => '${e.key}=${e.value}').join(', ')}',
  );
}

Future<bool> _softDisableFiscalYear(AppDatabase db, int targetId) async {
  final fiscalYear = await (db.select(db.fiscalYears)
        ..where((row) => row.id.equals(targetId)))
      .getSingleOrNull();
  if (fiscalYear == null) throw StateError('السنة المالية $targetId غير موجودة');
  if (fiscalYear.deletedAt != null) return false;
  await (db.update(db.fiscalYears)..where((row) => row.id.equals(targetId)))
      .write(FiscalYearsCompanion(
    deletedAt: Value(DateTime.now()),
    isCurrent: const Value(false),
  ));
  return true;
}

void _verifyFinancialSnapshot(
  _FinancialSnapshot before,
  _FinancialSnapshot after,
) {
  if (before.journalEntryCount != after.journalEntryCount ||
      !_sameBalances(before.accountBalances, after.accountBalances)) {
    throw StateError('تغيّر عدد القيود أو أرصدة الحسابات؛ أُلغي الترحيل ذرياً');
  }
}

class _FinancialSnapshot {
  const _FinancialSnapshot(this.journalEntryCount, this.accountBalances);

  final int journalEntryCount;
  final Map<int, double> accountBalances;
}

Future<Map<String, int>> _fiscalYearReferences(AppDatabase db, int targetId) async {
  final references = db.isPostgres
      ? await _postgresFiscalYearReferences(db)
      : await _sqliteFiscalYearReferences(db);
  return _countFiscalYearReferences(db, references, targetId);
}

Future<Set<(String, String)>> _postgresFiscalYearReferences(
  AppDatabase db,
) async {
  final rows = await db.customSelect('''
    SELECT table_schema, table_name, column_name FROM (
      SELECT tc.table_schema, tc.table_name, kcu.column_name
      FROM information_schema.table_constraints tc
      JOIN information_schema.key_column_usage kcu
        ON tc.constraint_name=kcu.constraint_name
       AND tc.constraint_schema=kcu.constraint_schema
      JOIN information_schema.constraint_column_usage ccu
        ON ccu.constraint_name=tc.constraint_name
       AND ccu.constraint_schema=tc.constraint_schema
      WHERE tc.constraint_type='FOREIGN KEY' AND ccu.table_schema='public'
        AND ccu.table_name='fiscal_years' AND ccu.column_name='id'
      UNION
      SELECT table_schema, table_name, column_name
      FROM information_schema.columns
      WHERE table_schema='public' AND column_name='fiscal_year_id'
    ) references_to_fiscal_year ORDER BY table_name, column_name
  ''').get();
  return {
    for (final row in rows)
      ('${row.data['table_schema']}.${row.data['table_name']}',
          row.data['column_name'] as String),
  };
}

Future<Set<(String, String)>> _sqliteFiscalYearReferences(
  AppDatabase db,
) async {
  final references = <(String, String)>{};
  final tableRows = await db.customSelect(
    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
  ).get();
  for (final row in tableRows) {
    final table = row.data['name'] as String;
    await _addSqliteColumnReference(db, table, references);
    await _addSqliteForeignKeyReferences(db, table, references);
  }
  return references;
}

Future<void> _addSqliteColumnReference(
  AppDatabase db,
  String table,
  Set<(String, String)> references,
) async {
  final columns = await db.customSelect('PRAGMA table_info("$table")').get();
  if (columns.any((column) => column.data['name'] == 'fiscal_year_id')) {
    references.add((table, 'fiscal_year_id'));
  }
}

Future<void> _addSqliteForeignKeyReferences(
  AppDatabase db,
  String table,
  Set<(String, String)> references,
) async {
  final foreignKeys = await db.customSelect('PRAGMA foreign_key_list("$table")').get();
  for (final foreignKey in foreignKeys) {
    if (foreignKey.data['table'] == 'fiscal_years' && foreignKey.data['to'] == 'id') {
      references.add((table, foreignKey.data['from'] as String));
    }
  }
}

Future<Map<String, int>> _countFiscalYearReferences(
  AppDatabase db,
  Set<(String, String)> references,
  int targetId,
) async {
  final counts = <String, int>{};
  for (final reference in references) {
    final qualifiedTable = _quoteTableName(reference.$1);
    final quotedColumn = _quoteColumnName(reference.$2);
    final countQuery = await db.customSelect(
      'SELECT COUNT(*) AS n FROM $qualifiedTable WHERE $quotedColumn = ?',
      variables: [Variable<int>(targetId)],
    ).getSingle();
    counts['${reference.$1}.${reference.$2}'] =
        (countQuery.data['n'] as num).toInt();
  }
  return counts;
}

String _quoteTableName(String table) {
  final parts = table.split('.');
  if (parts.any((part) => !_isSqlIdentifier(part))) {
    throw StateError('اسم جدول غير متوقع في مرجع السنة المالية: $table');
  }
  return parts.map((part) => '"$part"').join('.');
}

String _quoteColumnName(String column) {
  if (!_isSqlIdentifier(column)) {
    throw StateError('اسم عمود غير متوقع في مرجع السنة المالية: $column');
  }
  return '"$column"';
}

bool _isSqlIdentifier(String identifier) =>
    RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(identifier);

Future<_FinancialSnapshot> _financialSnapshot(AppDatabase db) async {
  final entryCountQuery = await db.customSelect(
    'SELECT COUNT(*) AS n FROM journal_entries',
  ).getSingle();
  final balanceRows = await db.customSelect('''
    SELECT a.id AS account_id,
           COALESCE(SUM(l.debit - l.credit), 0) AS balance
    FROM accounts a
    LEFT JOIN journal_entry_lines l ON l.account_id = a.id
    GROUP BY a.id ORDER BY a.id
  ''').get();
  return _FinancialSnapshot(
    (entryCountQuery.data['n'] as num).toInt(),
    {for (final row in balanceRows) (row.data['account_id'] as num).toInt():
      (row.data['balance'] as num).toDouble()},
  );
}

bool _sameBalances(
  Map<int, double> balancesBefore,
  Map<int, double> balancesAfter,
) {
  if (balancesBefore.length != balancesAfter.length) return false;
  for (final entry in balancesBefore.entries) {
    if (balancesAfter[entry.key] != entry.value) return false;
  }
  return true;
}
