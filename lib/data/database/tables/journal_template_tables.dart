part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// JOURNAL ENTRY TEMPLATES (قوالب قيود اليومية المحاسبية)
// ═══════════════════════════════════════════════════════════════════════════

@DataClassName('JournalEntryTemplateData')
class JournalEntryTemplates extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(max: 100)();
  TextColumn get description => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@TableIndex(name: 'idx_journal_template_lines_template', columns: {#templateId})
@TableIndex(name: 'idx_journal_template_lines_account', columns: {#accountId})
class JournalEntryTemplateLines extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get templateId => integer().references(JournalEntryTemplates, #id, onDelete: KeyAction.cascade)();
  IntColumn get accountId => integer().references(Accounts, #id)();
  RealColumn get debit => real().withDefault(const Constant(0))();
  RealColumn get credit => real().withDefault(const Constant(0))();
  TextColumn get description => text().nullable()();
  IntColumn get costCenterId => integer().nullable()(); // مركز التكلفة
}
