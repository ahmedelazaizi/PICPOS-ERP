part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ACCOUNTING TABLES
// ═══════════════════════════════════════════════════════════════════════════

@TableIndex(name: 'idx_accounts_code', columns: {#code})
@TableIndex(name: 'idx_accounts_type', columns: {#accountType})
@TableIndex(name: 'idx_accounts_parent', columns: {#parentId}) // لتسريع بناء الشجرة الهرمية
class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get code => text().withLength(max: 20)();
  TextColumn get name => text().withLength(max: 100)();
  TextColumn get accountType =>
      text()(); // asset, liability, equity, revenue, expense
  TextColumn get accountNature =>
      text().withDefault(const Constant('detail'))(); // view (parent) / detail (postable)
  TextColumn get normalBalance =>
      text().withDefault(const Constant('debit'))(); // debit / credit
  IntColumn get level =>
      integer().withDefault(const Constant(1))(); // hierarchy level 1-5
  IntColumn get parentId => integer().nullable().references(Accounts, #id)();
  RealColumn get balance => real().withDefault(const Constant(0))();
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get isHiddenFromEntries =>
      boolean().withDefault(const Constant(false))(); // إخفاء من سندات القيد
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

@DataClassName('JournalEntryData')
@TableIndex(name: 'idx_journal_entries_date', columns: {#entryDate})
@TableIndex(
  name: 'idx_journal_entries_reference',
  columns: {#referenceType, #referenceId},
)
@TableIndex(name: 'idx_journal_entries_branch', columns: {#branchId, #entryDate})
@TableIndex(name: 'idx_journal_entries_posted', columns: {#isPosted, #entryDate})
@TableIndex(name: 'idx_journal_entries_fiscal', columns: {#fiscalYearId}) // لتسريع تقارير السنة
@TableIndex(name: 'idx_journal_entries_cost_center', columns: {#costCenterId}) // لتسريع تقارير مركز التكلفة

@TableIndex(name: 'idx_journal_entries_idempotency', columns: {#idempotencyKey})
class JournalEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entryNumber => text().withLength(max: 50)();
  DateTimeColumn get entryDate => dateTime()();
  TextColumn get description => text().nullable()();

  /// v174 — «المرجع» الذي يكتبه المستخدمُ في سند القيد (بلاغُ المالك
  /// 2026-09-18، تصميمُ `(14).jpeg`).
  ///
  /// ⚠️ **ولا يُخلَط بـ[referenceType]/[referenceId]**: هذان حقلا **نظامٍ**
  /// يربطان القيدَ بمستنده الذي ولّده (فاتورةٌ · سندٌ · استبعادُ أصل)، ويقرؤهما
  /// محرّكُ الترحيل وتقريرُ التدفّقات وزرُّ القفز إلى المستند المصدر. وحشرُ نصٍّ
  /// حرٍّ فيهما يكسر ذلك كلَّه. وهذا حقلٌ وصفيٌّ لا يقرؤه محرّك.
  TextColumn get reference => text().nullable().withLength(max: 100)();

  TextColumn get referenceType =>
      text().nullable()(); // sale, purchase, receipt, payment, return, transfer
  IntColumn get referenceId => integer().nullable()();
  BoolColumn get isPosted => boolean().withDefault(const Constant(true))();
  BoolColumn get isAutoPosted =>
      boolean().withDefault(const Constant(false))(); // تلقائي أم يدوي
  BoolColumn get needsApproval =>
      boolean().withDefault(const Constant(false))(); // ICR-01: يحتاج اعتماد مدير
  IntColumn get fiscalYearId => integer().nullable()(); // السنة المالية
  IntColumn get currencyId =>
      integer().nullable().references(Currencies, #id)(); // Phase 8: Multi-currency
  RealColumn get exchangeRate =>
      real().withDefault(const Constant(1.0))(); // سعر الصرف وقت القيد
  IntColumn get costCenterId =>
      integer().nullable().references(CostCenters, #id)(); // مركز تكلفة
  IntColumn get branchId =>
      integer().nullable().references(Branches, #id)(); // الفرع المنتمي له القيد

  // Phase 4: Distributed Sync Reliability

  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  TextColumn get idempotencyKey => text().nullable()(); // Deduplication key for offline replay resilience
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))(); // Soft Delete
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get deletedBy => integer().nullable().references(Users, #id)(); // PIR P0-01: Who deleted
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@TableIndex(name: 'idx_journal_entry_lines_entry', columns: {#entryId})
@TableIndex(name: 'idx_journal_entry_lines_account', columns: {#accountId})
@TableIndex(
  name: 'idx_journal_entry_lines_composite',
  columns: {#accountId, #entryId},
)
@TableIndex(name: 'idx_journal_entry_lines_cost_center', columns: {#costCenterId})
class JournalEntryLines extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get entryId => integer().references(JournalEntries, #id, onDelete: KeyAction.cascade)();
  IntColumn get accountId => integer().references(Accounts, #id)();
  RealColumn get debit => real().withDefault(const Constant(0))();
  RealColumn get credit => real().withDefault(const Constant(0))();
  TextColumn get description => text().nullable()();
  IntColumn get costCenterId => integer().nullable()(); // مركز التكلفة

}

// ═══════════════════════════════════════════════════════════════════════════
// COST CENTERS (مراكز التكلفة)
// ═══════════════════════════════════════════════════════════════════════════

class CostCenters extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get code => text().withLength(max: 20)();
  TextColumn get name => text().withLength(max: 100)();
  IntColumn get parentId => integer().nullable()(); // شجري
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

// ═══════════════════════════════════════════════════════════════════════════
// FISCAL YEARS (السنوات المالية)
// ═══════════════════════════════════════════════════════════════════════════

@DataClassName('FiscalYearData')
class FiscalYears extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(max: 50)(); // "2026" أو "2025-2026"
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime()();
  BoolColumn get isClosed => boolean().withDefault(const Constant(false))();
  BoolColumn get isCurrent => boolean().withDefault(const Constant(false))();
  DateTimeColumn get closedAt => dateTime().nullable()();
  IntColumn get closedBy => integer().nullable()(); // المستخدم الذي أقفل السنة
  TextColumn get closingNotes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

// ═══════════════════════════════════════════════════════════════════════════
// ACCOUNTING PERIODS (الفترات المحاسبية الشهرية)
// ═══════════════════════════════════════════════════════════════════════════

/// Monthly accounting periods for financial lock control.
/// Each period covers one calendar month. When closed, no invoices
/// or journal entries can be created/modified within that date range.
@DataClassName('AccountingPeriodData')
class AccountingPeriods extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get fiscalYearId => integer().references(FiscalYears, #id)();
  TextColumn get name =>
      text().withLength(max: 50)(); // "يناير 2026" أو "01/2026"
  IntColumn get month => integer()(); // 1-12
  IntColumn get year => integer()(); // 2026
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime()();
  BoolColumn get isClosed =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get closedAt => dateTime().nullable()();
  IntColumn get closedBy =>
      integer().nullable()(); // User ID who closed
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();


  @override
  List<Set<Column>> get uniqueKeys => [
    {month, year},
  ];
}

// ═══════════════════════════════════════════════════════════════════════════
// ACTIVITY PROFILES (ملفات الأنشطة)
// ═══════════════════════════════════════════════════════════════════════════

class ActivityProfiles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name =>
      text().withLength(max: 100)(); // تجاري, صناعي, مقاولات, POS
  TextColumn get enabledModules =>
      text()(); // JSON: ["manufacturing","assets",...]
  BoolColumn get isActive => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
// ═══════════════════════════════════════════════════════════════════════════
// ACCOUNT MAPPINGS (ربط الحسابات التلقائي)
// ═══════════════════════════════════════════════════════════════════════════

@TableIndex(name: 'idx_account_mappings_purpose', columns: {#purpose})
class AccountMappings extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get purpose =>
      text()(); // e.g., 'cash', 'sales_revenue', 'cogs', 'inventory'
  IntColumn get accountId => integer().references(Accounts, #id)();
  IntColumn get costCenterId => integer().nullable().references(CostCenters, #id)();
  // null = global/default mapping, non-null = per-cost-center override
  TextColumn get description => text().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

}
