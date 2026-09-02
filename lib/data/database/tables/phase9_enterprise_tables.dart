part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PHASE 9 ENTERPRISE TABLES — جداول المستوى المؤسسي المتقدم
// ═══════════════════════════════════════════════════════════════════════════

// ─────────────────────────────────────────────────────────────────────────
// 9.2 CONSOLIDATED FINANCIAL STATEMENTS — قوائم مالية موحدة
// ─────────────────────────────────────────────────────────────────────────

/// Business entities (subsidiaries) for consolidation
@DataClassName('EntityData')
class Entities extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get code => text().withLength(max: 20)();
  TextColumn get type =>
      text().withDefault(const Constant('subsidiary'))(); // parent, subsidiary, associate
  IntColumn get parentEntityId =>
      integer().nullable().references(Entities, #id)();
  RealColumn get ownershipPct =>
      real().withDefault(const Constant(100))(); // نسبة الملكية %
  IntColumn get currencyId =>
      integer().nullable().references(Currencies, #id)();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Entity-branch/cost center mapping
@DataClassName('EntityMappingData')
class EntityMappings extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get entityId => integer().references(Entities, #id)();
  IntColumn get costCenterId =>
      integer().nullable().references(CostCenters, #id)();
  IntColumn get branchId =>
      integer().nullable().references(Branches, #id)();
}

// ─────────────────────────────────────────────────────────────────────────
// 9.3 INTER-COMPANY ACCOUNTING — محاسبة بين الشركات
// ─────────────────────────────────────────────────────────────────────────

@DataClassName('IntercompanyTransactionData')
@TableIndex(name: 'idx_interco_entities', columns: {#fromEntityId, #toEntityId})
class IntercompanyTransactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get fromEntityId => integer().references(Entities, #id)();
  IntColumn get toEntityId => integer().references(Entities, #id)();
  TextColumn get transactionType =>
      text()(); // sale, purchase, transfer, loan, dividend
  RealColumn get amount => real()();
  IntColumn get currencyId =>
      integer().nullable().references(Currencies, #id)();
  RealColumn get exchangeRate => real().withDefault(const Constant(1.0))();
  IntColumn get fromJournalId =>
      integer().nullable().references(JournalEntries, #id)();
  IntColumn get toJournalId =>
      integer().nullable().references(JournalEntries, #id)();
  TextColumn get status =>
      text().withDefault(const Constant('pending'))(); // pending, confirmed, eliminated
  TextColumn get description => text().nullable()();
  DateTimeColumn get transactionDate => dateTime()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// ─────────────────────────────────────────────────────────────────────────
// 9.4 RESTATEMENT ENGINE — محرك إعادة العرض
// ─────────────────────────────────────────────────────────────────────────

@DataClassName('RestatementData')
class Restatements extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get reason =>
      text()(); // error_correction, policy_change, reclassification
  TextColumn get description => text()();
  IntColumn get fiscalYearId => integer().references(FiscalYears, #id)();
  TextColumn get status =>
      text().withDefault(const Constant('draft'))(); // draft, applied, reversed
  IntColumn get createdBy => integer().references(Users, #id)();
  IntColumn get approvedBy =>
      integer().nullable().references(Users, #id)();
  DateTimeColumn get appliedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Individual restatement adjustments
@DataClassName('RestatementLineData')
class RestatementLines extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get restatementId => integer().references(Restatements, #id)();
  IntColumn get accountId => integer().references(Accounts, #id)();
  RealColumn get originalDebit => real().withDefault(const Constant(0))();
  RealColumn get originalCredit => real().withDefault(const Constant(0))();
  RealColumn get adjustedDebit => real().withDefault(const Constant(0))();
  RealColumn get adjustedCredit => real().withDefault(const Constant(0))();
  TextColumn get notes => text().nullable()();
}

// ─────────────────────────────────────────────────────────────────────────
// 9.5 COMPLIANCE TRACKING — تتبع الامتثال
// ─────────────────────────────────────────────────────────────────────────

@DataClassName('ComplianceCheckData')
class ComplianceChecks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get category =>
      text()(); // ifrs, sox, vat, audit_trail, sod, data_integrity
  TextColumn get checkName => text()();
  TextColumn get description => text()();
  TextColumn get status =>
      text().withDefault(const Constant('pending'))(); // pass, fail, warning, pending
  TextColumn get details => text().nullable()();
  RealColumn get score =>
      real().withDefault(const Constant(0))(); // 0-100 compliance score
  DateTimeColumn get lastCheckedAt =>
      dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  // === v173 — أعمدةُ المزامنة (المرحلة ٤: السجلُّ الرقابيُّ والتشغيلُ العابر) ===
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}
