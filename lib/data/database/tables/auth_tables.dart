part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ROLES & PERMISSIONS
// ═══════════════════════════════════════════════════════════════════════════

/// User roles (أدوار المستخدمين)
class Roles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(max: 50)(); // مدير، كاشير، مخزني
  TextColumn get description => text().nullable()();
  BoolColumn get isSystemRole =>
      boolean().withDefault(const Constant(false))(); // أدوار النظام لا تُحذف
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

/// Permission definitions (تعريف الصلاحيات)
class Permissions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get code => text().unique()(); // pos_access, inventory_view
  TextColumn get name => text()(); // الوصول للبيع السريع
  TextColumn get category => text()(); // pos, inventory, settings
}

/// Role-Permission mapping (ربط الأدوار بالصلاحيات)
class RolePermissions extends Table {
  IntColumn get roleId => integer().references(Roles, #id)();
  IntColumn get permissionId => integer().references(Permissions, #id)();

  /// نمطُ المنح — `allow` أو `conditional`.
  ///
  /// ═══ لماذا عمودٌ ولم يكن ═══
  ///
  /// كان الجدولُ **جدولَ وجودٍ لا حالة**: صفٌّ موجودٌ = ممنوح، وغيابُه =
  /// ممنوع. وتصميمُ «مصفوفة الأدوار والصلاحيات» (`BENCH.perms`) يرسم خليّةً
  /// **ثلاثيّة**: مسموح · **مشروط** · ممنوع، ويصف المشروطَ بأنّه «يحتاج
  /// موافقةً أو حدّاً». وأمرُ المالك 2026-08-25: ابنِها.
  ///
  /// ═══ ما يعنيه «مشروط» بدقّة ═══
  ///
  /// الصلاحيةُ **ممنوحةٌ** (‏فصفُّها موجودٌ والشاشاتُ تظهر)، لكنّ تنفيذَها
  /// يمرّ بموافقة مسؤولٍ في كلّ مرّة. وهذا ليس اختراعَ آليّةٍ جديدة:
  /// `ensurePermission` تملك مسارَ `requestManagerApproval` منذ اليوم،
  /// والمشروطُ يمنعها من الاختصار عند فحص المِلك ويُنزلها إليه.
  ///
  /// ⚠️ **والافتراضُ `allow` لا `conditional`** — والفرقُ أمنيٌّ في اتّجاهه:
  /// ترقيةُ قاعدةٍ قائمةٍ تُبقي كلَّ منحةٍ كما كانت. ولو كان الافتراضُ
  /// مشروطاً لتحوّل كلُّ نظامٍ قائمٍ فجأةً إلى سؤال مسؤولٍ في كلّ ضغطة.
  TextColumn get grantMode => text().withDefault(const Constant('allow'))();

  @override
  Set<Column> get primaryKey => {roleId, permissionId};
}

// ═══════════════════════════════════════════════════════════════════════════
// USERS & AUTHENTICATION
// ═══════════════════════════════════════════════════════════════════════════

class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get username => text().withLength(min: 3, max: 50)();
  TextColumn get passwordHash => text()();
  TextColumn get passwordSalt =>
      text().withDefault(const Constant(''))(); // For secure password hashing
  TextColumn get displayName => text().withLength(max: 100)();
  IntColumn get roleId =>
      integer().nullable().references(Roles, #id)(); // New: role reference
  TextColumn get pin => text().nullable()(); // PIN للتبديل السريع
  TextColumn get defaultScreen =>
      text().withDefault(const Constant('pos'))(); // الشاشة الافتراضية
  BoolColumn get isLocked =>
      boolean().withDefault(const Constant(false))(); // حساب مقفل
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  RealColumn get maxDiscountPercent =>
      real().nullable()(); // حد الخصم الأقصى - null = بلا حد
  BoolColumn get discountLimitIsPercent => boolean().withDefault(
    const Constant(true),
  )(); // true = نسبة%, false = قيمة ثابتة
  TextColumn get cardCode => text().nullable()(); // كود كارت MSR للتسجيل السريع
  BoolColumn get forcePasswordChange =>
      boolean().withDefault(const Constant(false))(); // إجبار تغيير كلمة المرور
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

// ═══════════════════════════════════════════════════════════════════════════
// USER ACCESS CONTROL — Branch & Warehouse Restrictions (N3/N4)
// ═══════════════════════════════════════════════════════════════════════════

/// Which branches a user can access (empty = all branches for backward compat)
class UserBranchAccess extends Table {
  IntColumn get userId => integer().references(Users, #id)();
  IntColumn get branchId => integer().references(Branches, #id)();

  @override
  Set<Column> get primaryKey => {userId, branchId};
}

/// Which warehouses a user can access (empty = all warehouses for backward compat)
class UserWarehouseAccess extends Table {
  IntColumn get userId => integer().references(Users, #id)();
  IntColumn get warehouseId => integer().references(Warehouses, #id)();

  @override
  Set<Column> get primaryKey => {userId, warehouseId};
}

// ═══════════════════════════════════════════════════════════════════════════
// ACTIVITY LOGS (سجل العمليات)
// ═══════════════════════════════════════════════════════════════════════════

/// Activity logs for tracking all user actions (#14)
@TableIndex(name: 'idx_activity_logs_date', columns: {#createdAt})
@TableIndex(name: 'idx_activity_logs_user', columns: {#userId})
@TableIndex(name: 'idx_activity_logs_action', columns: {#action})
@TableIndex(name: 'idx_activity_logs_entity', columns: {#entityType, #entityId})
@TableIndex(name: 'idx_activity_logs_user_date', columns: {#userId, #createdAt})
@TableIndex(name: 'idx_activity_logs_global_id', columns: {#globalId})
@TableIndex(name: 'idx_activity_logs_modified', columns: {#lastModifiedAt})
class ActivityLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get userId => integer().nullable().references(Users, #id)();
  TextColumn get userName => text()(); // اسم المستخدم (cached)
  TextColumn get action =>
      text()(); // sale, refund, delete_product, edit_price, etc.
  TextColumn get entityType => text()(); // invoice, product, customer, setting
  IntColumn get entityId => integer().nullable()(); // ID of affected entity
  TextColumn get description => text()(); // وصف تفصيلي للعملية
  TextColumn get oldValue => text().nullable()(); // القيمة القديمة (للتعديلات)
  TextColumn get newValue => text().nullable()(); // القيمة الجديدة
  RealColumn get amount => real().nullable()(); // المبلغ (للعمليات المالية)
  TextColumn get ipAddress => text().nullable()(); // IP address
  TextColumn get deviceInfo => text().nullable()(); // معلومات الجهاز
  TextColumn get hash => text().nullable()(); // ICR-03: هاش السجل (SHA256)
  TextColumn get previousHash => text().nullable()(); // ICR-03: هاش السجل السابق (سلسلة)
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  // ── Sync columns (added for multi-client activity log sync) ──
  TextColumn get globalId => text().nullable().unique()(); // UUIDv7 للتعريف الفريد بين الأجهزة
  TextColumn get originClientId => text().nullable()(); // معرّف العميل الذي أنشأ السجل
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();

  // v138 (Issue 18 cleanup): branch_id stamped at write time so the
  // activity-log screen's branch filter can narrow rows at SQL level
  // instead of approximating from user_branch_access mappings (which
  // misclassified users moved between branches).
  IntColumn get branchId => integer().nullable().references(Branches, #id)();
}

class UserRegionAccess extends Table {
  IntColumn get userId => integer().references(Users, #id)();
  IntColumn get regionId => integer().references(Regions, #id)();
  @override
  Set<Column> get primaryKey => {userId, regionId};
}
