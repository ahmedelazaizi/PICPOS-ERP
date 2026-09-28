part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// TREASURY & PRINTERS & SETTINGS
// ═══════════════════════════════════════════════════════════════════════════

@TableIndex(name: 'idx_safes_branch', columns: {#branchId})
class Safes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(max: 100)();
  TextColumn get safeType =>
      text().withDefault(const Constant('cash'))(); // cash, bank
  TextColumn get bankName => text().nullable()(); // اسم البنك (مثلاً: البنك الأهلي)
  TextColumn get accountNumber => text().nullable()(); // رقم الحساب البنكي
  RealColumn get balance => real().withDefault(const Constant(0))();
  IntColumn get branchId => integer().nullable().references(Branches, #id)();
  IntColumn get costCenterId => integer().nullable().references(CostCenters, #id)(); // مركز التكلفة المرتبط بالصندوق
  IntColumn get linkedAccountId => integer().nullable().references(Accounts, #id)(); // الحساب المرتبط من شجرة الحسابات
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get regionId => integer().nullable().references(Regions, #id)();
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  // Spec 129 F6 — seeded-default flag (see Branches.isSystemDefault).
  BoolColumn get isSystemDefault => boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

@DataClassName('SafeTransactionData')
@TableIndex(
  name: 'idx_safe_transactions_date_safe',
  columns: {#createdAt, #safeId},
)
@TableIndex(
  name: 'idx_safe_transactions_category',
  columns: {#createdAt, #category},
)
// Perf-01: queries by referenceType + referenceId are issued in every
// void, return and shift-close operation.  Without this index each query
// is a full table scan — critical once SafeTransactions grows large.
@TableIndex(
  name: 'idx_safe_transactions_reference',
  columns: {#referenceType, #referenceId},
)
class SafeTransactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get voucherNumber => text().withLength(max: 50)();
  IntColumn get safeId => integer().references(Safes, #id)();
  TextColumn get transactionType => text()(); // receipt, payment, transfer
  TextColumn get category =>
      text()(); // sales, purchase, expense, salary, advance, other
  RealColumn get amount => real()(); // المبلغ الصافي
  RealColumn get discount => real().withDefault(const Constant(0))(); // مبلغ الخصم المسموح به أو المكتسب
  RealColumn get balanceAfter => real()();
  TextColumn get referenceType => text().nullable()();
  IntColumn get referenceId => integer().nullable()();
  IntColumn get partyId => integer().nullable().references(Parties, #id)();
  TextColumn get description => text().nullable()();
  IntColumn get userId => integer().nullable().references(Users, #id)();
  IntColumn get costCenterId => integer().nullable().references(CostCenters, #id)(); // مركز التكلفة
  IntColumn get employeeId => integer().nullable().references(Employees, #id)(); // الموظف (للرواتب والسلف)
  TextColumn get disbursementType => text().nullable()(); // salary, advance, expense — نوع الصرفية

  /// لقطة تسوية العملة الأجنبية على حركة الخزينة.
  IntColumn get currencyId => integer().nullable().references(Currencies, #id)();
  RealColumn get exchangeRate => real().nullable()();
  RealColumn get foreignAmount => real().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

class Printers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name =>
      text().withLength(max: 100)(); // اسم الطابعة (طابعة المطبخ)
  TextColumn get port => text().nullable()(); // منفذ COM (COM3)
  TextColumn get ipAddress => text().nullable()(); // للطابعات الشبكية
  IntColumn get portNumber => integer().nullable()(); // رقم المنفذ الشبكي
  TextColumn get printerType =>
      text().withDefault(const Constant('thermal'))(); // thermal, network, usb
  TextColumn get purpose => text().withDefault(
    const Constant('pos_receipt'),
  )(); // pos_receipt, kitchen, tables
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get description => text().nullable()(); // وصف اختياري
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text().nullable()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Receipt customization settings - editable from Settings screen
@DataClassName('ReceiptSettingData')
class ReceiptSettings extends Table {
  IntColumn get id => integer().autoIncrement()();

  // Company Information
  TextColumn get companyName =>
      text().withDefault(const Constant('اسم الشركة'))();
  TextColumn get companyAddress => text().nullable()();
  TextColumn get companyPhone => text().nullable()();
  TextColumn get companyPhone2 => text().nullable()();
  TextColumn get companyEmail => text().nullable()();
  TextColumn get taxNumber => text().nullable()();

  // Header & Footer
  TextColumn get headerText =>
      text().withDefault(const Constant('مرحباً بكم'))();
  TextColumn get footerText =>
      text().withDefault(const Constant('شكراً لزيارتكم'))();
  TextColumn get termsText => text().nullable()(); // شروط الدفع

  // Logo
  BlobColumn get logoImage => blob().nullable()();
  BoolColumn get showLogo => boolean().withDefault(const Constant(false))();

  // Display Options
  BoolColumn get showQrCode => boolean().withDefault(const Constant(true))();
  BoolColumn get showBarcode => boolean().withDefault(const Constant(false))();
  BoolColumn get showTaxDetails =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get showItemCode => boolean().withDefault(const Constant(false))();
  BoolColumn get showSalesperson =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get showCustomerInfo =>
      boolean().withDefault(const Constant(true))();

  // Font Sizes (for thermal print)
  IntColumn get headerFontSize => integer().withDefault(const Constant(14))();
  IntColumn get bodyFontSize => integer().withDefault(const Constant(10))();
  IntColumn get footerFontSize => integer().withDefault(const Constant(9))();

  // Paper Width (mm)
  IntColumn get paperWidth =>
      integer().withDefault(const Constant(80))(); // 58mm, 80mm

  // Currency
  TextColumn get currencySymbol => text().withDefault(const Constant('JOD'))();

  // Timestamps
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

// ═══════════════════════════════════════════════════════════════════════════
// v114 / Feature 009 — POS terminals registry (FR-034)
// ═══════════════════════════════════════════════════════════════════════════

/// Master-data registry of every POS terminal (cashier station / lane).
/// Each row binds a unique `deviceId` (UUIDv7 from flutter_secure_storage)
/// to a friendly name and a branch. Required to enable per-terminal policy
/// overrides (FR-017) and traceable per-terminal sales reports.
///
/// Sync policy: serverWins (master data, Constitution III + R5).
///
/// Lifecycle:
///   1. Device generates `device_id` on first launch (DeviceIdentityService).
///   2. Device sends "register-terminal" to server on first online connect.
///   3. Server creates this row (or returns the existing one).
///   4. Subsequent shifts opened on this device populate
///      Shifts.posTerminalId from the resolved id.
@DataClassName('PosTerminalData')
@TableIndex(name: 'idx_pos_terminals_device', columns: {#deviceId})
@TableIndex(name: 'idx_pos_terminals_branch', columns: {#branchId})
class PosTerminals extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(max: 100)();
  TextColumn get deviceId => text().withLength(max: 64).unique()();
  IntColumn get branchId => integer().references(Branches, #id)();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  TextColumn get globalId => text().nullable().unique()();
}
