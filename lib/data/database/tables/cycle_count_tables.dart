part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CYCLE COUNTING — الجرد الدوري المستمر (Phase C4)
// ═══════════════════════════════════════════════════════════════════════════

/// Cycle count plan definition — defines the schedule and scope
@DataClassName('CycleCountPlanData')
@TableIndex(name: 'idx_cycle_plan_warehouse', columns: {#warehouseId})
class CycleCountPlans extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()(); // اسم الخطة
  IntColumn get warehouseId => integer().references(Warehouses, #id)();

  /// Counting frequency: daily, weekly, monthly, quarterly
  TextColumn get frequency =>
      text().withDefault(const Constant('weekly'))();

  /// ABC classification filter: A, B, C, or 'all'
  TextColumn get abcClassification =>
      text().withDefault(const Constant('all'))();

  /// Number of products to count per task
  IntColumn get productsPerTask =>
      integer().withDefault(const Constant(20))();

  /// Plan status: active, paused, completed
  TextColumn get status =>
      text().withDefault(const Constant('active'))();

  DateTimeColumn get nextDueDate => dateTime().nullable()();
  IntColumn get createdBy => integer().nullable().references(Users, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Individual counting task assigned to a user
@DataClassName('CycleCountTaskData')
@TableIndex(name: 'idx_cycle_task_plan', columns: {#planId})
@TableIndex(name: 'idx_cycle_task_date', columns: {#taskDate})
@TableIndex(name: 'idx_cycle_task_status', columns: {#status})
class CycleCountTasks extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get planId => integer().references(CycleCountPlans, #id)();
  DateTimeColumn get taskDate => dateTime()();
  IntColumn get assignedTo => integer().nullable().references(Users, #id)();

  /// Task status: pending, in_progress, completed, cancelled
  TextColumn get status =>
      text().withDefault(const Constant('pending'))();

  IntColumn get productCount => integer().withDefault(const Constant(0))();
  IntColumn get countedCount => integer().withDefault(const Constant(0))();
  IntColumn get varianceCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get startedAt => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Individual product count within a task
@DataClassName('CycleCountItemData')
@TableIndex(name: 'idx_cycle_item_task', columns: {#taskId})
@TableIndex(name: 'idx_cycle_item_product', columns: {#productId})
class CycleCountItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get taskId => integer().references(CycleCountTasks, #id)();
  IntColumn get productId => integer().references(Products, #id)();
  RealColumn get expectedQty => real()();
  RealColumn get countedQty => real().nullable()();
  RealColumn get variance => real().nullable()();
  RealColumn get variancePercent => real().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get countedAt => dateTime().nullable()();
}
