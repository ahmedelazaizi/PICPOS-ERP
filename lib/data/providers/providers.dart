import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import '../../services/csv_import_export_service.dart';
import '../database/database_barrel.dart';
import '../../core/constants/app_constants.dart';
export '../database/database_barrel.dart';
import '../database/supabase_database.dart';
import '../../services/accounting_service.dart';
import '../../services/accounting_validator.dart';
import '../../services/booking_actions_service.dart';
import 'branch_scope_provider.dart';
// ‏`OrderingTerm` و`&` على تعبيرات drift — الحزمةُ ليست ضمن barrel القاعدة.
import 'package:drift/drift.dart' show OrderingTerm, BooleanExpressionOperators;
import '../../domain/models/picpos_booking_view.dart';
import '../../services/journal_entry_factory.dart';
import '../../services/cost_center_resolver.dart';
import '../../services/kitchen_service.dart';
import '../../services/notification_triggers_service.dart';
import '../../services/reconciliation_service.dart';
import '../../services/fingerprint_service.dart';
import '../../services/api/api_handler_base.dart';
import '../../services/coa_management_service.dart';
import '../../services/table_session_service.dart';
import '../../services/table_checkout_coordinator.dart';
import '../../presentation/widgets/notifications/providers/notification_provider.dart';
import 'repository_providers.dart';

// Domain-specific providers
export 'auth_providers.dart';
export 'branch_scope_provider.dart';
// نطاقُ النسبة (assignableWarehousesProvider / assignableCostCentersProvider)
// — تستعمله المنتقياتُ في ثماني شاشات، فيُصدَّر مع بقيّةِ نطاقات الفروع.
export 'client_scope_provider.dart';
export 'inventory_providers.dart';
export '../../domain/repositories/region_repository.dart';
export 'parties_providers.dart' hide deliveryRepositoryProvider;
export 'sales_providers.dart';
export 'purchases_providers.dart';
export 'quotations_providers.dart';
export 'treasury_providers.dart';
export 'settings_providers.dart';
export 'audit_providers.dart';
export 'repository_providers.dart';

// Conditional import for native database and services
import 'providers_native.dart' if (dart.library.html) 'providers_web_stub.dart';
export 'providers_native.dart' if (dart.library.html) 'providers_web_stub.dart';
import '../../services/theme_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CORE INFRASTRUCTURE PROVIDERS
// ═══════════════════════════════════════════════════════════════════════════

/// Global database provider - uses Drift on desktop
final databaseProvider = Provider<AppDatabase>((ref) {
  if (kIsWeb) {
    throw UnsupportedError('Use supabaseDatabaseProvider on web platform');
  }
  final db = AppDatabase();
  // DO NOT CALL db.close() here. AppDatabase is a global singleton for SQLite,
  // or overridden via withExecutor for PostgreSQL. Closing it will cause 
  // 'This database has already been closed' errors on re-authentication.
  return db;
});

/// Excel service provider - uses ExcelService on desktop, null/stub on web
final excelServiceProvider = Provider<dynamic>((ref) {
  if (kIsWeb) return null;
  return ref.watch(nativeExcelServiceProvider);
});

/// CSV Import/Export service provider
final csvImportExportServiceProvider = Provider<CsvImportExportService>((ref) {
  final productRepo = ref.watch(productRepositoryProvider);
  final partyRepo = ref.watch(partiesRepositoryProvider);
  final db = ref.watch(databaseProvider);
  return CsvImportExportService(productRepo, partyRepo, db);
});

/// Supabase client provider (web only)
final supabaseClientProvider = Provider<SupabaseClient?>((ref) {
  if (kIsWeb) {
    return Supabase.instance.client;
  }
  return null;
});

/// Supabase database provider (web only)
final supabaseDatabaseProvider = Provider<SupabaseDatabase?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client != null) {
    return SupabaseDatabase(client);
  }
  return null;
});

/// Check if using Supabase
final isWebProvider = Provider<bool>((ref) => kIsWeb);

// ═══════════════════════════════════════════════════════════════════════════
// THEME PROVIDER
// ═══════════════════════════════════════════════════════════════════════════

final themeServiceProvider = Provider<ThemeService>((ref) => ThemeService());

/// أفعالُ الحجز التي تُكتب في سجلّ النشاط.
///
/// ⚠️ **كان الصنفُ بلا مزوِّدٍ واحد** — لا يُذكر إلّا في ملفّه، فلا شاشةَ
/// تصل إليه. وهو أحدُ الثلاثةِ الناقصةِ في محرِّك الحجز (المزوِّد · غلافُ
/// `setBookingStatus` · الشاشة).
///
/// و`BookingActionsService` **لا يُعاد تسميتُه** إلى `BookingService`: drift
/// يولّد `class BookingService` صفَّ جدولِ `BookingServices` مفرَداً، وهذا
/// الملفُّ يعيد تصديرَ حزمة القاعدة — فالاسمان يتصادمان بـ`ambiguous_import`
/// في أوّل ملفٍّ يجمعهما. وهذا الملفُّ **هو** ذلك الملفّ.
final bookingActionsServiceProvider = Provider<BookingActionsService>((ref) {
  return BookingActionsService(db: ref.watch(databaseProvider));
});

/// اليومُ المعروضُ على لوحة الحجوزات — منتصفُ ليلِه.
///
/// يُطبَّع إلى منتصف الليل عند الضبط: قيمةٌ تحمل ساعةً تجعل «اليوم» نافذةً
/// متحرّكةً بـ٢٤ ساعةً من لحظة الفتح، فيظهر حجزُ الغدِ الباكرِ في يومِ أمس.
class BookingBoardDayNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => _midnight(DateTime.now());

  static DateTime _midnight(DateTime d) => DateTime(d.year, d.month, d.day);

  void set(DateTime day) => state = _midnight(day);
  void shift(int days) => state = state.add(Duration(days: days));
  void today() => state = _midnight(DateTime.now());
}

final bookingBoardDayProvider =
    NotifierProvider<BookingBoardDayNotifier, DateTime>(
        BookingBoardDayNotifier.new);

/// حجوزاتُ اليوم المعروض — **حيّةً** وبنطاق فرع المستخدم.
///
/// ⚠️ والنطاقُ يُقرأ من `branchScopeProvider` لا يُفترَض: مستخدمٌ بلا إسنادٍ
/// نطاقُه فارغٌ ويجب أن **يفشل مغلقاً** هنا كما في القوائم الأخرى — وإلّا
/// رأى مَن لا فرعَ له كلَّ حجزٍ بفرعٍ معدوم، وفي تنصيبةٍ بفرعٍ واحدٍ ذلك
/// كلُّ الحجوزات.
final bookingsBoardProvider =
    StreamProvider.autoDispose<List<BookingBoardRow>>((ref) async* {
  final db = ref.watch(databaseProvider);
  final day = ref.watch(bookingBoardDayProvider);
  final scope = await ref.watch(branchScopeProvider.future);

  yield* db.watchBookingsBoard(
    day,
    day.add(const Duration(days: 1)),
    allowedBranchIds: scope.hasFullAccess
        ? null
        : scope.allowedBranchIds!.toList(),
  );
});

/// عملاءُ الحجوزات مُجمَّعين — بنفس نطاق فرعِ اللوحة.
final bookingCustomersProvider =
    StreamProvider.autoDispose<List<BookingCustomerRow>>((ref) async* {
  final db = ref.watch(databaseProvider);
  final scope = await ref.watch(branchScopeProvider.future);
  yield* db.watchBookingCustomers(
    allowedBranchIds:
        scope.hasFullAccess ? null : scope.allowedBranchIds!.toList(),
  );
});

/// تذكيراتُ الحجوزات — بنفس نطاق فرعِ اللوحة.
final bookingRemindersProvider =
    StreamProvider.autoDispose<List<BookingReminderRow>>((ref) async* {
  final db = ref.watch(databaseProvider);
  final scope = await ref.watch(branchScopeProvider.future);
  yield* db.watchBookingReminders(
    allowedBranchIds:
        scope.hasFullAccess ? null : scope.allowedBranchIds!.toList(),
  );
});

/// الوجهةُ المعروضةُ من وجهات الحجوزات الثمانِ.
///
/// ⚠️ `Notifier` لا `StateProvider`: الأخيرةُ ليست ضمن Riverpod 3 المستعملةِ
/// هنا، وهذا هو نمطُ الحالة البسيطة في المستودع كلِّه.
class BookingsDestinationNotifier extends Notifier<BookingsDestination> {
  @override
  BookingsDestination build() => BookingsDestination.board;
  void set(BookingsDestination d) => state = d;
}

final bookingsDestinationProvider =
    NotifierProvider<BookingsDestinationNotifier, BookingsDestination>(
        BookingsDestinationNotifier.new);

/// نصُّ البحث السريع في شاشة الحجوزات.
class BookingsQueryNotifier extends Notifier<String> {
  @override
  String build() => '';
  void set(String q) => state = q;
}

final bookingsQueryProvider =
    NotifierProvider<BookingsQueryNotifier, String>(BookingsQueryNotifier.new);

/// الموارد (موظَّفون وأجهزة) — للوحة وللمنتقيات.
final bookingResourcesProvider =
    StreamProvider<List<BookingResource>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.bookingResources)
        ..where((r) => r.deletedAt.isNull())
        ..orderBy([(r) => OrderingTerm.asc(r.sortOrder)]))
      .watch();
});

/// الخدماتُ المعروضة — النشِطةُ وحدَها.
final bookingServicesProvider = StreamProvider<List<BookingService>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.bookingServices)
        ..where((s) => s.deletedAt.isNull() & s.isActive.equals(true))
        ..orderBy([(s) => OrderingTerm.asc(s.sortOrder)]))
      .watch();
});

/// Accounting Service provider
final accountingServiceProvider = Provider<AccountingService>((ref) {
  final accountingRepo = ref.watch(accountingRepositoryProvider);
  final partiesRepo = ref.watch(partiesRepositoryProvider);
  final treasuryRepo = ref.watch(treasuryRepositoryProvider);
  final productRepo = ref.watch(productRepositoryProvider);
  final inventoryRepo = ref.watch(inventoryRepositoryProvider);
  final settingsRepo = ref.watch(settingsRepositoryProvider);
  final auditRepo = ref.watch(auditRepositoryProvider);
  
  return AccountingService(
    accountingRepo,
    partiesRepo,
    treasuryRepo,
    productRepo,
    inventoryRepo,
    settingsRepo,
    auditRepo,
  );
});

/// ISS-08: Direct access to validation sub-service
final accountingValidatorProvider = Provider<AccountingValidator>((ref) {
  return ref.watch(accountingServiceProvider).validator;
});

/// ISS-08: Direct access to JE generation sub-service
final journalEntryFactoryProvider = Provider<JournalEntryFactory>((ref) {
  return ref.watch(accountingServiceProvider).journalFactory;
});

/// ISS-17: Cost center resolver with branch-default fallback
final costCenterResolverProvider = Provider<CostCenterResolver>((ref) {
  final db = ref.watch(databaseProvider);
  return CostCenterResolver(db);
});

/// Kitchen Service provider
final kitchenServiceProvider = Provider<KitchenService>((ref) {
  final kitchenRepo = ref.watch(kitchenRepositoryProvider);
  final productRepo = ref.watch(productRepositoryProvider);
  final printersRepo = ref.watch(printersRepositoryProvider);
  final db = ref.watch(databaseProvider);
  return KitchenService(kitchenRepo, productRepo, printersRepo, db);
});

/// Notification Triggers Service provider
final notificationTriggersServiceProvider = Provider<NotificationTriggersService>((ref) {
  final productRepo = ref.watch(productRepositoryProvider);
  final settingsRepo = ref.watch(settingsRepositoryProvider);
  final notificationService = ref.watch(notificationProvider);
  return NotificationTriggersService(productRepo, settingsRepo, notificationService);
});

final reconciliationServiceProvider = Provider<ReconciliationService>((ref) {
  return ReconciliationService(
    accountingRepo: ref.watch(accountingRepositoryProvider),
    partiesRepo: ref.watch(partiesRepositoryProvider),
    treasuryRepo: ref.watch(treasuryRepositoryProvider),
    productRepo: ref.watch(productRepositoryProvider),
    db: ref.watch(databaseProvider),
  );
});

/// Provides a singleton [FingerprintService] instance.
final fingerprintServiceProvider = Provider<FingerprintService>((ref) {
  final service = FingerprintService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// KDS Ready Orders — stream of today's "ready" orders for POS notification
final kdsReadyOrdersProvider = StreamProvider<List<WorkOrder>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchReadyOrders();
});

/// Table session service — آلةُ حالات الطاولة (فتح/إغلاق/دمج/نقل/دفع).
final tableSessionServiceProvider = Provider<TableSessionService>((ref) {
  return TableSessionService(ref.watch(databaseProvider));
});

/// منسّقُ تحصيل الطاولة — يبني خطط التقسيم ويسوّي حصصها. المصدرُ الوحيدُ
/// المصرَّحُ به لطبقة العرض للوصول إلى منطق التقسيم بلا استيراد `data/database`
/// مباشرةً (راجع `presentation_db_import_guard_test.dart`).
final tableCheckoutCoordinatorProvider = Provider<TableCheckoutCoordinator>((
  ref,
) {
  return TableCheckoutCoordinator(
    db: ref.watch(databaseProvider),
    session: ref.watch(tableSessionServiceProvider),
  );
});

class ThemeModeNotifier extends Notifier<ThemeMode> {
  late final ThemeService _service;

  @override
  ThemeMode build() {
    _service = ref.read(themeServiceProvider);

    // Attempt to load saved theme mode
    // Note: build() should return a value immediately.
    // For persistent states, we usually initialize with a default
    // or use a separate initialization flow.
    // Here we use ThemeMode.light as default.
    return ThemeMode.light;
  }

  /// Load the saved theme mode from persistent storage
  Future<void> init() async {
    final savedMode = await _service.getThemeMode();
    state = savedMode;
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    await _service.saveThemeMode(mode);
  }

  // Backward compatibility for old calls
  void setDarkMode(bool value) {
    setMode(value ? ThemeMode.dark : ThemeMode.light);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(() {
  return ThemeModeNotifier();
});

/// ── System Currency ──────────────────────────────────────────────────
class SystemCurrencyNotifier extends Notifier<String> {
  @override
  String build() => AppConstants.currencyCode; // default

  /// Initialize from DB
  Future<void> init() async {
    final db = ref.read(databaseProvider);
    final saved = await db.getSettingValue('system_currency');
    if (saved != null && saved.isNotEmpty) {
      AppConstants.setCurrency(saved);
      state = saved;
    }
  }

  /// Change currency and persist.
  ///
  /// ⚠️ **يُرفَض بعد أوّل حركةٍ ماليّة** (‏م-٢، قرارُ المالك 2026-08-23).
  /// دقّةُ العملة تتبع العملةَ الآن (الدينارُ ٣ والجنيهُ ٢)، فالتبديلُ بعد
  /// أن تُكتب أرقامٌ في الدفاتر يُعيد `12.345` إلى `12.35` وقد يُخلّ قيداً
  /// اتّزن بثلاث خانات. العملةُ قرارُ تنصيبٍ لا تفضيلُ عرض.
  ///
  /// والرفضُ هنا **لا في الواجهة وحدَها**: المنتقي مُعطَّلٌ في الإعدادات،
  /// لكنّ الواجهةَ تُلتَفّ (استدعاءٌ برمجيّ، مزامنة، سكربت) — فالحارسُ
  /// الحقيقيُّ يقع عند الكتابة. وتبديلٌ إلى نفس العملة الحاليّة يمرّ: ليس
  /// تبديلاً أصلاً.
  Future<void> setCurrency(String code) async {
    final db = ref.read(databaseProvider);
    final normalized = CurrencyInfo.fromCode(code).code;
    if (normalized != AppConstants.currencyCode &&
        await db.hasAnyFinancialMovement()) {
      throw StateError(
        'لا يمكن تبديل عملة النظام بعد تسجيل حركات مالية. العملة تحدَّد عند '
        'التنصيب لأن دقّتها العشرية جزءٌ من كل مبلغ محفوظ وكل قيد مرحَّل — '
        'وتبديلها الآن يعيد تقريب المبالغ القائمة وقد يُخلّ قيوداً متّزنة.',
      );
    }
    await db.setSetting('system_currency', code);
    AppConstants.setCurrency(code);
    state = code; // triggers rebuild of all watchers
  }
}

/// هل تبديلُ العملة مقفولٌ الآن؟ — للواجهة كي تُعطّل المنتقيَ وتشرح السبب.
///
/// والحارسُ الحقيقيُّ في `SystemCurrencyNotifier.setCurrency`؛ هذا للعرض.
final currencyChangeLockedProvider = FutureProvider<bool>((ref) async {
  // يُعاد حسابُه مع كلّ تغيّرٍ في المبيعات أو المشتريات، فالقفلُ يظهر فور
  // أوّل فاتورةٍ بلا إعادةِ تشغيل.
  ref.watch(salesInvoicesChangeProvider);
  ref.watch(purchaseInvoicesChangeProvider);
  return ref.read(databaseProvider).hasAnyFinancialMovement();
});

final systemCurrencyProvider = NotifierProvider<SystemCurrencyNotifier, String>(
  () {
    return SystemCurrencyNotifier();
  },
);

// ═══════════════════════════════════════════════════════════════════════════
// SERVER-SIDE DATA CHANGE NOTIFIER (auto-refresh reports)
// ═══════════════════════════════════════════════════════════════════════════

/// Stream of table names changed on the server via API.
/// Report screens watch this to auto-refresh when a client submits data.
final serverDataChangeProvider = StreamProvider<String>((ref) {
  // Import here to avoid circular — only used at runtime on server
  return ApiHandlerBase.onDataChanged;
});

/// Auto-incrementing version counter for sales data.
/// Reports watch this to trigger reloads.
class SalesDataVersionNotifier extends Notifier<int> {
  @override
  int build() {
    // Listen for server API data changes
    ref.listen<AsyncValue<String>>(serverDataChangeProvider, (_, next) {
      next.whenData((table) {
        if (table == 'sales' || table == 'held_orders') {
          state++;
        }
      });
    });
    return 0;
  }

  void increment() => state++;
}

final salesDataVersionProvider =
    NotifierProvider<SalesDataVersionNotifier, int>(
  () => SalesDataVersionNotifier(),
);

// ═══════════════════════════════════════════════════════════════════════════
// ISS-06: PRESENTATION-LAYER FACADE PROVIDERS
// These wrap direct DB calls so presentation screens don't access the
// database directly. Each provider delegates to the appropriate DAO via
// the existing databaseProvider singleton.
// ═══════════════════════════════════════════════════════════════════════════

/// Monthly expense summary for a date range.
/// Used by analytics dashboard instead of direct db.getMonthlyExpenseSummary().
final monthlyExpenseSummaryProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, ({DateTime from, DateTime to})>((ref, range) {
  final db = ref.watch(databaseProvider);
  return db.getMonthlyExpenseSummary(from: range.from, to: range.to);
});

/// Resolve branch → warehouse IDs for branch-based filtering.
final branchWarehouseIdsProvider = FutureProvider.autoDispose
    .family<List<int>, int>((ref, branchId) async {
  final branchRepo = ref.watch(branchRepositoryProvider);
  final warehouses = await branchRepo.getWarehousesByBranch(branchId);
  return warehouses.map((w) => w.id).toList();
});

/// Resolve branch → safe IDs for treasury branch-based filtering.
final branchSafeIdsProvider = FutureProvider.autoDispose
    .family<List<int>, int>((ref, branchId) async {
  final db = ref.watch(databaseProvider);
  final branchSafes = await (db.select(db.safes)
        ..where((s) => s.branchId.equals(branchId)))
      .get();
  return branchSafes.map((s) => s.id).toList();
});

/// Batch-load party names by IDs. Used by returns screens.
final partyNamesMapProvider = FutureProvider.autoDispose
    .family<Map<int, String>, List<int>>((ref, ids) {
  final db = ref.watch(databaseProvider);
  return db.getPartyNamesMap(ids);
});

/// Audit dashboard hash-chain statistics.
final auditDashboardStatsProvider = FutureProvider.autoDispose<({
  Map<String, int> hashStats,
  int conflictCount,
})>((ref) async {
  final db = ref.watch(databaseProvider);
  final dao = db.auditDashboardDao;
  final stats = await dao.getHashChainStats();
  final conflicts = await dao.getUnresolvedConflictCount();
  return (hashStats: stats, conflictCount: conflicts);
});

/// Audit dashboard hash-chain verification.
final auditHashChainVerifyProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final db = ref.watch(databaseProvider);
  return db.auditDashboardDao.verifyHashChain();
});

/// Sync conflicts for the conflicts screen.
final syncConflictsProvider = FutureProvider.autoDispose
    .family<({
  List<dynamic> conflicts,
  List<String> tableNames,
}), String?>((ref, tableName) async {
  final db = ref.watch(databaseProvider);
  final dao = db.auditDashboardDao;
  final conflicts = await dao.getSyncConflicts(tableName: tableName, limit: 200);
  final tables = await dao.getConflictTableNames();
  return (conflicts: conflicts, tableNames: tables);
});

/// Resolve a sync conflict.
final resolveSyncConflictProvider = FutureProvider.autoDispose
    .family<void, ({int id, String resolution})>((ref, params) async {
  final db = ref.watch(databaseProvider);
  await db.auditDashboardDao.resolveConflict(params.id, params.resolution);
});

/// Validate fiscal period for a given date and operation.
final fiscalPeriodValidationProvider = FutureProvider.autoDispose
    .family<void, ({DateTime date, String operation})>((ref, params) async {
  final db = ref.watch(databaseProvider);
  await db.validateFinancialPeriod(params.date, operation: params.operation);
});

/// Stream that emits whenever the salesInvoices table changes.
///
/// NOT autoDispose: keeping this alive for the app's lifetime guarantees
/// that inserts happening while a subscriber is NOT currently mounted
/// (e.g., a sale completed in POS while the sales-list screen was
/// dormant) are still reflected when the screen returns — the current
/// subscriber always sees the latest Drift watch snapshot on subscribe.
/// Cost: one always-on watch query; negligible memory overhead.
///
/// ── لماذا عدّادٌ لا `void` (‏بلاغُ المالك 2026-08-23) ─────────────────────
/// كانت `StreamProvider<void>` نهايتُها `.map((_) {})`، فكلُّ بثٍّ يحمل نفسَ
/// القيمة. وRiverpod لا يُخطر المستمعَ إلّا حين تتبدّل الحالةُ بالمساواة،
/// و`AsyncData<void>(null) == AsyncData<void>(null)`. فالبثُّ الأوّلُ يوقظ
/// المستمعَ و**ما بعده يُبتلَع صامتاً** — وهو بالضبط «جدولُ الفواتير لا
/// يتحدّث بعد الحفظ».
///
/// وهذا يفسّر ما بدا متناقضاً في السجلّ: بيعُ نقطةِ البيع يظهر فوراً لأنّ
/// `checkout_controller` يُبطل المزوِّدَ صراحةً فتمرّ الحالةُ بـ`AsyncLoading`
/// — تبدّلٌ حقيقيّ. أمّا الحفظُ من «فاتورة جديدة» فلا يُبطل شيئاً.
///
/// ⚠️ والعدّادُ ليس زينةً: أيُّ قيمةٍ ثابتةٍ تُعيد العطبَ. والمستهلكون كلُّهم
///    يتجاهلون القيمةَ (`(_, _) =>`)، فالتبديلُ لا يمسّ عقدَ أحد.
final salesInvoicesChangeProvider = StreamProvider<int>((ref) {
  final db = ref.watch(databaseProvider);
  var tick = 0;
  return db.select(db.salesInvoices).watch().map((_) => ++tick);
});

/// Same rationale as salesInvoicesChangeProvider — live notifications for
/// the purchase invoices list. والعدّادُ لنفس السبب المكتوبِ فوق.
final purchaseInvoicesChangeProvider = StreamProvider<int>((ref) {
  final db = ref.watch(databaseProvider);
  var tick = 0;
  return db.select(db.purchaseInvoices).watch().map((_) => ++tick);
});

/// CoA management service provider for chart of accounts import/export.
final coaManagementServiceProvider = Provider<dynamic>((ref) {
  final db = ref.watch(databaseProvider);
  return CoaManagementService(db);
});

/// Authenticate user by password or card (admin verification).
final authenticateByPasswordOrCardProvider = FutureProvider.autoDispose
    .family<dynamic, String>((ref, input) {
  final authRepo = ref.watch(authRepositoryProvider);
  return authRepo.authenticateByPasswordOrCard(input);
});

/// Get unit by barcode for POS barcode scanning.
final unitByBarcodeProvider = FutureProvider.autoDispose
    .family<ProductUnit?, String>((ref, barcode) {
  final db = ref.watch(databaseProvider);
  return db.getUnitByBarcode(barcode);
});

/// Branch-user mapping for activity log branch filtering.
final branchUserMappingProvider = FutureProvider.autoDispose<Map<int, Set<int>>>((ref) async {
  final branchRepo = ref.watch(branchRepositoryProvider);
  final branches = await branchRepo.getBranches();
  final users = ref.read(reportingRepositoryProvider).watchAllUsers();
  final allUsers = await users.first;
  final mapping = <int, Set<int>>{};
  for (final branch in branches) {
    final userIds = <int>{};
    for (final uw in allUsers) {
      final accessIds = await branchRepo.getUserAccessibleBranchIds(uw.user.id);
      if (accessIds.isEmpty || accessIds.contains(branch.id)) {
        userIds.add(uw.user.id);
      }
    }
    mapping[branch.id] = userIds;
  }
  return mapping;
});

/// Get held order with items for printing.
final heldOrderWithItemsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>?, int>((ref, orderId) {
  final db = ref.watch(databaseProvider);
  return db.getHeldOrderWithItems(orderId);
});

/// Sales return item details for viewing return contents.
final salesReturnItemDetailsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, int>((ref, invoiceId) {
  final db = ref.watch(databaseProvider);
  return db.getSalesReturnItemDetails(invoiceId);
});

/// Purchase return item details for viewing return contents.
final purchaseReturnItemDetailsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, int>((ref, invoiceId) {
  final db = ref.watch(databaseProvider);
  return db.getPurchaseReturnItemDetails(invoiceId);
});

/// Get sales invoice by ID (for edit flow).
final salesInvoiceByIdProvider = FutureProvider.autoDispose
    .family<dynamic, int>((ref, invoiceId) {
  final db = ref.watch(databaseProvider);
  return db.getSalesInvoiceById(invoiceId);
});

/// Get product by ID (presentation-layer convenience).
final productByIdProvider = FutureProvider.autoDispose
    .family<dynamic, int>((ref, productId) {
  final db = ref.watch(databaseProvider);
  return db.getProductById(productId);
});
