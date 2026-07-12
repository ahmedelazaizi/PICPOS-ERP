part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PIR P0-04: Failed Autopost Log — فشل الترحيل التلقائي
// When GL auto-posting fails, the failure is logged here for admin review.
// ═══════════════════════════════════════════════════════════════════════════
@DataClassName('FailedAutopost')
@TableIndex(name: 'idx_failed_autoposts_invoice', columns: {#invoiceId, #referenceType})
class FailedAutoposts extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get invoiceId => integer()(); // ID of the failing invoice/entity
  TextColumn get referenceType => text()(); // 'sale', 'purchase', etc.
  TextColumn get errorMessage => text()(); // Raw exception message
  BoolColumn get isResolved => boolean().withDefault(const Constant(false))();
  IntColumn get resolvedBy => integer().nullable().references(Users, #id)();
  DateTimeColumn get resolvedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('Shift')
@TableIndex(name: 'idx_shifts_user_status', columns: {#userId, #status})
@TableIndex(name: 'idx_shifts_start_time', columns: {#startTime})
class Shifts extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get startTime => dateTime()();
  DateTimeColumn get endTime => dateTime().nullable()();
  IntColumn get userId => integer().references(Users, #id)();

  // Spec 008 / FR-001: the branch this shift was opened on. Required so
  // multi-branch users' close logic zeroes the right branch's safes.
  // Nullable for legacy rows created before v145 — the close path falls
  // back to `getUserBranchId(userId)` when branchId is null, preserving
  // pre-008 behavior for those records.
  IntColumn get branchId => integer().nullable().references(Branches, #id)();

  // Financial context at opening
  RealColumn get openingBalance => real().withDefault(const Constant(0))();

  // Values at closing
  RealColumn get expectedCash => real().nullable()(); // Calculated by system
  RealColumn get actualCash =>
      real().nullable()(); // Entered by cashier (Blind Audit)
  RealColumn get variance => real().nullable()(); // expected - actual

  TextColumn get status => text().withLength(max: 20)(); // 'open', 'closed'
  TextColumn get notes => text().nullable()();
  // Closing method: 'normal', 'quick', 'msr_card', 'admin_password'
  TextColumn get closingMethod => text().withDefault(const Constant('normal'))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();

  // v114 / Feature 009 (FR-035): the POS terminal this shift was opened on.
  // Auto-populated by the shift-open flow on POS hosts; NULL for non-POS
  // sessions (admin laptop, web admin) so legacy and admin sessions still
  // function. Powers per-terminal stock-shortage policy override (FR-017).
  IntColumn get posTerminalId =>
      integer().nullable().references(PosTerminals, #id)();
}
