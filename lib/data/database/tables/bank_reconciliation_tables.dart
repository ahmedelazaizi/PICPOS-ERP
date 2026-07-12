part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// BANK RECONCILIATION TABLES — جداول المطابقة البنكية
// ═══════════════════════════════════════════════════════════════════════════

/// Bank statement lines imported from CSV/manual entry
@DataClassName('BankStatementLine')
@TableIndex(name: 'idx_bank_stmt_date', columns: {#transactionDate})
@TableIndex(name: 'idx_bank_stmt_account', columns: {#bankAccountId})
class BankStatementLines extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get bankAccountId => integer().references(Accounts, #id)();
  DateTimeColumn get transactionDate => dateTime()();
  TextColumn get reference => text().nullable()(); // رقم مرجعي بنكي
  TextColumn get description => text().nullable()();
  RealColumn get debitAmount => real().withDefault(const Constant(0))();
  RealColumn get creditAmount => real().withDefault(const Constant(0))();
  RealColumn get runningBalance => real().withDefault(const Constant(0))();
  BoolColumn get isMatched =>
      boolean().withDefault(const Constant(false))();
  IntColumn get matchedJournalLineId => integer().nullable()(); // ربط بسطر قيد
  TextColumn get matchType => text().nullable()(); // auto, manual, unmatched
  TextColumn get importBatch => text().nullable()(); // دفعة الاستيراد
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Bank reconciliation header — one per period per bank account
@DataClassName('BankReconciliationData')
class BankReconciliations extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get bankAccountId => integer().references(Accounts, #id)();
  DateTimeColumn get periodStart => dateTime()();
  DateTimeColumn get periodEnd => dateTime()();
  RealColumn get statementBalance => real()(); // رصيد كشف البنك
  RealColumn get bookBalance => real()(); // رصيد الدفتر
  RealColumn get difference => real().withDefault(const Constant(0))();
  IntColumn get totalMatched => integer().withDefault(const Constant(0))();
  IntColumn get totalUnmatched => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('draft'))(); // draft, completed
  IntColumn get preparedBy => integer().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
