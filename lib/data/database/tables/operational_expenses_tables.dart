part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// OPERATIONAL EXPENSES (المصروفات التشغيلية)
// ═══════════════════════════════════════════════════════════════════════════

/// Operational Expense Categories — فئات المصروفات التشغيلية
/// Types: direct (مباشرة), indirect (غير مباشرة), fixed (ثابتة), variable (متغيرة)
/// Allocation: per_unit, per_hour, per_order, fixed_monthly
@DataClassName('OpExpenseCategoryData')
class OpExpenseCategories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(max: 100)();
  TextColumn get type => text().withDefault(
    const Constant('indirect'),
  )(); // direct | indirect | fixed | variable
  BoolColumn get isProductionRelated => boolean().withDefault(
    const Constant(true),
  )(); // هل يتعلق بالإنتاج؟
  TextColumn get allocationMethod => text().withDefault(
    const Constant('fixed_monthly'),
  )(); // per_unit | per_hour | per_order | fixed_monthly
  RealColumn get defaultRate => real().withDefault(
    const Constant(0),
  )(); // المعدل الافتراضي (مبلغ لكل وحدة/ساعة/أمر)
  /// C-03 FIX: GL account code for this expense category (e.g., 5101 rent, 5102 utilities)
  /// Defaults to '5299' (مصروفات متنوعة) for backward compatibility.
  TextColumn get accountCode => text().withDefault(const Constant('5299'))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  // === v166 — أعمدةُ المزامنة (المرحلة ٢) ===
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

/// Operational Expenses — سجل المصروفات التشغيلية
@DataClassName('OpExpenseData')
@TableIndex(name: 'idx_op_expenses_category', columns: {#categoryId})
@TableIndex(name: 'idx_op_expenses_date', columns: {#expenseDate})
@TableIndex(name: 'idx_op_expenses_mfg_order', columns: {#manufacturingOrderId})
class OpExpenses extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get categoryId => integer().references(OpExpenseCategories, #id)();
  RealColumn get amount => real()();
  DateTimeColumn get expenseDate => dateTime()();
  TextColumn get period => text().withDefault(
    const Constant('monthly'),
  )(); // monthly | weekly | daily | one_time
  IntColumn get manufacturingOrderId => integer().nullable().references(
    ManufacturingOrders,
    #id,
  )(); // ربط مباشر بأمر تصنيع (اختياري)
  TextColumn get reference => text().nullable()(); // رقم مرجعي
  TextColumn get notes => text().nullable()();
  IntColumn get costCenterId => integer().nullable().references(CostCenters, #id)(); // مركز التكلفة
  IntColumn get branchId => integer().nullable().references(Branches, #id)(); // الفرع (للتصفية في التقارير)
  TextColumn get status => text().withDefault(const Constant('draft'))(); // U-03: draft | approved | paid
  TextColumn get paymentMethod => text().withDefault(const Constant('cash'))(); // F-12: cash | bank
  IntColumn get userId => integer().references(Users, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  // === v166 — أعمدةُ المزامنة (المرحلة ٢) ===
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

/// Manufacturing Order Costs — تفصيل تكاليف أمر التصنيع
/// Breaks down total cost into: raw_material | labor | overhead | depreciation | utility | other
@DataClassName('MfgOrderCostData')
@TableIndex(name: 'idx_mfg_order_costs_order', columns: {#orderId})
class MfgOrderCosts extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get orderId => integer().references(ManufacturingOrders, #id)();
  TextColumn get costType => text()(); // raw_material | labor | overhead | depreciation | utility | other
  TextColumn get description => text().withLength(max: 200)();
  RealColumn get amount => real()();
  IntColumn get expenseCategoryId => integer().nullable().references(
    OpExpenseCategories,
    #id,
  )(); // ربط بفئة المصروف (اختياري)
  IntColumn get expenseId => integer().nullable().references(
    OpExpenses,
    #id,
  )(); // ربط بسجل المصروف (اختياري)
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  // === v166 — أعمدةُ المزامنة (المرحلة ٢) ===
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}
