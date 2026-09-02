part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ENTERPRISE TABLES — جداول المستوى المؤسسي (Phase 8)
// ═══════════════════════════════════════════════════════════════════════════

// ─────────────────────────────────────────────────────────────────────────
// 8.2 BUDGETING — الموازنات
// ─────────────────────────────────────────────────────────────────────────

/// Budget definitions — one per fiscal year per account
@DataClassName('BudgetData')
@TableIndex(name: 'idx_budget_year', columns: {#fiscalYearId})
class Budgets extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get fiscalYearId => integer().references(FiscalYears, #id)();
  IntColumn get accountId => integer().references(Accounts, #id)();
  IntColumn get costCenterId =>
      integer().nullable().references(CostCenters, #id)();
  TextColumn get name => text().nullable()(); // اسم الموازنة
  RealColumn get annualAmount => real().withDefault(const Constant(0))();
  TextColumn get distributionMethod =>
      text().withDefault(const Constant('equal'))(); // equal, manual, seasonal
  TextColumn get status =>
      text().withDefault(const Constant('draft'))(); // draft, approved, closed
  IntColumn get approvedBy => integer().nullable().references(Users, #id)();
  DateTimeColumn get approvedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Monthly budget breakdown
@DataClassName('BudgetLineData')
@TableIndex(name: 'idx_budget_line_month', columns: {#budgetId, #month})
class BudgetLines extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get budgetId => integer().references(Budgets, #id)();
  IntColumn get month => integer()(); // 1-12
  RealColumn get plannedAmount => real().withDefault(const Constant(0))();
  RealColumn get actualAmount => real().withDefault(const Constant(0))();
  RealColumn get variance => real().withDefault(const Constant(0))();
  TextColumn get notes => text().nullable()();
}

// ─────────────────────────────────────────────────────────────────────────
// 8.3 DEFERRED REVENUE / EXPENSE — الإيرادات والمصروفات المؤجلة
// ─────────────────────────────────────────────────────────────────────────

/// Deferred schedule for revenue recognition or expense amortization
@DataClassName('DeferredScheduleData')
@TableIndex(name: 'idx_deferred_type', columns: {#type})
class DeferredSchedules extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get type => text()(); // deferred_revenue, prepaid_expense
  TextColumn get description => text()();
  RealColumn get totalAmount => real()();
  RealColumn get recognizedAmount => real().withDefault(const Constant(0))();
  RealColumn get remainingAmount => real().withDefault(const Constant(0))();
  IntColumn get sourceAccountId => integer().references(Accounts, #id)();
  IntColumn get targetAccountId => integer().references(Accounts, #id)();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime()();
  IntColumn get totalPeriods => integer()(); // عدد فترات الاستحقاق
  IntColumn get completedPeriods => integer().withDefault(const Constant(0))();
  TextColumn get frequency =>
      text().withDefault(const Constant('monthly'))(); // monthly, quarterly
  TextColumn get status =>
      text().withDefault(const Constant('active'))(); // active, completed, cancelled
  IntColumn get referenceId => integer().nullable()(); // فاتورة/عقد مرتبط
  TextColumn get referenceType => text().nullable()(); // invoice, contract
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Individual recognition entries for each period
@DataClassName('DeferredEntryData')
class DeferredEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get scheduleId => integer().references(DeferredSchedules, #id)();
  IntColumn get periodNumber => integer()();
  DateTimeColumn get recognitionDate => dateTime()();
  RealColumn get amount => real()();
  IntColumn get journalEntryId =>
      integer().nullable().references(JournalEntries, #id)();
  BoolColumn get isPosted =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get postedAt => dateTime().nullable()();
}

// ─────────────────────────────────────────────────────────────────────────
// 8.4 APPROVAL WORKFLOWS — سير عمل الاعتمادات
// ─────────────────────────────────────────────────────────────────────────

/// Workflow template definitions
@DataClassName('ApprovalWorkflowData')
class ApprovalWorkflows extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get entityType =>
      text()(); // journal_entry, sales_invoice, purchase_invoice, safe_transfer
  RealColumn get amountThreshold =>
      real().withDefault(const Constant(0))(); // الحد الأدنى لتفعيل الاعتماد
  IntColumn get requiredLevels =>
      integer().withDefault(const Constant(2))(); // عدد المستويات: 2=Maker-Checker, 3=+Approver
  /// JSON condition rules for dynamic routing
  /// Format: [{"field":"amount","op":">","value":5000}, ...]
  TextColumn get conditionRules => text().nullable()();
  /// Hours before auto-escalation to next level (0 = disabled)
  IntColumn get escalationHours => integer().withDefault(const Constant(0))();
  /// Auto-approve requests below this amount (0 = disabled)
  RealColumn get autoApproveBelow => real().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  // === v173 — أعمدةُ المزامنة (المرحلة ٤: السجلُّ الرقابيُّ والتشغيلُ العابر) ===
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

/// Approval workflow step definitions
@DataClassName('ApprovalStepData')
class ApprovalSteps extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get workflowId => integer().references(ApprovalWorkflows, #id)();
  IntColumn get stepOrder => integer()(); // 1, 2, 3...
  TextColumn get stepName => text()(); // Maker, Checker, Approver
  IntColumn get roleId =>
      integer().nullable().references(Roles, #id)(); // الدور المطلوب
  IntColumn get userId =>
      integer().nullable().references(Users, #id)(); // أو مستخدم محدد
  BoolColumn get canReject => boolean().withDefault(const Constant(true))();
  // === v173 — أعمدةُ المزامنة (المرحلة ٤: السجلُّ الرقابيُّ والتشغيلُ العابر) ===
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

/// Pending approval requests
@DataClassName('ApprovalRequestData')
@TableIndex(name: 'idx_approval_request_entity', columns: {#entityType, #entityId})
@TableIndex(name: 'idx_approval_request_status', columns: {#status})
class ApprovalRequests extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get workflowId => integer().references(ApprovalWorkflows, #id)();
  TextColumn get entityType => text()();
  IntColumn get entityId => integer()();
  RealColumn get amount => real().withDefault(const Constant(0))();
  IntColumn get currentStep => integer().withDefault(const Constant(1))();
  TextColumn get status =>
      text().withDefault(const Constant('pending'))(); // pending, approved, rejected
  IntColumn get requestedBy => integer().references(Users, #id)();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get completedAt => dateTime().nullable()();
  // === v173 — أعمدةُ المزامنة (المرحلة ٤: السجلُّ الرقابيُّ والتشغيلُ العابر) ===
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

/// Approval decision log
@DataClassName('ApprovalDecisionData')
class ApprovalDecisions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get requestId => integer().references(ApprovalRequests, #id)();
  IntColumn get stepId => integer().references(ApprovalSteps, #id)();
  IntColumn get decidedBy => integer().references(Users, #id)();
  TextColumn get decision => text()(); // approved, rejected
  TextColumn get comments => text().nullable()();
  DateTimeColumn get decidedAt => dateTime().withDefault(currentDateAndTime)();
  // === v173 — أعمدةُ المزامنة (المرحلة ٤: السجلُّ الرقابيُّ والتشغيلُ العابر) ===
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

// ─────────────────────────────────────────────────────────────────────────
// 8.5 SOD MATRIX — مصفوفة فصل المهام
// ─────────────────────────────────────────────────────────────────────────

/// Segregation of Duties conflict definitions
@DataClassName('SodConflictData')
class SodConflicts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get permission1 => text()(); // e.g. 'create_journal'
  TextColumn get permission2 => text()(); // e.g. 'approve_journal'
  TextColumn get conflictType =>
      text().withDefault(const Constant('hard'))(); // hard (blocked), soft (warning)
  TextColumn get description => text()(); // وصف التعارض
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  // === v173 — أعمدةُ المزامنة (المرحلة ٤: السجلُّ الرقابيُّ والتشغيلُ العابر) ===
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

/// SOD violation log
@DataClassName('SodViolationData')
@TableIndex(name: 'idx_sod_violation_user', columns: {#userId})
class SodViolations extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get conflictId => integer().references(SodConflicts, #id)();
  IntColumn get userId => integer().references(Users, #id)();
  IntColumn get roleId => integer().nullable().references(Roles, #id)();
  TextColumn get detectedAction => text()(); // العملية التي تسببت في الاكتشاف
  BoolColumn get wasBlocked =>
      boolean().withDefault(const Constant(false))(); // هل تم منع العملية
  TextColumn get overrideReason => text().nullable()(); // سبب التجاوز إن وجد
  IntColumn get overriddenBy =>
      integer().nullable().references(Users, #id)(); // المشرف الذي سمح
  DateTimeColumn get detectedAt =>
      dateTime().withDefault(currentDateAndTime)();
  // === v173 — أعمدةُ المزامنة (المرحلة ٤: السجلُّ الرقابيُّ والتشغيلُ العابر) ===
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

// ─────────────────────────────────────────────────────────────────────────
// 8.6 IN-APP NOTIFICATIONS — الإشعارات الداخلية
// ─────────────────────────────────────────────────────────────────────────

/// System notifications for users
@DataClassName('NotificationData')
@TableIndex(name: 'idx_notification_user', columns: {#userId})
class Notifications extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get userId => integer().references(Users, #id)(); // User to notify
  TextColumn get title => text()(); // عنوان الإشعار
  TextColumn get body => text()(); // نص الإشعار
  TextColumn get type => 
      text().withDefault(const Constant('info'))(); // info, warning, error, success
  BoolColumn get isRead => boolean().withDefault(const Constant(false))();
  IntColumn get relatedEntityId => integer().nullable()(); // ID of the related item
  TextColumn get relatedEntityType => text().nullable()(); // Type of the related item (e.g., invoice, stock)
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
}
