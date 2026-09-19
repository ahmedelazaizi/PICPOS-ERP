import '../../core/constants/payment_methods.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:drift/drift.dart';
import 'package:rxdart/rxdart.dart' show DebounceExtensions; // Spec 115 L2 — debounceTime
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';
// Import treasury_repository.dart for DAO types (SafeData, TreasurySummaryData, etc.)
import '../../domain/repositories/treasury_repository.dart';
import '../../domain/models/receipt_qr_decision.dart'
    show kEInvoiceEnabledSettingKey;
import 'connection.dart';
import 'pg_compat_sql.dart';
import 'wal_checkpoint.dart';
import '../../domain/models/return_original_link.dart';
import '../../domain/models/invoice_due_date.dart';
import '../../domain/models/journal_balance.dart';
import '../../domain/models/purchase_line_discount.dart';
import '../../services/security_service.dart';
import '../../domain/models/quick_sale_policy.dart'
    show kQuickSaleReceiptTemplateKey, quickSaleReceiptTemplateFile;
import '../../services/printing/template_resolver.dart';
import '../../services/printing/paper_compatibility.dart';
import '../../services/password_collision_scanner.dart';
import '../../services/journal_entry_diagnostics.dart';
import '../../core/config/app_config.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/stock_movement_types.dart';
import '../../core/auth/bootstrap_admin.dart';
import '../../core/logging/diagnostic_logger.dart';
import '../../core/permissions/permission_codes.dart';
import '../../core/utils/arabic_utils.dart';
// Spec 139 — deterministic JE balancing uses FinancialUtils' minor-unit helpers
// and the single balance-tolerance source of truth. `show` avoids importing its
// UnbalancedJournalException (a different type lives in journal_entry_factory).
import '../../core/utils/date_utils.dart' show DateUtils;
import '../../core/utils/financial_utils.dart' show FinancialUtils;
import '../../core/utils/sales_payment_calculator.dart';
import '../../core/utils/uuid_v7.dart';
import '../../core/utils/journal_entry_gid.dart';
// Replaced license_service with trial_state to break cycles.
import '../../core/trial/trial_state.dart';
import '../../domain/entities/product_entity.dart';
import '../../services/invoice_integrity_service.dart';
import '../../services/role_grant_preflight_service.dart';
import '../../domain/entities/accounting_entities.dart';
import 'sync_interceptor.dart';
import '../../services/sync/mirror_settings_keys.dart';
// Removing error_handler to break cycle
import 'daos/audit_dashboard_dao.dart';
// Feature 004 (US1): Exception types for the auto-account-linkage path.
import 'daos/account_linkage_exceptions.dart';
export 'daos/account_linkage_exceptions.dart';
// Feature 004 (US3): Mutation guard mirror for read-only-on-disconnect.
import '../../core/mutation_guard.dart';
export '../../core/mutation_guard.dart';
// Feature 009 (Auto-Deplete BOM): exceptions + stock-shortage policy enum
// used by _consumeBomComponentsAtomic in manufacturing_dao.dart and by
// applyAutoDepleteForSale (T015).
import 'daos/manufacturing_exceptions.dart';
export 'daos/manufacturing_exceptions.dart';
import '../../services/stock_shortage_policy_service.dart';
export '../../services/stock_shortage_policy_service.dart' show StockShortagePolicy;
// Feature 009 (T012h): shift-open populates Shifts.posTerminalId from this
// service so the per-terminal stock-shortage policy tier (FR-017) can
// resolve at sale time. Null-tolerant — see treasury_dao.dart openShift.
import '../../services/pos_terminal_registration_service.dart';
// 062 (D1-004) — PermissionEnforcer for critical financial ops.
import '../../services/permission_enforcer.dart';
import '../../core/config/brand.dart';
// قاعدةُ إشارة حركة الخزنة — مصدرٌ واحدٌ يشترك فيه الاستعلامُ والشاشة، فلا
// تُنسخ داخل `CASE` في SQL ثم تنحرف عن نسختها بأوّل نوعٍ جديد.
import '../../domain/models/safe_running_balance.dart';
// تقريرُ الطاولات: النوعُ الذي يعبر إلى التقرير خالصٌ، فالتجميعُ يُختبَر بلا
// قاعدة. و`TableOrderTotals` هو محرّكُ الخصم الوحيد — لا تُنسَخ قاعدتُه هنا.
import '../../domain/models/table_order_totals.dart';
import '../../domain/models/tables_report_row.dart';
import '../../domain/models/booking_overlap.dart';
import '../../domain/models/picpos_booking_view.dart';
import '../../domain/models/shift_drawer_resolver.dart';
export '../../services/permission_enforcer.dart' show PermissionDeniedException;

part 'database.g.dart';

// DAO EXTENSIONS
part 'daos/product_crud_dao.dart';
part 'daos/product_barcode_units_dao.dart';
part 'daos/sales_dao.dart';
part 'daos/sales_mutations_dao.dart';
part 'daos/sales_actions_dao.dart';
part 'daos/sales_held_orders_dao.dart';
part 'daos/sales_analytics_dao.dart';
part 'daos/purchase_dao.dart';
part 'daos/purchase_reports_dao.dart';
part 'daos/treasury_dao.dart';
part 'daos/treasury_reports_dao.dart';
part 'daos/user_dao.dart';
part 'daos/party_dao.dart';
part 'daos/tables_dao.dart';
part 'daos/bookings_dao.dart';
part 'daos/inventory_dao.dart';
part 'daos/inventory_batch_dao.dart';
part 'daos/inventory_transfers_dao.dart';
part 'daos/offers_dao.dart';
part 'daos/settings_dao.dart';
part 'daos/printer_dao.dart';
part 'daos/permissions_dao.dart';
part 'daos/delivery_dao.dart';
part 'daos/kitchen_dao.dart';
part 'daos/branches_dao.dart';
part 'daos/regions_dao.dart';
part 'daos/accounting_dao.dart';
part 'daos/accounting_dao_reads.dart';
part 'daos/accounting_dao_writes.dart';
part 'daos/accounting_autopost_dao.dart';
part 'daos/autopost_repair_dao.dart';
part 'daos/accounting_reports_dao.dart';
part 'daos/accounting_fiscal_dao.dart';
part 'daos/accounting_audit_dao.dart';
part 'daos/commercial_papers_dao.dart';
part 'daos/multi_currency_pricelist_dao.dart';
part 'daos/manufacturing_dao.dart';
part 'daos/fixed_assets_dao_ext.dart';
part 'daos/e_invoicing_dao.dart';
part 'daos/activity_logs_dao.dart';
part 'daos/invoice_template_dao.dart';
part 'daos/template_binding_dao.dart';
part 'daos/invoice_template_seeder_dao.dart';
part 'daos/sync_dao.dart';
part 'daos/quotations_dao.dart';
part 'daos/scale_dao.dart';
part 'daos/purchase_orders_dao.dart';
part 'daos/modifiers_dao.dart';
// fixed_assets_dao.dart merged into fixed_assets_dao_ext.dart (Phase 3.2 God DAO split)
part 'daos/sales_orders_dao.dart';
part 'daos/bank_reconciliation_dao.dart';
part 'daos/data_maintenance_dao.dart';
part 'daos/multi_currency_dao.dart';
part 'daos/budgeting_dao.dart';
part 'daos/deferred_schedule_dao.dart';
part 'daos/approval_workflow_dao.dart';
part 'daos/sod_matrix_dao.dart';
part 'daos/consolidated_statements_dao.dart';
part 'daos/intercompany_dao.dart';
part 'daos/restatement_dao.dart';
part 'daos/compliance_dashboard_dao.dart';
part 'daos/journal_template_dao.dart';
part 'daos/field_audit_dao.dart';
part 'daos/cycle_count_dao.dart';
part 'daos/landed_cost_dao.dart';
part 'daos/api_key_dao.dart';
part 'daos/report_builder_dao.dart';
part 'daos/notification_dao.dart';
part 'daos/operational_expenses_dao.dart';
part 'daos/fk_resolver_dao.dart';
part 'daos/work_holidays_dao.dart';
part 'daos/party_engagement_dao.dart';
// Seeding & Projections
part 'database_seeder.dart';
part 'database_seeder_permissions.dart';
part 'database_seeder_accounts.dart';
part 'database_seeder_postgres.dart';
part 'database_migrations.dart';
part 'database_startup.dart';
part 'migrations/epoch_1.dart';
part 'migrations/epoch_2.dart';
part 'migrations/epoch_3.dart';
part 'models/projections.dart';

// Table Definitions
part 'tables/auth_tables.dart';
part 'tables/inventory_tables.dart';
part 'tables/product_tables.dart';
part 'tables/sales_purchase_tables.dart';
part 'tables/restaurant_tables.dart';
part 'tables/accounting_tables.dart';
part 'tables/treasury_settings_tables.dart';
part 'tables/delivery_tables.dart';
part 'tables/kitchen_tables.dart';
part 'tables/hr_tables.dart';
part 'tables/scale_tables.dart';
part 'tables/audit_tables.dart';
part 'tables/sync_tables.dart';
part 'tables/invoice_template_tables.dart';
part 'tables/commercial_finance_tables.dart';
part 'tables/manufacturing_assets_tables.dart';
part 'tables/e_invoicing_tables.dart';
part 'tables/loyalty_tables.dart';
part 'tables/distribution_tables.dart';
part 'tables/party_engagement_tables.dart';
part 'tables/document_sequences.dart';
part 'tables/quotation_tables.dart';
part 'tables/operational_expenses_tables.dart';
part 'tables/bank_reconciliation_tables.dart';
part 'tables/enterprise_tables.dart';
part 'tables/phase9_enterprise_tables.dart';
part 'tables/journal_template_tables.dart';
part 'tables/field_audit_tables.dart';
part 'tables/cycle_count_tables.dart';
part 'tables/landed_cost_tables.dart';
part 'tables/api_key_tables.dart';
part 'tables/report_builder_tables.dart';
part 'tables/booking_tables.dart';

/// The primary industry mode for the application, controlling which
/// screens and features are available (e.g. restaurant tables, café menus).
enum IndustryMode { supermarket, restaurant, cafe, retail }

// ═══════════════════════════════════════════════════════════════════════════
// SPEC 130 — PG SCHEMA PARITY EXCEPTION
// ═══════════════════════════════════════════════════════════════════════════
//
// Thrown by `_ensurePostgresSchemaParity()` when the parity pass cannot
// close schema gaps because of an unrecoverable error (DDL permission
// denied, connection lost, etc.). Caller (main_desktop.dart) MUST route
// to FatalSetupErrorApp per Spec 130 Clarification Q2 (Block-all):
// no reads + no writes until resolved or user clicks "إعادة محاولة".
//
// Distinct from runtime DDL errors that the pass tolerates (e.g.,
// column type drift, extra PG tables) — those are warn-only.
// ═══════════════════════════════════════════════════════════════════════════
class PgSchemaParityException implements Exception {
  /// Arabic message for FatalSetupErrorApp display.
  final String reasonAr;

  /// English details for DiagnosticLogger / support call-in.
  final List<String> details;

  /// Entity names that the pass couldn't heal (e.g., table names).
  final List<String> failedEntities;

  const PgSchemaParityException({
    required this.reasonAr,
    this.details = const [],
    this.failedEntities = const [],
  });

  @override
  String toString() =>
      'PgSchemaParityException(reasonAr=$reasonAr, '
      'failedEntities=$failedEntities, details=$details)';
}

/// In-memory snapshot of a single PG column from `information_schema.columns`.
/// Lowercased everywhere for case-insensitive comparison.
class _PgLiveColumn {
  final String pgType;
  final bool nullable;
  const _PgLiveColumn({required this.pgType, required this.nullable});
}

/// Captured DDL failure during the parity pass. Aggregated and converted to
/// [PgSchemaParityException] at end-of-pass.
class _PgParityFatal {
  final String entity;
  final String detail;
  const _PgParityFatal({required this.entity, required this.detail});
}

/// 066 (D5-001) — read-only audit result row from
/// [AppDatabase.auditNumberingGaps]. Egyptian VAT prohibits auto-renumbering;
/// callers display this to the accountant, who decides whether to post
/// compensating void rows. See
/// specs/066-voucher-numbering-atomicity/contracts/numbering-atomicity.md.
///
/// NOTE: kept ABOVE `@DriftDatabase(...)` so the annotation binds to
/// `AppDatabase` (the very next class declaration) and not to this one.
/// drift_dev attaches each `@DriftDatabase` to the next class in source
/// order — placing this class between the annotation and `AppDatabase`
/// caused build_runner to emit `_$NumberingGapReport extends GeneratedDatabase`
/// instead of `_$AppDatabase`, breaking every `flutter analyze` call.
class NumberingGapReport {
  final String prefix;
  final int counterNext;
  final int maxUsedNumber;
  final int gapCount;
  const NumberingGapReport({
    required this.prefix,
    required this.counterNext,
    required this.maxUsedNumber,
    required this.gapCount,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Spec 151 — auto-post dedup UNIQUE index: single source of truth
// ═══════════════════════════════════════════════════════════════════════════
//
/// Name of the partial UNIQUE index that backstops duplicate auto-posted JEs
/// for the same `(reference_type, reference_id)` pair (originally added in the
/// v120 migration).
const String kJeAutopostDedupIndexName = 'idx_je_autopost_dedup';

/// Canonical CREATE statement for [kJeAutopostDedupIndexName] — the ONE place
/// the index shape is defined. Referenced by (a) the v150 migration step,
/// (b) the fresh-install `onCreate` SQLite path, and (c) the every-boot
/// `ensureSchemaDefaults` self-heal, so all three agree.
///
/// Spec 151: return JEs are now keyed on the ORIGINATING invoice id
/// (`referenceId = invoice.id`), so multiple partial returns of one invoice
/// legitimately share `(reference_type, reference_id)`. Their per-event
/// uniqueness rides on `journal_entries.global_id` (its own UNIQUE constraint),
/// NOT on this index — so the return types are exempted here.
///
/// The exemption list MUST stay in lock-step with `createJournalEntry`'s
/// `multiJeReferenceTypes` guard: EVERY reference type that legitimately posts
/// more than one auto-posted JE per `referenceId` is exempt. Besides the two
/// return types that Spec 151 re-keyed, that set already includes
/// `commercial_paper` (one JE per lifecycle status: deposited → cashed …) and
/// `partial_collection` (one JE per instalment). Omitting those here would let
/// the index — once it lives on fresh installs (b) — reject the second
/// lifecycle/instalment JE that the in-code guard deliberately allows.
///
/// SQLite-only (partial index `WHERE …`). Postgres never carried this index
/// (the v120 migration was SQLite-only and it is not a Drift schema entity), so
/// we do NOT create it on PG — matching existing behavior.
/// أنواعُ المراجع التي تُنتج **قيداً لكلِّ حدثٍ** لا قيداً لكلِّ مرجع.
///
/// هذه هي القائمةُ الواحدةُ التي يقرؤها الطرفان: حارسُ
/// `createJournalEntry` في التطبيق، و`NOT IN` في الفهرس أدناه. وكانا
/// مكتوبَين مرّتين، والوثيقةُ تقول «لا بدّ أن يبقيا متطابقَين» — ولا شيءَ
/// يفرض ذلك.
///
/// 🔴 **وقع فعلاً 2026-08-27:** أُضيف `asset_depreciation` إلى حارس التطبيق
/// وحدَه، فصار الترحيلُ يمرّ الحارسَ ثمّ يصطدم بـ`UNIQUE constraint failed`
/// في الفهرس. و`runMonthlyDepreciation` يلتقط الاستثناءَ **لكلِّ أصلٍ على
/// حدة** ويتخطّاه، فتراجعت المعاملةُ كلُّها: لا قيدَ ولا صفَّ إهلاكٍ ولا
/// بطاقةٌ متقدّمة. أي أنّ الإهلاكَ **توقّف** بعد شهره الأوّل — والمصالحةُ
/// مرّت خضراءَ لأنّ الطرفَين تساويا عند الرقم الخاطئ.
///
/// و`e_je_dedup_lockstep_test.dart` يثبّت التطابقَ الآن.
const Set<String> kMultiJeReferenceTypes = {
  // Spec 151 (A-01/F-02) — قيودُ المردودات مفتاحُها فاتورةُ المنشأ ليتمكّن
  // `cancelSalesReturn` / `editPurchaseReturn` من عكسها بذلك الرقم. وفاتورةٌ
  // واحدةٌ تحمل مردوداتٍ جزئيّةً متعدّدة، فتفرّدُها يركب على `globalId`
  // الحتميِّ لا على `(refType, refId)`.
  'sales_return',
  'purchase_return',
  // قيدٌ لكلِّ انتقالِ حالة: pending → deposited → cashed.
  'commercial_paper',
  // قيدٌ لكلِّ قسطِ تحصيل.
  'partial_collection',
  // 🔴 v168 (‏2026-08-27) — كشفته مصالحةُ الأصول في المرحلة ٤، ولا يظهر في
  // أيّ اختبارِ وحدة.
  //
  // الإهلاكُ قيدٌ لكلِّ **شهر**، و`referenceId` رقمُ الأصل **بلا فترة**.
  // فأصلٌ يُهلَك شهريّاً كان يُرحَّل في شهره الأوّل فقط، ويُعَدّ كلُّ شهرٍ
  // تالٍ «مكرَّراً» فيُبتلَع — بينما صفُّ `asset_depreciations` يُكتَب
  // و`fixed_assets.accumulated_depreciation` يتقدّم كالمعتاد.
  //
  // والأثرُ يتراكم صامتاً: مجمَّعُ الإهلاك في الأستاذ يتجمّد عند شهرٍ واحدٍ
  // لكلّ أصل، فالأصولُ الثابتةُ **مضخَّمةٌ** في الميزانيّة ومصروفُ الإهلاك
  // **منقوصٌ** في قائمة الدخل — ربحٌ أعلى من حقيقته وضريبةُ دخلٍ على أساسٍ
  // خاطئ. والشاشاتُ تقرأ البطاقةَ لا الأستاذ، فتبدو سليمةً تماماً.
  //
  // مقيسٌ: ثلاثةُ أشهرٍ ⇒ البطاقةُ ٦٠٠ والأستاذُ ٢٠٠، وصفوفُ الإهلاك
  // الثلاثةُ كلُّها تشير إلى **نفس** رقم القيد.
  //
  // وتفرّدُه لكلِّ حدثٍ محفوظٌ في موضعه الصحيح: `runMonthlyDepreciation`
  // يفحص `(assetId, periodDate)` ويتخطّى المُهلَك سلفاً قبل أن يصل هنا.
  'asset_depreciation',
};

const String kCreateJeAutopostDedupIndexSql =
    'CREATE UNIQUE INDEX IF NOT EXISTS $kJeAutopostDedupIndexName '
    'ON journal_entries(reference_type, reference_id) '
    'WHERE is_auto_posted = 1 '
    "AND reference_type NOT IN "
    "('sales_return', 'purchase_return', 'commercial_paper', "
    "'partial_collection', 'asset_depreciation')";

/// أنواعُ المراجع التي تُصنَّف **أنشطةً استثماريّةً** في قائمة التدفّقات
/// النقديّة (‏IAS 7.16) — وهي عينُ ما يكتبه محرّكُ الأصول الثابتة.
///
/// 🔴 **وقع فعلاً:** كانت القائمةُ مكتوبةً مرّتين حرفيّاً داخلَ
/// `getCashFlowStatement` — في `NOT IN` التشغيليّة وفي `IN` الاستثماريّة —
/// وكلتاهما تحملان `'asset_acquisition'` و`'asset_disposal'`، **ولا يكتب
/// المستودعُ كلُّه أيّاً منهما**. والمحرّكُ في
/// `fixed_assets_dao_ext.dart` يكتب `'fixed_asset'` للاقتناء
/// و`'fixed_asset_disposal'` للاستبعاد.
///
/// فكلُّ شراءِ أصلٍ أو بيعِه نقداً كان يقع في **القِسم الخطأ مرّتين**:
/// لا يُستثنى من التشغيليّة (فيُحتسَب «مدفوعاتٍ/مقبوضاتٍ أخرى» في فرع
/// `default:`)، ولا يظهر في الاستثماريّة (فتُقرأ صفراً). وصافي التغيّر في
/// النقديّة يبقى صحيحاً لأنّ المبلغَ لم يضِعْ بل انتقل — فلا يمسكه أيُّ
/// فحصِ اتّزان، والمكسورُ هو الفصلُ الذي هو **غرضُ القائمة الأوّل**.
///
/// مقيسٌ قبل الإصلاح: أصلان نقداً بـ١٣٠٠٠٠ وبيعٌ بـ٣٠٠٠٠ ⇒ الاستثماريّةُ
/// `0.0` والتشغيليّةُ خارجاً `130000.0`.
///
/// و`'asset_transfer'` و`'asset_revaluation'` كانا مطابقَين في الطرفَين
/// أصلاً، فبقيا كما هما.
///
/// ⚠️ **و`'asset_depreciation'` ليس هنا بقصد**: قيدُه مدين `6213` / دائن
/// مجمَّعُ الإهلاك، ولا رِجْلَ له على النقد. وترشيحا القائمة **كلاهما**
/// مقيَّدان بحسابات النقد/البنك، فالإهلاكُ يُقرأ صفراً في الطرفَين بلا
/// تصنيف. والقائمةُ هنا تُبنى بالمنهج **المباشر** (جمعُ رِجْلِ النقد) لا
/// غيرِ المباشر (الربحُ ثمّ إضافةُ غير النقديّ عكسيّاً — IAS 7.20)، فلا
/// إضافةَ عكسيّةً للإهلاك تُصنَع أصلاً. ويثبّت ذلك
/// `ias7_fixed_asset_cashflow_classification_test.dart` قياساً لا افتراضاً.
///
/// والقائمةُ **واحدةٌ لا اثنتان**: الطرفان يقرآنها من هنا،
/// و`ias7_reference_type_lockstep_guard_test.dart` يشتقُّ ما يكتبه المحرّك
/// من الملفِّ نفسِه ويرفض أيَّ نوعٍ جديدٍ غيرِ مصنَّف.
const Set<String> kInvestingJeReferenceTypes = {
  'fixed_asset', // الاقتناء — fixed_assets_dao_ext.dart
  'fixed_asset_disposal', // الاستبعاد
  'asset_transfer',
  'asset_revaluation',
};

/// أنواعُ مراجع **قيدِ فاتورة المشتريات** — اسمان لقيدٍ واحد.
///
/// ⚠️ **ولهما مصدران مختلفان يكتبان نفسَ المستند:** المسارُ المُدمَج في
/// `createPurchaseInvoice` يختم `'purchase_invoice'`، و`autoPostPurchase`
/// يختم `'purchase'`. فأيُّ قارئٍ يفحص أحدَهما وحدَه يقرأ نصفَ الفواتير
/// «غيرَ مُرحَّلة» وهي مُرحَّلة.
///
/// وهي مقروءةٌ في ثلاثة مواضعَ: عكسُ القيد عند التعديل، وعكسُه عند الإلغاء،
/// وعمودُ «حالة الترحيل» في شاشة الاستعلام. وثلاثُ نسخٍ يدويّةٍ من نفس
/// القائمة تفترق في أوّل نوعٍ يُضاف — وهي بعينها عائلةُ عطبِ
/// [kInvestingJeReferenceTypes] أعلاه: طرفان يكتبان ويقرآن ولا يعرف
/// أحدُهما الآخر. فالقائمةُ **واحدةٌ** و`purchase_je_reference_lockstep_
/// guard_test.dart` يرفض أيَّ مُرشِّحٍ يكتبها بيده.
const Set<String> kPurchaseJeReferenceTypes = {
  'purchase_invoice', // المسارُ المُدمَج — createPurchaseInvoice
  'purchase', // الترحيلُ الآليّ — autoPostPurchase
};

/// أنواعُ المراجع المصنَّفةُ **أنشطةً تمويليّةً** (‏IAS 7.17).
const Set<String> kFinancingJeReferenceTypes = {'commercial_paper'};

/// يصيّر مجموعةَ أنواعٍ إلى قائمةِ SQL حرفيّة: `'a', 'b'`.
///
/// المُدخَلُ ثوابتُ ترجمةٍ لا مُدخَلُ مستخدمٍ، فلا مسرحَ لحقنٍ هنا —
/// والمتغيّراتُ المرقَّمةُ لا تُستعمل لأنّ الترشيحَ يُركَّب داخلَ نصٍّ
/// يحمل `?` لتواريخَ ومرشِّحاتٍ أخرى، فإدخالُ عددٍ متغيّرٍ منها يُزيح
/// ترتيبَ الوسائط.
String sqlRefTypeList(Iterable<String> types) =>
    types.map((t) => "'$t'").join(', ');

/// B1 — قيد قاعدة البيانات ضد صرف الراتب مرتين لنفس الفترة.
///
/// الحارس في `recordSalaryPayment` على مستوى التطبيق، وبيقفل الحالة الشائعة
/// (ضغطتين على نفس الجهاز). لكنه **مش كافٍ**: كاتب متزامن من جهاز تاني بيقرا
/// «مفيش صرف سابق» في نفس اللحظة، فالاتنين بيعدّوا الفحص ويكتبوا. ده الطبقة
/// اللي بتمنع ده.
///
/// `type` جزء من المفتاح بقصد — مكافأة أو سلفة لنفس الفترة التزام مختلف لا
/// تكرار للراتب.
///
/// ⚠️ `period` عمود nullable، وSQLite بيعتبر الـNULLات متمايزة في الفهرس
/// الفريد. فصفوف بلا فترة **مش محروسة** — وده **مطابق عن قصد** لحارس التطبيق:
/// `p.period.equals(null)` بيترجم لـ`= NULL` اللي عمره ما بيتحقق. التطابق بين
/// الطبقتين أهم من إحكام أكتر في طبقة واحدة، لأن اختلافهما بينتج رفضاً من
/// القاعدة بلا رسالة مفهومة من التطبيق.
const String kSalaryPaymentDedupIndexName = 'idx_salary_payments_period_dedup';
const String kCreateSalaryPaymentDedupIndexSql =
    'CREATE UNIQUE INDEX IF NOT EXISTS $kSalaryPaymentDedupIndexName '
    'ON salary_payments(employee_id, period, type)';

/// B2 — قيد قاعدة البيانات ضد تكرار صف الحضور لنفس اليوم.
///
/// استيراد البصمة بقى يعمل upsert على (‏employeeId, date)، لكن ده كود تطبيق
/// كمان. والحضور بيتحوّل لفلوس مباشرةً (الراتب بيعدّ صفوف `present`)، فصف
/// مكرر واحد = يوم عمل مدفوع مرتين.
const String kAttendanceDayDedupIndexName = 'idx_employee_attendance_day_dedup';
const String kCreateAttendanceDayDedupIndexSql =
    'CREATE UNIQUE INDEX IF NOT EXISTS $kAttendanceDayDedupIndexName '
    'ON employee_attendance(employee_id, date)';

/// ٦‑١ — سجلُّ حالات الفاتورة الإلكترونيّة: جدولٌ **غائبٌ عن كلِّ تنصيبةٍ
/// SQLite جديدة**.
///
/// 🔴 `EInvoiceStatusLog` له صنفُ جدولٍ في `e_invoicing_tables.dart` لكنّه
/// **غيرُ مُعلَنٍ في `@DriftDatabase`**. و`onCreate` يبني من كيانات drift،
/// و`onUpgrade` لا يعمل على تنصيبةٍ جديدة — فالهجرةُ v81 التي تُنشئه لا
/// تصل إلّا القواعدَ المُرقَّاة. أمّا PostgreSQL فمغطًّى بكتلةٍ خاصّةٍ في
/// مسار التكافؤ.
///
/// والنتيجةُ على SQLite الجديد: `e_invoicing_dao` يكتب ويقرأ الجدولَ بـSQL
/// خامٍّ (‏`INSERT INTO` و`SELECT * FROM`) فيفشل بـ«no such table» — وهو
/// **عينُ العطب** الذي عولج هنا لفهارس v150/v152 وv159 بنفس التعليل.
///
/// فالـDDL مصدرٌ واحدٌ تقرؤه ثلاثةُ أطراف: الهجرةُ، و`onCreate`، والشفاءُ
/// الذاتيُّ كلَّ إقلاع — وإلّا افترقت وعادت الفجوةُ من بابٍ آخر.
///
/// v173 — **صار الصنفُ مُعلَناً في `@DriftDatabase`** فيبنيه `createAll`
/// و`_createAllForPostgres` كأيّ كيان، وهذا الـDDL بقي شفاءً ذاتيّاً
/// للقواعد التي سبقت الإعلان. ويحمل أعمدةَ المزامنة الخمسةَ ليتطابق مع
/// الكيان: سجلُّ حالات الفاتورة الإلكترونيّة إثباتٌ رقابيٌّ يُزامَن.
const String kCreateEInvoiceStatusLogSql = '''
CREATE TABLE IF NOT EXISTS e_invoice_status_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  submission_id INTEGER NOT NULL REFERENCES e_invoice_submissions(id),
  old_status TEXT,
  new_status TEXT NOT NULL,
  changed_by TEXT,
  notes TEXT,
  changed_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
  global_id TEXT UNIQUE,
  last_modified_at INTEGER,
  deleted_at INTEGER,
  origin_client_id TEXT,
  row_version INTEGER NOT NULL DEFAULT 0
)''';
const String kCreateEInvoiceStatusLogIndexSql =
    'CREATE INDEX IF NOT EXISTS idx_einv_status_log_submission '
    'ON e_invoice_status_log(submission_id)';

/// v159 — المسارُ الساخنُ لمحرِّك الحجز: `getOverlappingBookings`.
///
/// كلُّ إنشاءِ حجزٍ وكلُّ نقلٍ أو تأجيلٍ أو إحياءٍ يشغّل استعلامَ مرشَّحين
/// على `(resource_id, starts_at)` بالضبط — داخل معاملةٍ تحجز الكتابة. وبلا
/// فهرسٍ فهو مسحُ جدولٍ كاملٍ ينمو بعمر المنشأة.
///
/// **وليس فريداً** — بخلاف فهرسَي B1/B2: التداخلُ يُمنَع بالفحص في الـDAO
/// لا بقيدٍ، وصفّان على نفس الموظَّف في نفس اللحظةِ **مشروعان** ما دام
/// أحدُهما `cancelled` أو `no_show`. فهرسٌ فريدٌ هنا كان سيمنع الصحيح.
///
/// ومحلُّه v159 عينُها: الجدولُ جديدٌ لم يُشحَن، فالتنصيبُ الجديدُ يأخذه من
/// `onCreate` والمُرقّى من الهجرة، بلا نسخةِ مخطّطٍ ثانية.
const String kBookingResourceSlotIndexName = 'idx_bookings_resource_starts_at';
const String kCreateBookingResourceSlotIndexSql =
    'CREATE INDEX IF NOT EXISTS $kBookingResourceSlotIndexName '
    'ON bookings(resource_id, starts_at)';

/// ٦‑٣ — تفرّدُ ربطِ الحسابات على (‏الغرض، مركزُ التكلفة).
///
/// `getAccountByPurpose` يختار بـ`limit(1)` بلا `orderBy`، فصفّان لنفس الغرض
/// يجعلان **اختيارَ الحساب غيرَ حتميّ**: نفسُ الفاتورةِ قد تُرحَّل على حسابٍ
/// اليومَ وعلى آخرَ غداً. والازدواجُ ميدانيٌّ مُوثَّقٌ في
/// `accounting_dao_writes.dart` (‏«mirror sync replays can leave more than one
/// row per purpose key») — و`.limit(1)` هناك مسكّنٌ للعَرَض لا علاجٌ للجذر.
///
/// ⚠️ **و`UNIQUE(purpose, cost_center_id)` لا يعالجه**: الربطُ العامُّ
/// `cost_center_id IS NULL`، و`NULL` لا يساوي `NULL` في قيدِ تفرّد — فالصفُّ
/// الذي يزدوج هو بعينه الصفُّ الذي يفلت. ولذلك الفهرسُ **تعبيريٌّ** على
/// `coalesce(cost_center_id, 0)`، وهو الشكلُ المكتوبُ أصلاً في ثلاثِ خطواتِ
/// هجرةٍ في `epoch_3.dart` — لكنّ `onCreate` يبني من كيانات drift و`onUpgrade`
/// لا يعمل على قاعدةٍ جديدةٍ ومتجاوَزٌ كلّيّاً على PG، فلم يصل تنصيبةً واحدة.
///
/// والمُعلَنُ في صنف الجدول `@TableIndex(idx_account_mappings_purpose)` —
/// غيرُ فريدٍ وعلى الغرض وحدَه — فلا يسدّ شيئاً من هذا.
const String kAccountMappingsPurposeCcIndexName =
    'idx_account_mappings_purpose_cc';
const String kCreateAccountMappingsPurposeCcIndexSql =
    'CREATE UNIQUE INDEX IF NOT EXISTS $kAccountMappingsPurposeCcIndexName '
    'ON account_mappings(purpose, coalesce(cost_center_id, 0))';

/// §٣‑٦ — قيدُ قاعدةٍ ضدّ تغطيةِ سطرَي كشفٍ بنكيٍّ بقيدٍ واحد.
///
/// المطابقةُ الآليّةُ تُقصي سطرَ القيد المستعملَ سلفاً (`l.id NOT IN (...)`)،
/// واليدويّةُ صارت ترمي عليه — **لكنّ الاثنين كودُ تطبيق**. ونفسُ حجّةِ فهرسَي
/// B1/B2 تسري هنا حرفاً: الأثرُ ماليّ.
///
/// فسطرا كشفٍ يُغلقان على نفسِ سطر القيد يُعَدّان مطابَقَين اثنَين، وينخفض
/// «غيرُ المطابَق» بمقدارَين، فتبدو المطابقةُ تامّةً بينما حركةٌ بنكيّةٌ كاملةٌ
/// بلا ما يقابلها في الدفتر. وهذا **يُخفي** الفرقَ بدل أن يُظهره — وإظهارُه
/// هو الغرضُ الوحيدُ من المطابقة.
///
/// ⚠️ **ولا حاجةَ لفهرسٍ جزئيّ**: العمودُ nullable، و`UNIQUE` تعامل `NULL`
/// قيماً **متمايزةً** في SQLite وPostgreSQL معاً — فآلافُ الأسطر غير المطابَقة
/// (`matched_journal_line_id IS NULL`) لا تتصادم.
///
/// ⚠️ **ولا تسويةَ آليّةً قبله** — نفسُ سياسة B1/B2 لا سياسةِ ربطِ الحسابات:
/// الصفُّ الزائدُ هنا **حركةٌ ذاتُ قيمةٍ ماليّة** لا إعداداً، فحذفُه قرارُ
/// محاسبٍ لا قرارُ إقلاع. وعلى بياناتٍ مزدوجةٍ تفشل الجملةُ بصمتٍ ويبقى حارسُ
/// التطبيق.
const String kBankStatementMatchDedupIndexName =
    'idx_bank_stmt_matched_je_line_dedup';
const String kCreateBankStatementMatchDedupIndexSql =
    'CREATE UNIQUE INDEX IF NOT EXISTS $kBankStatementMatchDedupIndexName '
    'ON bank_statement_lines(matched_journal_line_id)';

/// تسويةُ المزدوج **قبل** تركيب [kCreateAccountMappingsPurposeCcIndexSql].
///
/// قرارُ المالك 2026-08-31: **يبقى الأحدثُ بـ`updated_at`**، والتعادلُ يُحسَم
/// بأكبر `id`. المنطق: آخرُ ما اختاره المستخدمُ في شاشة ربط الحسابات هو
/// نيّتُه الحاليّة.
///
/// ⚠️ والترتيبُ مُلزِم: القيدُ على بياناتٍ مزدوجةٍ يفشل، وحلقةُ الشفاء الذاتيِّ
/// **تبتلع الفشلَ بصمت** — فتخرج القاعدةُ بلا حمايةٍ ولا بلاغ. ولذلك يُثبِت
/// الاختبارُ وجودَ الفهرس **بعد** التسوية لا نجاحَ الجملة.
///
/// وهذا يخالف عمداً سياسةَ فهرسَي B1/B2 المجاورَين (‏«التسويةُ اليدويّةُ شغلُ
/// محاسبٍ لا شغلُ إقلاع»): هناك الصفُّ الزائدُ حركةٌ لها قيمةٌ ماليّةٌ مستقلّة،
/// وهنا الصفُّ الزائدُ **إعدادٌ** مكرَّرٌ لا حركةَ فيه — وبقاؤه هو الضرر.
///
/// الصيغةُ مكتوبةٌ بمقارنةٍ مترابطةٍ لا بدوالِّ نوافذَ كي تعمل حرفيّاً على
/// SQLite وPostgreSQL معاً.
const String kDedupAccountMappingsSql = '''
DELETE FROM account_mappings
WHERE id NOT IN (
  SELECT m.id
  FROM account_mappings m
  WHERE m.id = (
    SELECT m2.id
    FROM account_mappings m2
    WHERE m2.purpose = m.purpose
      AND coalesce(m2.cost_center_id, 0) = coalesce(m.cost_center_id, 0)
    ORDER BY m2.updated_at DESC, m2.id DESC
    LIMIT 1
  )
)''';

// ═══════════════════════════════════════════════════════════════════════════
// DATABASE CLASS
// ═══════════════════════════════════════════════════════════════════════════

@DriftDatabase(
  tables: [
    Roles, // User roles
    Permissions, // Permission definitions
    RolePermissions, // Role-Permission mapping
    Users,
    UserBranchAccess, // N3: User-branch access control
    UserWarehouseAccess, // N3: User-warehouse access control
    UserRegionAccess, // Region-level access control
    Regions,
    Branches,
    Warehouses,
    Units,
    Categories,
    CategoryBranches, // PIR R-10: Category-Branch visibility join table
    Products,
    ProductBarcodes,
    ProductUnits,
    ProductBatches, // Batch tracking for expiry
    PartyGroups,
    Parties,
    PurchaseInvoices,
    PurchaseInvoiceItems,
    // v174 - تفاصيلُ فاتورة الاستيراد (١:١ مع الفاتورة)
    ImportPurchaseDetails,
    // §٦‑٢ — مستندُ مرتجع المشتريات. جدولٌ **مستقلٌّ** عمداً: صفٌّ في
    // `purchase_invoices` كان سيدخل خمسةً وثلاثين استعلامَ مشترياتٍ قائماً.
    PurchaseReturns,
    SalesInvoices,
    SalesInvoiceItems,
    Offers,
    OfferItems,
    TableSections, // NEW: Restaurant sections
    RestaurantTables, // NEW: Restaurant tables
    TableOrders, // NEW: Table orders
    TableOrderItems, // NEW: Items in table orders
    // v174 - معالمُ القاعة غيرُ الطاولات
    FloorPlanItems,
    TableReservations, // NEW: Table reservations
    TableOrderPayments, // v154: دفعةٌ لكلّ دافعٍ على طلب الطاولة
    BookingResources, // v159: «الموظفون / الموارد» — مَن يُحجَز وقتُه
    BookingServices, // v159: الخدماتُ المعروضة للحجز
    Bookings, // v159: مواعيدُ الخدمة — مستقلّةٌ عن TableReservations
    BookingReminders, // v161: تذكيرُ الموعد — «فُتحت» لا «أُرسلت»
    StockMovements,
    InventoryBalances,
    Accounts,
    JournalEntries,
    JournalEntryLines,
    Safes,
    SafeTransactions,
    Printers, // Work order printers
    PosTerminals, // v146 / Feature 009: POS terminal registry (FR-034)
    HeldOrders, // Held/suspended orders
    HeldOrderItems, // Items in held orders
    DeliveryCompanies,
    Couriers,
    Settings,
    // KDS Tables
    WorkOrders,
    WorkOrderItems,
    KitchenStations,
    // Spec 130 root-cause: the table class existed in kitchen_tables.dart
    // but was never registered here, so Drift never emitted a CREATE TABLE.
    // On PG installs this manifested as
    //   42P01 relation "category_station_mappings" does not exist
    // on every POS sale that hit KitchenDao.getStationForCategory.
    CategoryStationMappings,
    // HR Tables
    Employees,
    EmployeeAttendance,
    SalaryPayments,
    EmployeeTransactions, // NEW: Advances and deductions
    EmployeeLeaves, // Phase 5: Leave management
    LeaveBalances, // Phase 5: Leave balance tracking
    OvertimeRecords, // Phase 5: Overtime tracking
    FingerprintDevices, // Phase 5: Biometric device registry
    PerformanceReviews, // Phase 9: HR Performance evaluation
    PerformanceGoals, // Phase 9: Employee goal tracking
    EmployeeContracts, // Phase 9: Employment contracts
    WorkHolidays, // v153: Hourly wage/overtime — holiday calendar
    // Stock Audit Tables
    StockAudits,
    StockAuditItems,
    ReceiptSettings, // Receipt/Invoice customization
    ActivityLogs, // Audit trail for all user actions (#14)
    // Invoice Template Designer Tables
    InvoiceTemplates,
    InvoiceTemplateElements,
    InvoiceTableSettings,
    TemplateBindings,
    // Phase 2: Inventory Bonds
    InventoryBonds,
    InventoryBondItems,
    StockRequisitions, // Phase 2: Cross-Branch Stock Requisition
    StockRequisitionItems, // Phase 2: Cross-Branch Stock Requisition
    Shifts, // #Phase4: Operational Auditing
    LabelScales, // #Phase5: Multi-scale PLU export registry
    // Phase 1: Advanced Accounting
    CostCenters,
    FiscalYears,
    AccountingPeriods, // PIR Phase 1.5: Monthly period locking
    ActivityProfiles,
    // Phase 2: Commercial Papers & Finance
    // v174 - دفترُ الشيكات الصادرة، وهو قبلَ CommercialPapers
    // لأنَّ الأخيرَ صار يشير إليه بـchequeBookId.
    ChequeBooks,
    CommercialPapers,
    PaperStatusHistory,
    Currencies,
    ExchangeRateHistory,
    PriceLists,
    PriceListItems,
    // Phase 3: Manufacturing & Assets
    BillOfMaterials,
    BomComponents,
    ManufacturingOrders,
    AssetCategories,
    FixedAssets,
    // v174 - طلبُ استبعاد أصلٍ: مستندٌ بدورةِ حياة
    AssetDisposals,
    AssetDepreciations,
    // Phase 4: E-Invoicing
    EInvoiceConfigs,
    EInvoiceSubmissions,
    // v173 — كان صنفاً بلا إعلانٍ (٦‑١) يُبنى بـSQL خامٍّ في ثلاثة مواضع.
    // صار كياناً كأخواته: `onCreate` و`_createAllForPostgres` يبنيانه
    // بأعمدة المزامنة، والـSQL الخامُّ أدناه بقي شفاءً ذاتيّاً لا مصدراً.
    EInvoiceStatusLog,
    TaxTypes,
    TaxSubtypes,
    // Phase 5.2: Loyalty Points
    LoyaltyPrograms,
    CustomerLoyaltyPoints,
    LoyaltyTransactions,
    // Phase 5.3: Distribution & Sales Reps
    SalesRoutes,
    RouteVisits,
    SalesRepTargets,
    SalesRepCollections,
    // Phase 7: Sync Engine
    SyncOutbox,
    SyncConflictLog,
    AccountMappings,
    DocumentSequences,
    Quotations,
    QuotationItems,
    // Phase 8: Operational Expenses
    OpExpenseCategories,
    OpExpenses,
    MfgOrderCosts,
    // v146 / Feature 009: Auto-Deplete BOM consumption log
    SaleBomConsumptions,
    // Phase 8.1: Purchase Orders
    PurchaseOrders,
    PurchaseOrderItems,
    WarehousePrices, // v69: Per-warehouse product pricing
    // Phase 9: Sales Orders
    SalesOrders,
    SalesOrderItems,
    // Phase 10: Independent Payments
    Payments,
    PaymentAllocations,
    // Phase 11: Bank Reconciliation
    BankStatementLines,
    BankReconciliations,
    // Phase 12: Enterprise — Budgeting, Deferred, Approvals, SOD
    Budgets,
    BudgetLines,
    DeferredSchedules,
    DeferredEntries,
    ApprovalWorkflows,
    ApprovalSteps,
    ApprovalRequests,
    ApprovalDecisions,
    SodConflicts,
    SodViolations,
    // Phase 13: Enterprise Advanced — Consolidation, Intercompany, Restatement, Compliance
    Entities,
    EntityMappings,
    IntercompanyTransactions,
    Restatements,
    RestatementLines,
    ComplianceChecks,
    // Phase 14: Journal Entry Templates
    JournalEntryTemplates,
    JournalEntryTemplateLines,
    // Phase 15: Notifications
    Notifications,
    // Phase C7: Field-Level Audit Logging
    FieldAuditLogs,
    // Phase C4: Cycle Counting
    CycleCountPlans,
    CycleCountTasks,
    CycleCountItems,
    // Phase C2: Landed Cost
    LandedCostSheets,
    LandedCostItems,
    LandedCostAllocations,
    // Phase C1: API Keys
    ApiKeys,
    // Phase C5: Report Builder
    CustomReports,
    SavedReportRuns,
    // API Idempotency
    ProcessedMessages,
    // P2.2: FK remap table (replaces JSON blob in settings)
    RemoteIdMappings,
    // PIR P0-04: Failed Autopost monitoring
    FailedAutoposts,
    // v165 — سجلّا تواصلٍ لا قيدَين: متابعةُ التحصيل ومطالبةُ المورد.
    PartyFollowUps,
    SupplierClaims,
  ],
)
/// MonixaERP ERP Core Database.
///
/// Drift-powered SQLite database with 41 schema versions, full-text search,
/// and 16 DAO extensions covering products, sales, purchases, treasury,
/// inventory, users, permissions, HR, delivery, kitchen, and audit logging.
///
/// Uses the SINGLETON PATTERN: `AppDatabase()` always returns the same instance.
/// This prevents multiple SQLCipher connections that would each run their own
/// `beforeOpen` seeder, leading to inconsistent data (e.g., password hash corruption).
///
/// `AppDatabase.forTesting()` opens an in-memory connection for tests (not singleton).
class AppDatabase extends _$AppDatabase {
  /// Whether this database is backed by PostgreSQL (affects migration behavior)
  final bool _isPostgres;

  /// Singleton instance for the default SQLite connection
  static AppDatabase? _instance;

  /// Factory constructor — returns the singleton SQLite instance.
  /// Every call to `AppDatabase()` returns the SAME database connection.
  factory AppDatabase() {
    _instance ??= AppDatabase._internal();
    return _instance!;
  }

  /// Private internal constructor — called only once
  AppDatabase._internal() : _isPostgres = false, super(openConnection());

  // Backwards compatibility for refactored DAOs
  AppDatabase get accountingDao => this;
  AppDatabase get quotationsDao => this;
  AppDatabase get journalTemplateDao => this;

  /// Opens the database using a custom [QueryExecutor] (e.g., PostgreSQL).
  /// NOT a singleton — each PostgreSQL config gets its own instance.
  AppDatabase.withExecutor(super.executor, {bool isPostgres = false})
      : _isPostgres = isPostgres;

  /// Opens an in-memory database for widget / integration tests.
  /// NOT a singleton — each test gets its own isolated database.
  AppDatabase.forTesting() : _isPostgres = false, super(openTestConnection()) {
    // Clear top-level caches to prevent cross-test contamination
    resetProductCaches();
  }

  /// Whether this database is backed by PostgreSQL (public read-only accessor
  /// used by DAOs that need to generate database-agnostic raw SQL).
  bool get isPostgres => _isPostgres;

  /// Open-transaction depth. Nested transactions (savepoints) push it further,
  /// so it only returns to zero once the OUTERMOST one has settled.
  int _txDepth = 0;

  /// True while any transaction is open on this database.
  ///
  /// Read caches must not be populated or served while this is true. A read
  /// taken mid-transaction sees state that may never be committed, and the
  /// product cache is process-global and has no notion of rollback — so one
  /// such read outlives the transaction and is handed to every later reader.
  /// That is not merely a stale display: `updateProductWAC` computes the
  /// weighted average from a cached `currentStock`/`costPrice` pair and WRITES
  /// the result, turning a poisoned read into stored cost.
  ///
  /// Bypassing reads as well as writes is deliberate — inside a transaction a
  /// caller must see its OWN uncommitted writes, which a pre-transaction
  /// cache entry would hide.
  ///
  /// ⚠️ **Deliberately over-conservative.** drift runs a transaction body in
  /// its own zone, so `resolvedEngine is Transaction` is scoped to the code
  /// actually inside it. This counter is a plain instance field, so it reads
  /// true for EVERY caller on this database while any transaction is open —
  /// a POS barcode lookup during invoice posting bypasses the cache too, and
  /// (because the write side is skipped as well) stays cold.
  ///
  /// That is safe but not free: correctness is unaffected — a database read is
  /// always at least as correct as a memoised one — while cache hit rate drops
  /// for the duration of any transaction. The zone-scoped alternative is
  /// `resolvedEngine`, which is `@internal` and cannot be used without
  /// breaking `flutter analyze`. **The performance cost is UNMEASURED**;
  /// measuring barcode-scan latency on weak hardware is a tracked follow-up.
  bool get isInTransaction => _txDepth > 0;

  @override
  Future<T> transaction<T>(
    Future<T> Function() action, {
    bool requireNew = false,
  }) {
    return super.transaction(() async {
      _txDepth++;
      try {
        return await action();
      } finally {
        _txDepth--;
      }
    }, requireNew: requireNew);
  }

  // ───────────────────────────────────────────────────────────────────────
  // 🔴 توافقُ PostgreSQL في مسار الإقلاع — `beforeOpen` يتخطّى المُعترِض
  // ───────────────────────────────────────────────────────────────────────
  //
  // الاتصالُ بـPostgreSQL يُلفّ بـ`_PgCompatInterceptor`
  // (`connection_io.dart`: ‏`PgDatabase(...).interceptWith(...)`) وهو يترجم
  // كلَّ SQL خامّ: ‏`strftime` و`julianday` و`GROUP_CONCAT` و**علامةَ
  // الاستفهام** `? → $1, $2, …` (‏`PgCompatSql.fixSql` خطوة ١٠).
  //
  // ⚠️ **لكنّ ما يعمل داخلَ `beforeOpen` لا يمرُّ بالمُعترِض.** مقيسٌ في سياق
  // الإقلاع نفسِه على PostgreSQL حيّة:
  //
  //     SELECT ?  AS a   ⇒ 42601: syntax error at or near "AS"
  //     SELECT $1 AS a   ⇒ يعمل
  //
  // ونفسُ الجملتين خارجَ الإقلاع تعملان — فالفارقُ السياقُ لا الجملة.
  //
  // والأثرُ المقيس: `syncAllPermissions` تموت عند **أوّل** إدراج، ومعها
  // `grantMissingDefaults` (أوّلُ سطرٍ فيها ينادي الأولى). وكلاهما مبتلَعٌ في
  // `catch` يطبع سطراً ويمضي. فعلى خادم PostgreSQL: التنصيبُ الأوّلُ سليمٌ
  // (معالجُ البدء خارجَ `beforeOpen`)، لكنّ **أيَّ صلاحيّةٍ تضيفها نسخةٌ لاحقةٌ
  // لا تصل القاعدةَ أبداً** ولا تُمنَح لمدير النظام.
  //
  // فالترجمةُ تُطبَّق هنا كذلك — عند المصدر لا عند المُعترِض وحدَه. والدالّتان
  // **مُتحايدتان**: `fixSql` محروسةٌ بـ`contains('?')` ولا تلمس شيئاً بعد
  // الترجمة، و`fixArgs` لا تمسّ إلّا `DateTime`. فمرورُهما ثانيةً عبر
  // المُعترِض بلا أثرٍ ولا كلفةٍ تُذكر.
  //
  // ⚠️ وسابقةٌ مسجَّلةٌ في `pg_compat_sql.dart` نفسِه (2026-04-28): عطبٌ بنفس
  // رمز `42601` سببُه أنّ الترجمةَ لم تقع. فهذه هي الطبقةُ الصحيحة.

  @override
  Future<void> customStatement(String statement, [List<dynamic>? args]) {
    if (!_isPostgres) return super.customStatement(statement, args);
    return super.customStatement(
      PgCompatSql.fixSql(statement),
      args == null ? null : PgCompatSql.fixArgs(args),
    );
  }

  @override
  Selectable<QueryRow> customSelect(
    String query, {
    List<Variable> variables = const [],
    Set<ResultSetImplementation> readsFrom = const {},
  }) {
    // المتغيّراتُ تبقى كما هي — الترتيبُ الموضعيُّ نفسُه، و`fixSql` ترقّم
    // العلاماتِ من اليسار لليمين فتبقى المطابقةُ صحيحة.
    return super.customSelect(
      _isPostgres ? PgCompatSql.fixSql(query) : query,
      variables: variables,
      readsFrom: readsFrom,
    );
  }

  /// Lazy accessor for the Audit Dashboard DAO
  late final AuditDashboardDao auditDashboardDao = AuditDashboardDao(this);

  /// 062 (D1-004) — shared PermissionEnforcer for critical financial ops.
  /// Used by DAO part-files (sales_actions_dao, purchase_dao, …) to gate
  /// the admin bypass on voidPaidInvoice / modifyLockedInvoice /
  /// overrideCreditLimit. See specs/062-wire-critical-financial-ops.
  late final PermissionEnforcer permissionEnforcer =
      PermissionEnforcer(userHasPermission);

  /// Returns the SQL literal for a boolean value that is compatible with the
  /// current database backend. PostgreSQL uses TRUE/FALSE, SQLite uses 1/0.
  String sqlBool(bool value) => _isPostgres
      ? (value ? 'TRUE' : 'FALSE')
      : (value ? '1' : '0');

  /// Returns a [Variable] for DateTime that works in raw SQL (customSelect).
  ///
  /// Drift stores DateTime columns as epoch seconds (BIGINT) in both SQLite
  /// and our PostgreSQL schema. On SQLite, `Variable(DateTime)` auto-converts
  /// to integer. On PostgreSQL, `drift_postgres` sends DateTime as a native
  /// timestamp type which causes type mismatch with BIGINT columns.
  ///
  /// This helper always returns `Variable<int>` with epoch seconds, ensuring
  /// `BETWEEN ? AND ?` and other comparisons work on both backends.
  Variable<int> dateVar(DateTime dt) =>
      Variable<int>(dt.millisecondsSinceEpoch ~/ 1000);

  /// Current schema version.
  ///
  /// Bump this whenever table definitions or migrations change.
  /// See [migration] for the full upgrade path.
  /// Schema v49: Phase 5.2-5.3 — Loyalty Points + Distribution
  /// Schema v142: Feature 004 (Multi-Branch Governance) — FixedAssets gains
  /// `global_id` (UUIDv7) + `linked_account_id` for atomic CoA sub-account linkage.
  ///
  /// Schema v143: Feature 005 (CoA Hardening) — re-aligns party sub-account
  /// parents from the phantom `'1201'`/`'2101'` codes (which were never in
  /// the seeder) to the seeded `'1121'`/`'2111'`. The migration attempts to
  /// move any orphan sub-accounts off `1201`/`2101` to the seeded counterparts
  /// then deletes the orphan parents — best-effort, no-op when those codes
  /// aren't present.
  ///
  /// Schema v144: Feature 005 Phase 8 — archives duplicate safe-linked
  /// accounts (orphan no-dash siblings of the canonical `111-XXXXX` rows)
  /// that some users created via the manual COA dialog. Soft-delete only,
  /// preserves rows that carry JE lines.
  ///
  /// Schema v145: Spec 008 / FR-001 — adds `branch_id` to `shifts` (nullable)
  /// so multi-branch users can record which branch each shift was opened on.
  ///
  /// Schema v146: Feature 009 (Auto-Deplete BOM on Sale) — adds
  /// `auto_deplete_on_sale` + `depletion_policy` columns on `bill_of_materials`,
  /// creates the `sale_bom_consumptions` append-only log, creates the
  /// `pos_terminals` master-data registry, and adds nullable
  /// `pos_terminal_id` on `shifts` for per-terminal policy resolution.
  ///
  /// Schema v150: Spec 151 (return-key fix) — RETURN journal entries are now
  /// keyed on the ORIGINATING invoice id, so multiple partial returns of one
  /// invoice share `(reference_type, reference_id)`. Drop + recreate
  /// `idx_je_autopost_dedup` with an exemption for the multi-JE reference types
  /// (returns + commercial papers + partial collections) so the second partial
  /// return no longer violates UNIQUE, and backfill historical hash-keyed
  /// return JEs onto their invoice id. Index-only change — no table/column
  /// change, so no generated schema regeneration is required.
  ///
  /// Schema v153: الأجرُ بالساعة والإضافي المحسوب (المهمة ٢) — جدولُ
  /// `work_holidays` (تقويمُ العطلات لكلّ فرع)، وعمودُ
  /// `employees.hours_per_day` (مقامُ أجر الساعة)، وعمودُ
  /// `overtime_records.is_manual_amount` (تعليمُ السجلّات القائمة كي لا
  /// يُعاد اشتقاقُها).
  ///
  /// Schema v155: ضريبةُ المبيعات على طلبات الطاولات — عمودا
  /// `table_orders.tax_enabled` (مرآةُ `CartState.taxEnabled`، افتراضُه
  /// `false`) و`table_orders.tax_rate` (لقطةُ `pos_default_tax_rate` كسريّةً
  /// لحظةَ فتح الطاولة، فلا يُعاد تسعيرُ حسابٍ عُرض على الضيف). بهما يصير
  /// المشحونُ على الفاتورة والمسجَّلُ على الطلب رقماً واحداً، فيسكت حارسُ
  /// `checkTableCharge` عن حقٍّ لا عن إضعاف.
  ///
  /// **١٥٦** — قيدُ `CHECK (NOT tax_enabled OR tax_rate > 0)` على
  /// `table_orders`: ما حرسته v155 عند مفتاح التفعيل صار مستحيلَ التمثيل في
  /// الجدول نفسِه. والترقيةُ تُعيد إنشاءَ الجدول (SQLite لا تضيف قيداً
  /// بـ`ALTER TABLE`) بعد تسويةِ أيِّ صفٍّ كاذبٍ قائم.
  ///
  /// **١٥٧** — شدُّ ذلك القيدِ إلى `tax_rate >= 0.01`: `> 0` كانت تقبل
  /// `0.0000001`، فالزرُّ «مفعَّل» والقيدُ راضٍ والمحصَّلُ صفرٌ بعد التقريب —
  /// الكذبةُ نفسُها بصورةٍ تمرّ من تحت قيدِ ١٥٦. والحدُّ الآن واحدٌ عند
  /// الأبواب الثلاثة: مدخلُ الإعدادات، و`setOrderTax`، وهذا القيد.
  @override
  // ⚠️ ‏160: ١٥٩ أخذته جداولُ محرِّك الحجز حين دخلت `main`، وفرعُ
  // `pos-flexible-permissions` كان قد أخذ ١٥٩ نفسَه لترقيةٍ أخرى — نقلِ فئة
  // `pos_shift_close` إلى الخزينة. فرُفعت تلك إلى **١٦٠** عند الدمج، ورُفع
  // حارسُها في [epoch_3] إلى `from < 160` معها. ولا تفصل بينهما: رقمٌ يُرفَع
  // وحارسٌ يبقى قديماً = ترقيةٌ لا تُطبَّق أبداً وتمرّ صامتة.
  // ⚠️ ‏162: ليست ميزةً بل إنقاذ. خطوةُ 161 كانت تنادي `alterTable` بلا
  // `newColumns`، فرمت `no such column: "role"` وابتلعها `_safeMigrate`
  // (تعدُّها خطأً عديمَ الأثر) — فخُتمت القواعدُ 161 وأعمدةُ المورد لم تُضَف،
  // و`from < 161` لا يعود يفحصها. الخطوةُ الجديدةُ تفحص ثمّ تُصلح.
  int get schemaVersion => 174;

  /// 🔴 جملةُ `CREATE INDEX` صالحةً لـPostgreSQL، مأخوذةً من الجملة التي
  /// ولّدتها drift لـSQLite.
  ///
  /// **العطب**: `Migrator.create(index)` يرمي على PG لأنّ الـcodegen لم يُولّد
  /// إلّا لهجةَ sqlite (‏`dialects` في `build.yaml`)، وdrift يؤكّد على وجود
  /// اللهجة قبل التنفيذ:
  ///   «Tried running SQL optimized for … SqlDialect.sqlite. However, the
  ///    database is running SqlDialect.postgres.»
  /// ومسارا المعالجة كلاهما كانا يعيدان نداءَ `Migrator.create` نفسِه، فيفشلان
  /// بعينِ السبب. مقيسٌ 2026-08-31 على قاعدةٍ حيّة: **١٤٨ من ١٤٨** فهرساً
  /// مُعلَناً بـ`@TableIndex` غائبةٌ عن كلّ قاعدةِ PostgreSQL — وهي خلفيّةُ
  /// الخادم في تنصيبة العميل/المرآة، أي أنّ كلّ استعلامٍ يعتمدها كان يمسح
  /// الجدولَ كاملاً.
  ///
  /// **والعلاجُ بلا codegen**: الجملُ المولَّدةُ محمولةٌ حرفيّاً — نصُّها
  /// `CREATE INDEX idx_accounts_code ON accounts (code)` وهو SQL قياسيٌّ تقبله
  /// PostgreSQL كما هو. فتُؤخَذ من [Index.createStatementsByDialect] وتُنفَّذ
  /// بـ`customStatement` بدل المرور بمُهاجر drift.
  ///
  /// ويُحقَن `IF NOT EXISTS` لأنّ drift لا تولّده، فيصير التنفيذُ آمناً على
  /// قاعدةٍ تحمل الفهرسَ أصلاً — وهذا شرطُ الشفاء كلَّ إقلاع.
  String pgPortableIndexSql(Index index) {
    final byDialect = index.createStatementsByDialect;
    final stmt = (byDialect[SqlDialect.postgres] ??
            byDialect[SqlDialect.sqlite] ??
            byDialect.values.first)
        .trim();
    if (RegExp(r'IF\s+NOT\s+EXISTS', caseSensitive: false).hasMatch(stmt)) {
      return stmt;
    }
    return stmt.replaceFirst(
      RegExp(r'INDEX\s+', caseSensitive: false),
      'INDEX IF NOT EXISTS ',
    );
  }

  /// PostgreSQL-specific table creation: Drift's `currentDateAndTime` generates
  /// `strftime('%s','now')` which doesn't exist in PostgreSQL.
  /// We try normal creation first, and for failures, we create the table using
  /// raw SQL with PostgreSQL-compatible defaults.
  Future<void> _createAllForPostgres(Migrator m) async {
    final failedEntities = <DatabaseSchemaEntity>[];

    // Phase 1: try creating each entity normally
    for (final entity in allSchemaEntities) {
      try {
        await m.create(entity);
      } catch (e) {
        failedEntities.add(entity);
        debugPrint('[PG] Failed to create ${entity.entityName}, will retry with fixed SQL');
      }
    }

    // Phase 2: for failed tables, create using raw PostgreSQL-compatible SQL
    for (final entity in failedEntities) {
      if (entity is TableInfo) {
        try {
          final columns = entity.$columns;
          final colDefs = <String>[];

          for (final col in columns) {
            final colName = col.$name;
            String pgType;

            // Map Drift types to PostgreSQL types
            if (col.type == DriftSqlType.int) {
              if (col.hasAutoIncrement) {
                pgType = 'SERIAL PRIMARY KEY';
                colDefs.add('"$colName" $pgType');
                continue;
              }
              pgType = 'INTEGER';
            } else if (col.type == DriftSqlType.string) {
              pgType = 'TEXT';
            } else if (col.type == DriftSqlType.bool) {
              pgType = 'BOOLEAN';
            } else if (col.type == DriftSqlType.double) {
              pgType = 'DOUBLE PRECISION';
            } else if (col.type == DriftSqlType.dateTime) {
              pgType = 'BIGINT';  // Drift stores datetime as unix epoch
            } else if (col.type == DriftSqlType.blob) {
              pgType = 'BYTEA';
            } else {
              pgType = 'TEXT';
            }

            final nullable = col.$nullable ? '' : ' NOT NULL';
            String defaultClause = '';

            // Handle defaults: replace strftime with PostgreSQL equivalent
            if (col.defaultValue != null) {
              final defaultStr = col.defaultValue.toString();
              if (defaultStr.contains('currentDateAndTime') || defaultStr.contains('CurrentDateTimeExpression')) {
                defaultClause = " DEFAULT (EXTRACT(EPOCH FROM NOW())::bigint)";
              } else if (col.defaultValue is Constant) {
                final val = (col.defaultValue as Constant).value;
                if (val is bool) {
                  defaultClause = ' DEFAULT ${val ? 'TRUE' : 'FALSE'}';
                } else if (val is String) {
                  defaultClause = " DEFAULT '${val.replaceAll("'", "''")}'";
                } else {
                  defaultClause = ' DEFAULT $val';
                }
              }
            }

            colDefs.add('"$colName" $pgType$nullable$defaultClause');
          }

          final sql = 'CREATE TABLE IF NOT EXISTS "${entity.entityName}" (${colDefs.join(', ')})';
          await customStatement(sql);
          debugPrint('[PG] Created ${entity.entityName} with fixed SQL');
        } catch (e2) {
          debugPrint('[PG] Failed to create ${entity.entityName} even with fixed SQL: $e2');
        }
      } else if (entity is Index) {
        // إعادةُ نداء `m.create` كانت تفشل بعينِ السبب (لهجةُ sqlite وحدَها)،
        // فالفهرسُ يُنشأ من جملته المحمولة — انظر [pgPortableIndexSql].
        try {
          await customStatement(pgPortableIndexSql(entity));
          debugPrint('[PG] Created index ${entity.entityName} (portable SQL)');
        } catch (e2) {
          debugPrint('[PG] Failed to create index ${entity.entityName}: $e2');
        }
      } else {
        // For other entities, try again (they might depend on now-created tables)
        try {
          await m.create(entity);
          debugPrint('[PG] Created entity ${entity.entityName} on retry');
        } catch (e2) {
          debugPrint('[PG] Skipped non-table entity ${entity.entityName}: $e2');
        }
      }
    }
  }

  /// PostgreSQL-specific seeder. Delegates to the atomic, idempotent,
  /// verifiable implementation in `database_seeder_postgres.dart`.
  ///
  /// Kept as a thin wrapper for backward compatibility with
  /// `database_startup.dart` callers. New code should call
  /// `seedInitialDataPostgresAtomic()` directly to get the `SeedResult`.
  Future<void> _seedInitialDataPostgres() async {
    await seedInitialDataPostgresAtomic();
  }

  /// Create PostgreSQL compatibility layer for SQLite-specific SQL that
  /// Drift generates. Covers: strftime(), boolean=integer comparisons.
  ///
  /// CRITICAL: this function runs on EVERY app start via `onCreate` on a
  /// fresh install AND explicitly from `runBeforeOpen` on re-launches.
  /// The previous implementation tried to `DROP ... IF EXISTS` the
  /// operators/casts before re-creating them. On a re-run, every table
  /// that carries a `CHECK (col IN (0, 1))` constraint on a BOOLEAN
  /// column depends on the `=(boolean, integer)` operator — so the
  /// DROP was refused by PostgreSQL with
  ///     "constraint users_force_password_change_check on table users
  ///      depends on operator =(boolean,integer)"
  /// and the follow-up CREATE OPERATOR failed (operator already exists).
  /// That cascade is exactly what left fresh server installs with an
  /// empty `roles` + `users` table and unsolvable login errors.
  ///
  /// New behaviour: functions are idempotent via `CREATE OR REPLACE`;
  /// operators and casts are guarded by catalog lookups so we do NOT
  /// drop them when they already exist (tables legitimately depend on
  /// them). We only `CREATE` on first run, otherwise we no-op silently.
  Future<void> _createPostgresCompatLayer() async {
    // 1. strftime() compatibility — Drift uses strftime('%s', 'now')
    try {
      await customStatement(r'''
        CREATE OR REPLACE FUNCTION strftime(fmt text, ts text)
        RETURNS bigint AS $fn$
          SELECT EXTRACT(EPOCH FROM NOW())::bigint;
        $fn$ LANGUAGE sql STABLE
      ''');
    } catch (e) { debugPrint('[PG-COMPAT] strftime(text,text): $e'); }

    try {
      await customStatement(r'''
        CREATE OR REPLACE FUNCTION strftime(fmt text, ts timestamptz)
        RETURNS bigint AS $fn$
          SELECT EXTRACT(EPOCH FROM ts)::bigint;
        $fn$ LANGUAGE sql STABLE
      ''');
    } catch (e) { debugPrint('[PG-COMPAT] strftime(text,timestamptz): $e'); }

    // 2. boolean = integer helper function (CREATE OR REPLACE is safe).
    try {
      await customStatement(r'''
        CREATE OR REPLACE FUNCTION bool_eq_int(boolean, integer)
        RETURNS boolean AS $fn$
          SELECT $1 = ($2 != 0);
        $fn$ LANGUAGE sql IMMUTABLE
      ''');
    } catch (e) { debugPrint('[PG-COMPAT] bool_eq_int func: $e'); }

    try {
      await customStatement(r'''
        CREATE OR REPLACE FUNCTION int_eq_bool(integer, boolean)
        RETURNS boolean AS $fn$
          SELECT ($1 != 0) = $2;
        $fn$ LANGUAGE sql IMMUTABLE
      ''');
    } catch (e) { debugPrint('[PG-COMPAT] int_eq_bool func: $e'); }

    try {
      await customStatement(r'''
        CREATE OR REPLACE FUNCTION int_to_bool(integer)
        RETURNS boolean AS $fn$
          SELECT $1 != 0;
        $fn$ LANGUAGE sql IMMUTABLE
      ''');
    } catch (e) { debugPrint('[PG-COMPAT] int_to_bool func: $e'); }

    // 3. Operators and cast — guarded by catalog lookup. CREATE ONLY IF
    //    MISSING. Never drop — table CHECK constraints depend on these.
    await _pgCreateIfMissing(
      checkSql:
          "SELECT 1 FROM pg_operator WHERE oprname = '=' "
          "AND oprleft = 'boolean'::regtype AND oprright = 'integer'::regtype",
      createSql: r'''
        CREATE OPERATOR public.= (
          LEFTARG = boolean, RIGHTARG = integer,
          FUNCTION = bool_eq_int
        )
      ''',
      label: 'OPERATOR =(boolean,integer)',
    );

    await _pgCreateIfMissing(
      checkSql:
          "SELECT 1 FROM pg_operator WHERE oprname = '=' "
          "AND oprleft = 'integer'::regtype AND oprright = 'boolean'::regtype",
      createSql: r'''
        CREATE OPERATOR public.= (
          LEFTARG = integer, RIGHTARG = boolean,
          FUNCTION = int_eq_bool
        )
      ''',
      label: 'OPERATOR =(integer,boolean)',
    );

    await _pgCreateIfMissing(
      checkSql:
          "SELECT 1 FROM pg_cast "
          "WHERE castsource = 'integer'::regtype "
          "AND casttarget = 'boolean'::regtype",
      createSql: r'''
        CREATE CAST (integer AS boolean)
        WITH FUNCTION int_to_bool(integer)
        AS IMPLICIT
      ''',
      label: 'CAST (integer AS boolean)',
    );

    debugPrint('[PG] ✅ Compatibility layer ready (idempotent, re-run safe)');
  }

  /// Runs [createSql] only if [checkSql] returns zero rows. Used for DDL
  /// objects (operators, casts) that have no `CREATE OR REPLACE` form
  /// AND cannot be dropped because live tables depend on them.
  Future<void> _pgCreateIfMissing({
    required String checkSql,
    required String createSql,
    required String label,
  }) async {
    try {
      final rows = await customSelect(checkSql).get();
      if (rows.isNotEmpty) {
        debugPrint('[PG-COMPAT] $label already exists — skipping');
        return;
      }
      await customStatement(createSql);
      debugPrint('[PG-COMPAT] $label created');
    } catch (e) {
      debugPrint('[PG-COMPAT] $label check/create failed: $e');
    }
  }

  /// Canonical list of sync-hardening tables (mirrors the list in
  /// `migrations/epoch_3.dart` v129). Used by the Postgres infrastructure
  /// ensurer to backfill columns and attach auto-bump triggers.
  ///
  /// 🔴 **v173 (2026-09-02) — القائمةُ كانت متأخّرةً ٣٢ جدولاً عن `pullTables`.**
  ///
  /// المرحلتان ٢ و٣ (v166 · v167) و`purchase_returns` (v172) أضافت
  /// أعمدةَ المزامنة إلى كيانات drift وأدرجت الجداولَ في مساري السحب —
  /// **ولم تُضِفها هنا**. وهذه القائمةُ هي ما يعلّق عليه PostgreSQL مُشغِّلَ
  /// `fn_bump_row_version`، وهو **الوحيدُ** الذي يختم `last_modified_at`
  /// عند الإدراج. فعلى خادم PostgreSQL كان كلُّ صفٍّ جديدٍ في تلك الجداول
  /// يُولَد بـ`last_modified_at = NULL`، ومسارُ السحب يرشّح بـ
  /// `last_modified_at IS NOT NULL AND > since` — أي أنّ **أوّلَ سحبٍ وحدَه**
  /// يراها، وما يُدرَج بعده لا يصل أيَّ عميلٍ أبداً. ولا يظهر ذلك في اختبارِ
  /// وحدةٍ: SQLite لا مُشغِّلَ إدراجٍ فيه أصلاً والفحوصُ تقيس الأعمدةَ لا الختم.
  ///
  /// فالعقدُ الآن: **كلُّ جدولٍ في `DeltaPullService.pullTables` هنا** —
  /// و`pg_sync_hardened_tables_guard_test` يثبّته. و`printers` تبقى (خارجَ
  /// السحب بقرار مالك، والمُشغِّلُ عليها بلا ضرر).
  static const _syncHardenedTables = <String>[
    'party_groups', 'parties', 'purchase_invoices', 'purchase_invoice_items',
    'sales_invoices', 'sales_invoice_items', 'held_orders', 'held_order_items',
    'purchase_orders', 'purchase_order_items', 'sales_orders', 'sales_order_items',
    'payments', 'payment_allocations',
    'accounts', 'journal_entries', 'cost_centers', 'fiscal_years', 'accounting_periods',
    'roles', 'users',
    'commercial_papers', 'currencies', 'price_lists', 'price_list_items',
    'regions', 'branches', 'warehouses', 'stock_movements',
    'units', 'categories', 'products', 'product_barcodes', 'product_units',
    'quotations', 'quotation_items',
    'safes', 'safe_transactions', 'printers',
    'shifts',

    // v166 / المرحلة ٢ — مستنداتُ الأثر المحاسبيّ (كانت غائبةً هنا).
    'asset_categories', 'op_expense_categories', 'bill_of_materials',
    'fixed_assets', 'manufacturing_orders', 'bom_components',
    'op_expenses', 'asset_depreciations', 'mfg_order_costs',
    'landed_cost_sheets', 'landed_cost_items', 'landed_cost_allocations',
    // §٦‑٢ (v172)
    'purchase_returns',
    // v167 / المرحلة ٣ — الفئةُ التشغيليّة (كانت غائبةً هنا).
    'employees',
    'table_sections', 'restaurant_tables', 'table_orders',
    'table_order_items', 'table_reservations', 'table_order_payments',
    'kitchen_stations', 'category_station_mappings',
    'work_orders', 'work_order_items',
    'booking_resources', 'booking_services', 'bookings', 'booking_reminders',
    'sales_routes', 'route_visits', 'sales_rep_targets',
    'sales_rep_collections',

    // v173 / المرحلة ٤ — السجلُّ الرقابيُّ والتشغيلُ العابرُ للأجهزة.
    'loyalty_programs', 'delivery_companies', 'couriers',
    'customer_loyalty_points', 'loyalty_transactions',
    'warehouse_prices',
    'cycle_count_plans', 'cycle_count_tasks', 'cycle_count_items',
    'stock_audits', 'stock_audit_items',
    'stock_requisitions', 'stock_requisition_items',
    'bank_reconciliations', 'bank_statement_lines',
    'e_invoice_submissions', 'e_invoice_status_log',
    'field_audit_logs', 'failed_autoposts',
    'approval_workflows', 'approval_steps', 'approval_requests',
    'approval_decisions', 'sod_conflicts', 'sod_violations',
    'compliance_checks',
  ];

  /// مكشوفةٌ لحارسٍ يثبّت أنّ كلَّ جدولٍ يُسحَب يحمل مُشغِّلَ الختم على
  /// PostgreSQL — انظر تعليقَ [_syncHardenedTables].
  @visibleForTesting
  static List<String> get syncHardenedTablesForTest => _syncHardenedTables;

  /// Ensures PostgreSQL has the full sync-hardening infrastructure.
  ///
  /// The SQLite migration path (epoch_3.dart v129/v130) uses SQLite-only DDL
  /// (`strftime`, `CREATE TRIGGER ... WHEN ... BEGIN ... END`, `AUTOINCREMENT`)
  /// which is incompatible with Postgres. The Drift `onUpgrade` hook is
  /// skipped entirely on PG (see [migration]), so those v129/v130 changes
  /// never land on server-mode installs. This method installs the Postgres
  /// equivalents directly, and runs idempotently on every startup so both
  /// fresh installs (where `_createAllForPostgres` already created the base
  /// tables) and older PG databases (pre-v129) converge to the same state.
  ///
  /// Steps:
  ///   1. `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` for the 4 sync columns
  ///      (`last_modified_at`, `deleted_at`, `origin_client_id`, `row_version`)
  ///      on every table in [_syncHardenedTables].
  ///   2. `CREATE TABLE IF NOT EXISTS remote_id_mappings` with Postgres DDL
  ///      (`SERIAL` instead of `AUTOINCREMENT`, `BIGINT` with
  ///      `EXTRACT(EPOCH FROM NOW())::bigint` default instead of `strftime`).
  ///   3. `CREATE OR REPLACE FUNCTION fn_bump_row_version()` in PL/pgSQL —
  ///      the Postgres equivalent of the SQLite auto-bump trigger body.
  ///      Runs as a BEFORE UPDATE trigger and mutates NEW directly (cheaper
  ///      than the SQLite approach of firing a follow-up UPDATE).
  ///   4. DROP + CREATE TRIGGER for each sync table (Postgres `CREATE OR
  ///      REPLACE TRIGGER` requires v14+; DROP IF EXISTS + CREATE is portable
  ///      back to v10).
  Future<void> _ensurePostgresSyncInfrastructure() async {
    if (!_isPostgres) return;

    // ── Step 1: backfill sync columns (Postgres 9.6+ supports IF NOT EXISTS).
    for (final t in _syncHardenedTables) {
      for (final ddl in [
        // v173 — دفاعيٌّ للقواعد التي سبقت إعلانَ كيانٍ ما (الكيانُ يحمله
        // على القواعد الجديدة، و`IF NOT EXISTS` يجعله عديمَ الأثر هناك).
        'ALTER TABLE $t ADD COLUMN IF NOT EXISTS global_id TEXT',
        'ALTER TABLE $t ADD COLUMN IF NOT EXISTS last_modified_at BIGINT',
        'ALTER TABLE $t ADD COLUMN IF NOT EXISTS deleted_at BIGINT',
        'ALTER TABLE $t ADD COLUMN IF NOT EXISTS origin_client_id TEXT',
        'ALTER TABLE $t ADD COLUMN IF NOT EXISTS row_version INTEGER NOT NULL DEFAULT 0',
      ]) {
        try {
          await customStatement(ddl);
        } catch (e) {
          // Table might not exist yet on a partially-provisioned DB; log and
          // continue so one missing table doesn't block the rest.
          debugPrint('[PG-SYNC] $t: $ddl failed: $e');
        }
      }
    }

    // ── Step 1b (v133): direct branch_id on invoice tables for multi-branch
    // reports + filters. PG-side ALTER + backfill from warehouses.branch_id
    // for any rows created before this schema bump.
    for (final t in const ['sales_invoices', 'purchase_invoices']) {
      try {
        await customStatement('ALTER TABLE $t ADD COLUMN IF NOT EXISTS branch_id INTEGER REFERENCES branches(id)');
        await customStatement(
          'UPDATE $t SET branch_id = '
          '(SELECT branch_id FROM warehouses WHERE warehouses.id = $t.warehouse_id) '
          'WHERE branch_id IS NULL',
        );
        await customStatement('CREATE INDEX IF NOT EXISTS idx_${t}_branch ON $t(branch_id)');
      } catch (e) {
        debugPrint('[PG-SYNC] $t.branch_id: $e');
      }
    }

    // ── Step 1c (v134): branch code for invoice number prefixing.
    // PG-side ALTER + backfill from name (first 3 chars uppercased).
    try {
      await customStatement('ALTER TABLE branches ADD COLUMN IF NOT EXISTS code TEXT');
      await customStatement(
        "UPDATE branches SET code = UPPER(SUBSTRING(REPLACE(name,' ',''), 1, 3)) "
        "WHERE code IS NULL OR code = ''",
      );
    } catch (e) {
      debugPrint('[PG-SYNC] branches.code: $e');
    }

    // ── Step 1d (v142, Feature 004 US1): per-asset CoA sub-account linkage
    // + UUIDv7 sync identity on fixed_assets. Idempotent on PG.
    try {
      await customStatement(
          'ALTER TABLE fixed_assets ADD COLUMN IF NOT EXISTS linked_account_id INTEGER REFERENCES accounts(id)');
      await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_fixed_assets_linked_account ON fixed_assets(linked_account_id)');
      await customStatement(
          'ALTER TABLE fixed_assets ADD COLUMN IF NOT EXISTS global_id TEXT');
      await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_fixed_assets_global_id '
          'ON fixed_assets(global_id) WHERE global_id IS NOT NULL');
    } catch (e) {
      debugPrint('[PG-SYNC] fixed_assets v142 columns: $e');
    }

    // ── Step 2: ensure remote_id_mappings (idempotent; Drift schema already
    //    creates it on fresh installs via _createAllForPostgres, but older PG
    //    databases from before v130 won't have it).
    try {
      await customStatement('''
        CREATE TABLE IF NOT EXISTS remote_id_mappings (
          id SERIAL PRIMARY KEY,
          table_name TEXT NOT NULL,
          local_id INTEGER NOT NULL,
          remote_id INTEGER NOT NULL,
          global_id TEXT,
          created_at BIGINT NOT NULL DEFAULT EXTRACT(EPOCH FROM NOW())::bigint
        )
      ''');
      await customStatement(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_remote_id_local '
        'ON remote_id_mappings(table_name, local_id)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_remote_id_remote '
        'ON remote_id_mappings(table_name, remote_id)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_remote_id_global '
        'ON remote_id_mappings(table_name, global_id)',
      );
    } catch (e) {
      debugPrint('[PG-SYNC] remote_id_mappings: $e');
    }

    // ── Step 2b (B-MIG-3): e_invoice_status_log has a Drift class but is NOT
    //    registered in @DriftDatabase, so _createAllForPostgres (which iterates
    //    allSchemaEntities) never creates it, and PG skips the SQLite onUpgrade
    //    that would. On a fresh PG install e_invoicing_dao's status-log
    //    INSERT/SELECT then failed with 42P01. Create it here idempotently.
    //    (The other raw-SQL-only tables the audit listed — sync_logs,
    //    warehouse_transfers/_items, pricing_rules — have zero call sites and
    //    are dead/id-only stubs, so they are intentionally NOT provisioned.)
    try {
      await customStatement('''
        CREATE TABLE IF NOT EXISTS e_invoice_status_log (
          id SERIAL PRIMARY KEY,
          submission_id INTEGER NOT NULL REFERENCES e_invoice_submissions(id),
          old_status TEXT,
          new_status TEXT NOT NULL,
          changed_by TEXT,
          notes TEXT,
          changed_at BIGINT NOT NULL DEFAULT EXTRACT(EPOCH FROM NOW())::bigint,
          global_id TEXT UNIQUE,
          last_modified_at BIGINT,
          deleted_at BIGINT,
          origin_client_id TEXT,
          row_version INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_einv_status_log_submission '
        'ON e_invoice_status_log(submission_id)',
      );
    } catch (e) {
      debugPrint('[PG-SYNC] e_invoice_status_log: $e');
    }

    // ── Step 3: auto-bump trigger function. Handles BOTH INSERT and UPDATE:
    //    * INSERT → stamps last_modified_at with server time so delta pull
    //      queries `WHERE last_modified_at > since` can find new rows. Server
    //      time is always authoritative here (avoids client clock skew).
    //    * UPDATE → if the application didn't advance row_version, bump it
    //      and refresh last_modified_at. The guard respects explicit client
    //      writes (e.g. a sync pull replaying a specific version).
    try {
      await customStatement(r'''
        CREATE OR REPLACE FUNCTION fn_bump_row_version()
        RETURNS trigger AS $fn$
        BEGIN
          IF TG_OP = 'INSERT' THEN
            NEW.last_modified_at := EXTRACT(EPOCH FROM NOW())::bigint;
            IF NEW.row_version IS NULL THEN
              NEW.row_version := 0;
            END IF;
          ELSIF TG_OP = 'UPDATE' THEN
            IF NEW.row_version IS NULL OR OLD.row_version IS NULL
               OR NEW.row_version = OLD.row_version THEN
              NEW.row_version := COALESCE(OLD.row_version, 0) + 1;
              NEW.last_modified_at := EXTRACT(EPOCH FROM NOW())::bigint;
            END IF;
          END IF;
          RETURN NEW;
        END;
        $fn$ LANGUAGE plpgsql
      ''');
    } catch (e) {
      debugPrint('[PG-SYNC] fn_bump_row_version: $e');
    }

    // ── Step 4: attach/refresh trigger on each sync table. Skip the whole
    //    loop when the expected trigger count is already installed — this
    //    keeps the common-case startup near zero-cost.
    var shouldInstallTriggers = true;
    try {
      final existing = await customSelect(
        "SELECT COUNT(*)::integer AS c FROM pg_trigger "
        "WHERE tgname LIKE '%_bump_version' AND NOT tgisinternal",
      ).get();
      final count = (existing.first.data['c'] as num).toInt();
      if (count >= _syncHardenedTables.length) {
        shouldInstallTriggers = false;
        debugPrint(
          '[PG-SYNC] triggers already installed ($count ≥ '
          '${_syncHardenedTables.length}) — skipping install',
        );
      }
    } catch (e) {
      debugPrint('[PG-SYNC] trigger count check failed, will reinstall: $e');
    }

    if (shouldInstallTriggers) {
      for (final t in _syncHardenedTables) {
        try {
          await customStatement(
            'DROP TRIGGER IF EXISTS ${t}_bump_version ON $t',
          );
          await customStatement('''
            CREATE TRIGGER ${t}_bump_version
            BEFORE INSERT OR UPDATE ON $t
            FOR EACH ROW
            EXECUTE FUNCTION fn_bump_row_version()
          ''');
        } catch (e) {
          debugPrint('[PG-SYNC] trigger $t: $e');
        }
      }
    }

    // ── Step 4.5: Modifier tables. Migration v70 creates these via raw
    //    SQLite DDL (AUTOINCREMENT, INTEGER booleans), and Drift's
    //    onUpgrade is skipped on PG, so a Postgres server installed
    //    before v70 — or any PG server, since these tables have no
    //    Drift Table class — never gets the schema. The DAO query
    //      SELECT mg.* FROM modifier_groups ...
    //    then fails with "relation modifier_groups does not exist"
    //    every time a cashier opens the modifier panel for a product.
    //    Idempotent CREATE IF NOT EXISTS keeps this safe across restarts.
    //
    // 🔴 ٦‑٢: هذه الكتلةُ كانت تحمل **نسخةً ثانيةً** من تعريف
    //    `modifier_groups` تخالف ما يكتبه [ensureModifierTables]:
    //      هنا:      (id, name, min_selection, max_selection, is_active)
    //      الصحيح:   (id, name, type, min_select, max_select, is_required,
    //                 is_active, sort_order)
    //    و`CREATE TABLE IF NOT EXISTS` تجعل الأسبقَ يفوز، والأسبقُ على PG هو
    //    الإقلاعُ لا الشاشة — فـ`ensureTables()` التي تناديها شاشةُ الإعدادات
    //    تصير بلا أثر، و`createModifierGroup` (تكتب الخمسةَ الناقصة) تنهار على
    //    **كلِّ** قاعدةِ PostgreSQL. أي الميزةُ معطَّلةٌ بالكامل لا «تقرأ خطأً».
    //
    //    فالتعريفُ صار مصدراً واحداً: تُستدعى [ensureModifierTables] نفسُها،
    //    وهي تُفرّع على الخلفيّة داخليّاً وتحمل شفاءَ الأعمدة الناقصة لخادمٍ
    //    نُصِّب على الشكل القديم. والفهرسان يبقيان هنا لأنّها لا تُنشئهما.
    try {
      await ensureModifierTables();
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_modifier_items_group ON modifier_items(group_id)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_product_modifier_groups_product ON product_modifier_groups(product_id)',
      );
    } catch (e) {
      debugPrint('[PG-SYNC] modifier tables ensure failed: $e');
    }

    // ── Step 5: activity_logs sync columns. activity_logs is NOT in
    //    _syncHardenedTables (it has no deleted_at / row_version because the
    //    audit trail is append-only and never modified once written), but it
    //    DOES need global_id + last_modified_at + origin_client_id so that
    //    multi-client activity logs can be pushed and pulled by globalId.
    //
    //    Without this block, ActivityLogger.log() throws on every call:
    //      Severity.error 42703: column "global_id" of relation
    //      "activity_logs" does not exist
    //    on Postgres servers that were created before the schema added these
    //    columns (Drift's onUpgrade is skipped on PG).
    try {
      for (final ddl in [
        'ALTER TABLE activity_logs ADD COLUMN IF NOT EXISTS global_id TEXT',
        'ALTER TABLE activity_logs ADD COLUMN IF NOT EXISTS origin_client_id TEXT',
        'ALTER TABLE activity_logs ADD COLUMN IF NOT EXISTS last_modified_at BIGINT',
        // Unique constraint on global_id matches the SQLite schema
        // (auth_tables.dart: globalId.unique()). IF NOT EXISTS keeps this
        // idempotent across restarts.
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_activity_logs_global_id '
            'ON activity_logs(global_id) WHERE global_id IS NOT NULL',
        'CREATE INDEX IF NOT EXISTS idx_activity_logs_modified '
            'ON activity_logs(last_modified_at)',
        // ── نظيرُ PG لأعمدة «Maker-Checker» الثلاثة ──
        //
        // ⚠️ نفسُ علّة `activity_logs` أعلاه بالضبط: v82 أضافها بـ`ALTER
        //    TABLE` في هجرة SQLite، و`onUpgrade` **متجاوَزٌ على PG**،
        //    و`_createAllForPostgres` يبني من كيانات drift وهي غيرُ مُعلَنةٍ
        //    في صنف الجدول. فخادمُ PostgreSQL بلا هذه الأعمدة، و
        //    `approveJournalEntry` ينهار عليه بـ42703.
        'ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS status TEXT '
            "NOT NULL DEFAULT 'posted'",
        'ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS approved_by INTEGER',
        'ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS approved_at BIGINT',
        'ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS created_by INTEGER',
        // ── §٦‑٣: نظيرُ PG لأعمدة تدقيقِ إعادة فتح الفترة ──
        //
        // نفسُ العلّة حرفاً: v82 أضافها بـALTER في هجرة SQLite، وهي غيرُ
        // مُعلَنةٍ في صنف `AccountingPeriods`، و`onUpgrade` متجاوَزٌ على PG.
        // فبلا هذه الأسطر ينهار `reopenAccountingPeriodWithAudit` على الخادم
        // بـ42703 متى وُصِل.
        'ALTER TABLE accounting_periods ADD COLUMN IF NOT EXISTS reopen_reason TEXT',
        'ALTER TABLE accounting_periods ADD COLUMN IF NOT EXISTS reopened_by INTEGER',
        'ALTER TABLE accounting_periods ADD COLUMN IF NOT EXISTS reopened_at BIGINT',
      ]) {
        try {
          await customStatement(ddl);
        } catch (e) {
          debugPrint('[PG-SYNC] activity_logs DDL failed: $e');
        }
      }
    } catch (e) {
      debugPrint('[PG-SYNC] activity_logs ensure failed: $e');
    }

    debugPrint('[PG-SYNC] ✅ Postgres sync infrastructure ensured');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SPEC 130 — PG SCHEMA PARITY (generic self-heal pass)
  // ═══════════════════════════════════════════════════════════════════════════
  //
  // Defense-in-depth catch-all that ensures every Drift schema entity exists
  // on PostgreSQL. Runs every boot in Phase 2d (after
  // `_ensurePostgresSyncInfrastructure`). Compares `allSchemaEntities` against
  // `information_schema` + `pg_indexes` and emits idempotent DDL to close
  // gaps:
  //   - Missing tables → CREATE TABLE IF NOT EXISTS (via Migrator)
  //   - Missing columns → ALTER TABLE ADD COLUMN IF NOT EXISTS
  //   - Missing indexes → CREATE INDEX IF NOT EXISTS
  //   - Missing FK constraints → ALTER TABLE ADD CONSTRAINT (guarded)
  //
  // Per Clarification Q1: full parity (tables + columns + indexes + FKs).
  // Per Clarification Q2: unrecoverable failure throws
  // [PgSchemaParityException] → Fatal screen (Block-all).
  // Per Clarification Q3: defense-in-depth — does NOT replace
  // `_createAllForPostgres()` or `_ensurePostgresSyncInfrastructure()`,
  // runs AFTER them as catch-all.
  // Per Clarification Q4: column type drift = warn-only, no ALTER COLUMN TYPE.
  //
  // **FR-008**: runs outside any transaction. Uses `customStatement` directly,
  // NEVER `db.transaction(...)`. Static test (T025) grep-asserts this.
  // ═══════════════════════════════════════════════════════════════════════════

  /// Information schema snapshot for one PG table column.
  /// Private helper structure for the parity pass.
  static const Map<DriftSqlType, List<String>> _driftTypeToPgAcceptable = {
    DriftSqlType.int: ['integer', 'bigint', 'smallint'],
    DriftSqlType.bigInt: ['bigint', 'integer'],
    DriftSqlType.string: ['text', 'character varying', 'character'],
    DriftSqlType.bool: ['boolean'],
    DriftSqlType.double: ['double precision', 'real', 'numeric'],
    DriftSqlType.dateTime: ['bigint'], // Drift stores epoch
    DriftSqlType.blob: ['bytea'],
    // `any` is Drift's wildcard for custom types — accept any actual PG
    // type to avoid false-positive drift warnings on columns the schema
    // intentionally leaves loose.
    DriftSqlType.any: [],
  };

  /// Read PG live table names from information_schema (public schema only).
  /// Returns lowercased set for case-insensitive comparison.
  Future<Set<String>> _pgFetchTableNames() async {
    final rows = await customSelect(
      "SELECT table_name FROM information_schema.tables "
      "WHERE table_schema = 'public' AND table_type = 'BASE TABLE'",
    ).get();
    return rows
        .map((r) => (r.data['table_name'] as String).toLowerCase())
        .toSet();
  }

  /// Read PG live columns keyed by `(table_name, column_name)` → (type, nullable).
  /// All names lowercased for case-insensitive comparison.
  Future<Map<String, _PgLiveColumn>> _pgFetchColumns() async {
    final rows = await customSelect(
      "SELECT table_name, column_name, data_type, is_nullable "
      "FROM information_schema.columns WHERE table_schema = 'public'",
    ).get();
    final out = <String, _PgLiveColumn>{};
    for (final r in rows) {
      final table = (r.data['table_name'] as String).toLowerCase();
      final col = (r.data['column_name'] as String).toLowerCase();
      out['$table.$col'] = _PgLiveColumn(
        pgType: (r.data['data_type'] as String).toLowerCase(),
        nullable: (r.data['is_nullable'] as String).toUpperCase() == 'YES',
      );
    }
    return out;
  }

  /// Read PG live FK constraint signatures `(table.column → refTable.refColumn)`.
  /// Used to detect missing FKs in Drift schema.
  Future<Set<String>> _pgFetchForeignKeys() async {
    final rows = await customSelect(
      "SELECT tc.table_name AS src_table, kcu.column_name AS src_col, "
      "       ccu.table_name AS ref_table, ccu.column_name AS ref_col "
      "FROM information_schema.table_constraints tc "
      "JOIN information_schema.key_column_usage kcu "
      "  ON tc.constraint_name = kcu.constraint_name "
      "JOIN information_schema.constraint_column_usage ccu "
      "  ON tc.constraint_name = ccu.constraint_name "
      "WHERE tc.table_schema = 'public' "
      "  AND tc.constraint_type = 'FOREIGN KEY'",
    ).get();
    return rows
        .map((r) =>
            '${(r.data['src_table'] as String).toLowerCase()}.'
            '${(r.data['src_col'] as String).toLowerCase()}→'
            '${(r.data['ref_table'] as String).toLowerCase()}.'
            '${(r.data['ref_col'] as String).toLowerCase()}')
        .toSet();
  }

  /// Read PG live index names. Returns lowercased set.
  Future<Set<String>> _pgFetchIndexNames() async {
    final rows = await customSelect(
      "SELECT indexname FROM pg_indexes WHERE schemaname = 'public'",
    ).get();
    return rows
        .map((r) => (r.data['indexname'] as String).toLowerCase())
        .toSet();
  }

  /// Build a `CREATE TABLE IF NOT EXISTS` statement for the given Drift
  /// [TableInfo] using PostgreSQL-compatible DDL (SERIAL, BOOLEAN, BYTEA,
  /// `EXTRACT(EPOCH FROM NOW())` instead of `strftime`).
  ///
  /// Logic mirrors `_createAllForPostgres()` Phase 2 (lines 508-563) so
  /// the same dialect rules apply on both first-boot creation and
  /// every-boot self-heal. Duplicated rather than shared via helper to
  /// avoid touching the legacy creator (Constitution I — Behavior
  /// Preservation).
  String _buildPgCreateTableSql(TableInfo entity) {
    final columns = entity.$columns;
    final colDefs = <String>[];

    for (final col in columns) {
      final colName = col.$name;
      String pgType;

      if (col.type == DriftSqlType.int) {
        if (col.hasAutoIncrement) {
          colDefs.add('"$colName" SERIAL PRIMARY KEY');
          continue;
        }
        pgType = 'INTEGER';
      } else if (col.type == DriftSqlType.string) {
        pgType = 'TEXT';
      } else if (col.type == DriftSqlType.bool) {
        pgType = 'BOOLEAN';
      } else if (col.type == DriftSqlType.double) {
        pgType = 'DOUBLE PRECISION';
      } else if (col.type == DriftSqlType.dateTime) {
        pgType = 'BIGINT'; // Drift stores datetime as unix epoch
      } else if (col.type == DriftSqlType.blob) {
        pgType = 'BYTEA';
      } else {
        pgType = 'TEXT';
      }

      final nullable = col.$nullable ? '' : ' NOT NULL';
      var defaultClause = '';

      if (col.defaultValue != null) {
        final defaultStr = col.defaultValue.toString();
        if (defaultStr.contains('currentDateAndTime') ||
            defaultStr.contains('CurrentDateTimeExpression')) {
          defaultClause = " DEFAULT (EXTRACT(EPOCH FROM NOW())::bigint)";
        } else if (col.defaultValue is Constant) {
          final val = (col.defaultValue as Constant).value;
          if (val is bool) {
            defaultClause = ' DEFAULT ${val ? 'TRUE' : 'FALSE'}';
          } else if (val is String) {
            defaultClause = " DEFAULT '${val.replaceAll("'", "''")}'";
          } else {
            defaultClause = ' DEFAULT $val';
          }
        }
      }

      colDefs.add('"$colName" $pgType$nullable$defaultClause');
    }

    // Composite / non-autoincrement primary keys.
    //
    // The loop above only emits PRIMARY KEY for an autoincrement int column
    // (as part of SERIAL). Everything else declared via drift's
    // `Set<Column> get primaryKey` was DROPPED, so eight tables were created
    // on PostgreSQL with no primary key at all — among them
    // `document_sequences` (keyed on `prefix`, guarding document numbering)
    // and `processed_messages` (keyed on `idempotency_key`, the whole basis
    // of replay de-duplication).
    //
    // Scope note: this affects CREATE TABLE only. It is deliberately NOT
    // retro-fitted onto tables that already exist on a live server — adding a
    // primary key to a table that has accumulated duplicate rows fails, and a
    // failing statement in the boot path is exactly what killed the app in
    // v132. Existing deployments need a measured dedup + ALTER, tracked
    // separately.
    if (entity.$primaryKey.isNotEmpty) {
      final hasSerialPk = columns.any(
        (c) => c.type == DriftSqlType.int && c.hasAutoIncrement,
      );
      if (!hasSerialPk) {
        final pkCols =
            entity.$primaryKey.map((c) => '"${c.$name}"').join(', ');
        colDefs.add('PRIMARY KEY ($pkCols)');
      }
    }

    return 'CREATE TABLE IF NOT EXISTS "${entity.actualTableName}" '
        '(${colDefs.join(', ')})';
  }

  /// Generic schema parity pass. Iterates `allSchemaEntities`, reads PG
  /// live schema from `information_schema` + `pg_indexes`, and emits
  /// idempotent DDL to close gaps. See class-level comment for the full
  /// contract.
  ///
  /// **DO NOT** wrap the body in `db.transaction(...)` — FR-008 requires
  /// DDL to run outside any active transaction. Static test T025
  /// grep-asserts the absence of `transaction(` here.
  Future<void> _ensurePostgresSchemaParity() async {
    if (!_isPostgres) return;

    final sw = Stopwatch()..start();
    var healedCount = 0;
    var driftCount = 0;
    final fatalErrors = <_PgParityFatal>[];

    // Snapshot PG live schema once. O(1) round-trips instead of per-entity.
    final pgTables = await _pgFetchTableNames();
    final pgColumns = await _pgFetchColumns();
    final pgIndexes = await _pgFetchIndexNames();
    // `_pgFetchForeignKeys` exists for future FK-parity work (see T018
    // comment in the loop below) but is not snapshotted here yet — the
    // current implementation cannot programmatically derive Drift's
    // declared FK targets, so reading PG's side without a way to compare
    // would emit only spurious extras warnings.

    // Iterate Drift schema entities. Handle each kind explicitly so out-of-
    // scope kinds (Trigger/View) are logged via [PG-PARITY-SKIP] rather than
    // silently ignored (FR-006).
    final driftTableNames = <String>{};
    for (final entity in allSchemaEntities) {
      if (entity is TableInfo) {
        final tableName = entity.actualTableName.toLowerCase();
        driftTableNames.add(tableName);
        final tableExisted = pgTables.contains(tableName);

        if (!tableExisted) {
          // Missing table → emit CREATE TABLE IF NOT EXISTS with
          // PG-compatible DDL (Drift-generated DDL uses SQLite-only syntax
          // like strftime() / AUTOINCREMENT that PG rejects).
          try {
            final sql = _buildPgCreateTableSql(entity);
            await customStatement(sql);
            healedCount++;
            await DiagnosticLogger.log(
              'PG-PARITY-HEAL',
              'table=$tableName action=created',
            );
          } catch (e) {
            fatalErrors.add(_PgParityFatal(
              entity: 'table:$tableName',
              detail: 'CREATE TABLE failed: $e',
            ));
            await DiagnosticLogger.log(
              'PG-PARITY-FATAL',
              'table=$tableName error=$e',
            );
            continue; // skip column/FK heal on a table we couldn't create
          }
        }

        // T016 — column-level parity. ALTER ADD COLUMN IF NOT EXISTS for
        // any Drift column not present on PG. Reuses the Drift→PG type
        // mapping via [_buildPgColumnDef]. Skipped for tables we just
        // created above (they already carry all their columns) AND for
        // SERIAL-PK columns (cannot be re-added via ALTER).
        if (tableExisted) {
          for (final col in entity.$columns) {
            if (col.hasAutoIncrement) continue; // SERIAL PK — never ALTER ADD
            final colName = col.$name.toLowerCase();
            final key = '$tableName.$colName';
            final live = pgColumns[key];

            if (live == null) {
              // Missing column → ALTER TABLE ADD COLUMN IF NOT EXISTS.
              try {
                final colDef =
                    _buildPgColumnDef(col, forExistingTable: true);
                // Required-with-no-default arrives nullable instead of
                // aborting the boot. Surface it so ops can see which columns
                // still need promoting, rather than discovering it later from
                // a NULL that should have been impossible.
                final degraded =
                    !col.$nullable && _buildPgDefaultClause(col).isEmpty;
                await customStatement(
                  'ALTER TABLE "$tableName" '
                  'ADD COLUMN IF NOT EXISTS $colDef',
                );
                healedCount++;
                await DiagnosticLogger.log(
                  'PG-PARITY-HEAL',
                  'column=$tableName.$colName action=added'
                      '${degraded ? ' nullability=degraded_to_nullable '
                          'reason=not_null_without_default_on_existing_table '
                          'followup=needs_backfill_then_set_not_null' : ''}',
                );
              } catch (e) {
                fatalErrors.add(_PgParityFatal(
                  entity: 'column:$tableName.$colName',
                  detail: 'ALTER ADD COLUMN failed: $e',
                ));
                await DiagnosticLogger.log(
                  'PG-PARITY-FATAL',
                  'column=$tableName.$colName error=$e',
                );
              }
            } else {
              // T019 — drift detection. Column exists; verify type +
              // nullability. Warn-only per Clarification Q4 (no ALTER
              // COLUMN TYPE — too risky for data loss).
              final acceptable =
                  _driftTypeToPgAcceptable[col.type] ?? const ['text'];
              if (!acceptable.contains(live.pgType)) {
                driftCount++;
                await DiagnosticLogger.log(
                  'PG-PARITY-DRIFT',
                  'table=$tableName column=$colName '
                      'expected_type=${col.type} '
                      'actual_type=${live.pgType}',
                );
              } else if (live.nullable != col.$nullable) {
                driftCount++;
                await DiagnosticLogger.log(
                  'PG-PARITY-DRIFT',
                  'table=$tableName column=$colName '
                      'expected_null=${col.$nullable} '
                      'actual_null=${live.nullable}',
                );
              }
            }
          }
        }

        // T018 — FK constraint parity. Drift's runtime `GeneratedColumn`
        // does not expose the `.references(...)` target programmatically
        // (the metadata is baked into a private constraint-generation
        // closure that only fires inside Drift's own SQL emission path).
        //
        // The practical safety net for FK gaps is `_buildPgCreateTableSql`
        // — when a *missing table* is created, ON-INSERT runtime errors
        // surface FK violations loudly. For *existing tables* that lost a
        // constraint manually, an operator-level repair is required.
        //
        // Clarification Q1 listed FKs in the "full parity" scope, but
        // research.md §R4 and Edge Case §"Drift schema entity بدون SQL
        // CREATE statement جاهز" pre-authorized deferring constraint
        // kinds when the Drift API limits us. Log once per table so the
        // gap is visible in diagnostics.
        // (No-op for now — see comment block above. Drift API limitation
        // tracked for follow-up.)
      } else if (entity is Index) {
        // T017 — index-level parity. CREATE INDEX IF NOT EXISTS via
        // Migrator first, falling back to a no-op warn if Drift's emitted
        // DDL is PG-incompatible.
        final indexName = entity.entityName.toLowerCase();
        if (pgIndexes.contains(indexName)) continue;
        try {
          await Migrator(this).create(entity);
          healedCount++;
          await DiagnosticLogger.log(
            'PG-PARITY-HEAL',
            'index=$indexName action=created',
          );
        } catch (e) {
          // 🔴 هذا المسارُ كان يبتلع **كلَّ** فهرس: مُهاجرُ drift يرمي على PG
          // لأنّ الـcodegen لهجةُ sqlite وحدَها، فيُسجَّل «انحرافٌ» ويمضي.
          // والجملةُ المولَّدةُ محمولةٌ أصلاً — تُنفَّذ خامّاً قبل الاستسلام.
          try {
            await customStatement(pgPortableIndexSql(entity));
            healedCount++;
            await DiagnosticLogger.log(
              'PG-PARITY-HEAL',
              'index=$indexName action=created_portable',
            );
          } catch (e2) {
            // إخفاقٌ حقيقيٌّ الآن (عمودٌ ناقصٌ على هذه التنصيبة مثلاً).
            // تحذيرٌ فقط كي لا يُسقط فهرسٌ واحدٌ التمريرةَ كلَّها.
            driftCount++;
            await DiagnosticLogger.log(
              'PG-PARITY-DRIFT',
              'index=$indexName reason=create_index_failed '
                  'migrator_error=$e portable_error=$e2',
            );
          }
        }
      } else {
        // Trigger / View / unknown kind — explicitly out of Spec 130 scope
        // per Assumption A3. Logged so the pass NEVER silently swallows an
        // entity kind (FR-006).
        await DiagnosticLogger.log(
          'PG-PARITY-SKIP',
          'kind=${entity.runtimeType} entity=${entity.entityName} '
              'reason=out_of_scope',
        );
      }
    }

    // Extras detection — PG tables not in Drift schema. CREATE-only policy
    // means we never drop them (FR-004); warn-only.
    for (final pgTable in pgTables) {
      if (!driftTableNames.contains(pgTable)) {
        await DiagnosticLogger.log(
          'PG-PARITY-EXTRA',
          'table=$pgTable reason=not_in_drift_schema action=preserved',
        );
      }
    }

    sw.stop();

    if (fatalErrors.isNotEmpty) {
      await DiagnosticLogger.log(
        'PG-PARITY-FATAL',
        'count=${fatalErrors.length} '
            'entities=${fatalErrors.map((e) => e.entity).join(',')}',
      );
      throw PgSchemaParityException(
        reasonAr:
            'فشل إصلاح المخطط الذاتى. الكيانات المتأثرة: '
            '${fatalErrors.map((e) => e.entity).join('، ')}. '
            'راجع السجل التشخيصى للتفاصيل.',
        details: fatalErrors.map((e) => e.detail).toList(),
        failedEntities: fatalErrors.map((e) => e.entity).toList(),
      );
    }

    await DiagnosticLogger.log(
      'PG-PARITY-OK',
      'healed=$healedCount drift=$driftCount '
          'duration=${sw.elapsedMilliseconds}ms',
    );
  }

  /// Build a single column definition (`"$name" $type [NOT NULL] [DEFAULT ...]`)
  /// in PG dialect — used by both `_buildPgCreateTableSql` (via inlining)
  /// and the column-heal path (T016) which emits ALTER ADD COLUMN with this
  /// fragment.
  ///
  /// SERIAL PK columns return their own `SERIAL PRIMARY KEY` string. The
  /// column-heal path must filter `hasAutoIncrement` out before calling
  /// this — PostgreSQL doesn't allow ALTER ADD COLUMN on a SERIAL PK.
  ///
  /// Set [forExistingTable] when the fragment is destined for
  /// `ALTER TABLE ... ADD COLUMN` rather than `CREATE TABLE`. On an existing
  /// table a `NOT NULL` column with no `DEFAULT` is rejected outright by
  /// PostgreSQL if any row is present, so that combination is degraded to
  /// nullable — see the comment at the nullability decision below.
  String _buildPgColumnDef(GeneratedColumn col, {bool forExistingTable = false}) {
    final colName = col.$name;
    if (col.type == DriftSqlType.int && col.hasAutoIncrement) {
      return '"$colName" SERIAL PRIMARY KEY';
    }

    String pgType;
    if (col.type == DriftSqlType.int) {
      pgType = 'INTEGER';
    } else if (col.type == DriftSqlType.bigInt) {
      pgType = 'BIGINT';
    } else if (col.type == DriftSqlType.string) {
      pgType = 'TEXT';
    } else if (col.type == DriftSqlType.bool) {
      pgType = 'BOOLEAN';
    } else if (col.type == DriftSqlType.double) {
      pgType = 'DOUBLE PRECISION';
    } else if (col.type == DriftSqlType.dateTime) {
      pgType = 'BIGINT';
    } else if (col.type == DriftSqlType.blob) {
      pgType = 'BYTEA';
    } else if (col.type == DriftSqlType.any) {
      // DriftSqlType.any is the schema-loose "untyped column" marker. PG
      // doesn't have a true equivalent — fall back to TEXT so the ALTER
      // succeeds; drift detection is suppressed via the empty acceptable
      // list above.
      pgType = 'TEXT';
    } else {
      pgType = 'TEXT';
    }

    final defaultClause = _buildPgDefaultClause(col);
    var nullable = col.$nullable ? '' : ' NOT NULL';

    // PostgreSQL rejects `ALTER TABLE ... ADD COLUMN ... NOT NULL` on a table
    // that already has rows unless a DEFAULT backfills them (23502). Drift
    // columns declared required-but-without-a-default therefore make the heal
    // pass throw, and that exception is fatal: it aggregates into
    // `PgSchemaParityException`, `database_startup` rethrows it, and the retry
    // button just re-runs the same ALTER — a permanently bricked install with
    // no exit but `--use-sqlite`. That is the v132 failure class exactly.
    //
    // The boot path must never throw for something this recoverable, so the
    // column lands nullable and the caller logs it. Promoting it to NOT NULL
    // needs a backfill decision plus an ACCESS EXCLUSIVE lock and a full table
    // scan — offline reconciliation work, not something to do while the app is
    // trying to start.
    if (forExistingTable && !col.$nullable && defaultClause.isEmpty) {
      nullable = '';
    }

    return '"$colName" $pgType$nullable$defaultClause';
  }

  /// The ` DEFAULT ...` fragment for [col] in PG dialect, or `''` when drift
  /// declares no default this builder can render. Split out of
  /// [_buildPgColumnDef] so the heal path can ask "would this column arrive
  /// with a backfill value?" without re-deriving the answer.
  String _buildPgDefaultClause(GeneratedColumn col) {
    if (col.defaultValue == null) return '';
    final defaultStr = col.defaultValue.toString();
    if (defaultStr.contains('currentDateAndTime') ||
        defaultStr.contains('CurrentDateTimeExpression')) {
      return ' DEFAULT (EXTRACT(EPOCH FROM NOW())::bigint)';
    }
    if (col.defaultValue is Constant) {
      final val = (col.defaultValue as Constant).value;
      if (val is bool) return ' DEFAULT ${val ? 'TRUE' : 'FALSE'}';
      if (val is String) return " DEFAULT '${val.replaceAll("'", "''")}'";
      return ' DEFAULT $val';
    }
    return '';
  }

  /// ISS-08: Migration logic delegated to database_migrations.dart
  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        // PostgreSQL: create strftime() compatibility function BEFORE createAll
        if (_isPostgres) {
          await _createPostgresCompatLayer();
          // Use PostgreSQL-safe table creation with per-table fallback
          await _createAllForPostgres(m);
        } else {
          await m.createAll();
          // Spec 151: idx_je_autopost_dedup is raw SQL (not a Drift table
          // entity), so createAll() never emits it. Create it here so FRESH
          // SQLite installs get the same return-exempt dedup backstop that
          // upgraded DBs get via the v150 migration. Uses the shared SoT SQL so
          // fresh installs and upgrades agree on the exemption shape.
          await customStatement(kCreateJeAutopostDedupIndexSql);
          // نفس المنطق: فهارس خام مش كيانات Drift، فـcreateAll() ما بيصدّرهاش.
          // التنصيبات الجديدة لازم تاخد نفس حراسة B1/B2 اللي بتاخدها المُرقّاة.
          await customStatement(kCreateSalaryPaymentDedupIndexSql);
          await customStatement(kCreateAttendanceDayDedupIndexSql);
          // v159: فهرسُ المسار الساخن لمحرِّك الحجز — نفسُ المنطق، فهرسٌ
          // خامٌّ لا كيانُ drift فـ`createAll()` ما بيصدّرهوش.
          await customStatement(kCreateBookingResourceSlotIndexSql);
          // ٦‑١: نفسُ المنطق لكن على **جدول** لا فهرس. `EInvoiceStatusLog`
          // صنفُ جدولٍ غيرُ مُعلَنٍ في `@DriftDatabase`، فتنصيبةٌ جديدةٌ
          // تفتقده تماماً بينما المُرقّاةُ تأخذه من هجرة v81 — و
          // `e_invoicing_dao` يقرؤه ويكتبه بـSQL خامّ.
          await customStatement(kCreateEInvoiceStatusLogSql);
          await customStatement(kCreateEInvoiceStatusLogIndexSql);
        }
        // seedInitialData + syncDefaultAccounts moved to beforeOpen
        // (after defensive v110 column additions)
      },
      onUpgrade: (Migrator m, int from, int to) async {
        // PostgreSQL: skip SQLite-specific migrations entirely.
        // PG schema is created fresh via _createAllForPostgres() in onCreate.
        // Incremental migrations use SQLite-only syntax (AUTOINCREMENT, PRAGMA,
        // INSERT OR IGNORE, typeof(), etc.) that fails on PostgreSQL.
        if (_isPostgres) {
          debugPrint('[PG] onUpgrade skipped (from=$from to=$to) — PG uses fresh schema');
          return;
        }
        await runOnUpgrade(m, from, to);
      },
      beforeOpen: (details) async {
        await runBeforeOpen(details);
      },
    );
  }
  // Seeding methods have been moved to DatabaseSeeder extension in database_seeder.dart
  // to keep the main database.dart file clean and manageable.

  // ═══════════════════════════════════════════════════════════════════════════
  // UTILITY METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  /// ═══════════════════════════════════════════════════════════════════════
  /// INVOICE / VOUCHER NUMBER PREFIXES — single source of truth
  /// ═══════════════════════════════════════════════════════════════════════
  ///
  /// Canonical defaults for each of the eight document types. Each prefix
  /// was chosen to be visually distinct even at a glance — `POS` / `SINV`
  /// / `SRET` / `PINV` / `PRET` / `RCPT` / `PMT` / `QUOT`. User-configured
  /// overrides live in the `settings` table under the matching key from
  /// [_prefixSettingKeys].
  static const defaultSalesPosPrefix = 'POS';
  static const defaultSalesManualPrefix = 'SINV';
  static const defaultSalesReturnPrefix = 'SRET';
  static const defaultPurchasePrefix = 'PINV';
  static const defaultPurchaseReturnPrefix = 'PRET';
  static const defaultReceiptVoucherPrefix = 'RCPT';
  static const defaultPaymentVoucherPrefix = 'PMT';
  static const defaultQuotationPrefix = 'QUOT';

  /// Map of canonical prefixes → setting key. Callers pass the canonical
  /// prefix (or one of the legacy aliases in [_prefixAliases]); the
  /// `generateInvoiceNumber` entry point normalises to the canonical form
  /// before looking up either a user override or the default.
  static const _prefixSettingKeys = <String, String>{
    defaultSalesPosPrefix: 'prefix_sales_pos',
    defaultSalesManualPrefix: 'prefix_sales_manual',
    defaultSalesReturnPrefix: 'prefix_sales_return',
    defaultPurchasePrefix: 'prefix_purchase',
    defaultPurchaseReturnPrefix: 'prefix_purchase_return',
    defaultReceiptVoucherPrefix: 'prefix_receipt_voucher',
    defaultPaymentVoucherPrefix: 'prefix_payment_voucher',
    defaultQuotationPrefix: 'prefix_quotation',
  };

  /// Legacy → canonical alias map. Historical call sites hard-coded older
  /// prefix strings (`R-`, `INV`, `RET-`, `PUR`, `RV`, `PV`, `QUO`, ...).
  /// We normalise them on entry so every new document flows through the
  /// same canonical prefix pipeline AND honours the shared settings keys.
  static const _prefixAliases = <String, String>{
    // Sales
    'R': defaultSalesPosPrefix,
    'R-': defaultSalesPosPrefix,
    'Receipt': defaultSalesPosPrefix,
    'Recept': defaultSalesPosPrefix,
    'INV': defaultSalesManualPrefix,
    'RET-': defaultSalesReturnPrefix,
    'SRET-': defaultSalesReturnPrefix,
    // Purchases
    'PUR': defaultPurchasePrefix,
    'PRET-': defaultPurchaseReturnPrefix,
    // Vouchers
    'RV': defaultReceiptVoucherPrefix,
    'PV': defaultPaymentVoucherPrefix,
    // Quotations
    'QUO': defaultQuotationPrefix,
  };

  /// All canonical prefixes — used by the settings screen to validate that
  /// no two document types accidentally share the same user-configured
  /// prefix.
  static List<String> get canonicalInvoicePrefixes => const [
        defaultSalesPosPrefix,
        defaultSalesManualPrefix,
        defaultSalesReturnPrefix,
        defaultPurchasePrefix,
        defaultPurchaseReturnPrefix,
        defaultReceiptVoucherPrefix,
        defaultPaymentVoucherPrefix,
        defaultQuotationPrefix,
      ];

  /// Generate a unique, thread-safe invoice number based on DocumentSequences.
  ///
  /// Takes either a canonical prefix (`POS`, `SINV`, `SRET`, `PINV`, `PRET`,
  /// `RCPT`, `PMT`, `QUOT`) or a legacy alias (`R-`, `INV`, `RET-`, `PUR`,
  /// `RV`, `PV`, `QUO`, ...). All aliases are normalised to their canonical
  /// form up-front, so legacy call-sites keep working without changes.
  ///
  /// User overrides from the "إعدادات ترقيم المستندات" screen (settings
  /// keyed by [_prefixSettingKeys]) are honoured verbatim as the DISPLAY
  /// prefix. The SEQUENCE counter stays locked to the canonical prefix
  /// so renaming the display prefix never restarts the counter.
  ///
  /// Output format: `<DISPLAY>-<counter>` (e.g. `POS-1`, `SINV-42`) since the
  /// 2026-04 product change. Unified across every document type so the printed
  /// invoices look consistent.
  ///
  /// On PostgreSQL the counter row is locked with `FOR UPDATE` before it is
  /// read — without that, concurrent callers on separate connections issue
  /// duplicate numbers, and there is no UNIQUE index on `invoice_number` to
  /// catch them.
  Future<String> generateInvoiceNumber(String prefix) async {
    // 066 (D5-001) — defensive guard. The counter advance and the dependent
    // voucher insert MUST be atomic; Drift makes a nested transaction() into
    // a SAVEPOINT only when the caller is already in a transaction. Calling
    // bare → the inner txn commits independently → if the caller's insert
    // fails the counter is permanently advanced → Egyptian-VAT-illegal gap.
    // See specs/066-voucher-numbering-atomicity/contracts/numbering-atomicity.md C-1.
    // ignore: invalid_use_of_internal_member
    if (identical(resolvedEngine, this)) {
      throw StateError(
        'generateInvoiceNumber must be called inside a db.transaction(). '
        'See specs/066-voucher-numbering-atomicity/contracts/numbering-atomicity.md',
      );
    }
    return transaction(() async {
      debugPrint(
        '[GEN_INV_DEBUG] generateInvoiceNumber called with prefix: "$prefix"',
      );

      // Normalise any legacy alias onto its canonical prefix. Unknown
      // prefixes (e.g. `VD` / `ADV` used by ad-hoc helpers) pass through
      // unchanged — they still follow the same counter + format pipeline.
      final normalizedPrefix = _prefixAliases[prefix] ?? prefix;

      // Check for user-configured custom prefix for this document type.
      String displayPrefix = normalizedPrefix;
      final settingKey = _prefixSettingKeys[normalizedPrefix];
      if (settingKey != null) {
        final customPrefix = await getSettingValue(settingKey);
        if (customPrefix != null && customPrefix.isNotEmpty) {
          displayPrefix = customPrefix;
        } else {
          // Legacy fallback: the old single `invoice_code_prefix` setting
          // still applies to all three sales-side types if nobody set a
          // per-type override.
          final isSalesPrefix = normalizedPrefix == defaultSalesPosPrefix ||
              normalizedPrefix == defaultSalesManualPrefix ||
              normalizedPrefix == defaultSalesReturnPrefix;
          if (isSalesPrefix) {
            final legacyPrefix = await getSettingValue('invoice_code_prefix');
            if (legacyPrefix != null && legacyPrefix.isNotEmpty) {
              displayPrefix = legacyPrefix;
            }
          }
        }
      }

      // PostgreSQL: take the row lock BEFORE reading the counter.
      //
      // The read-modify-write below is only atomic if nobody else can read the
      // same `next_value` in between. On SQLite that is free — the global write
      // lock serialises the whole transaction. On PostgreSQL under READ
      // COMMITTED it is not: two connections both read N, both compute N, and
      // the second UPDATE simply blocks until the first commits and then writes
      // the same N+1. Both callers walk away holding document number N.
      //
      // Measured on a live PG with two connections: 16 allocations produced 8
      // distinct numbers — a 100% collision rate on every concurrent pair, not
      // an intermittent race. And nothing catches it downstream: there is no
      // UNIQUE index on `invoice_number` (see the note where the number is
      // returned).
      //
      // `FOR UPDATE` makes the second reader wait for the first to commit, so
      // it reads N+1 and the sequence advances correctly.
      if (_isPostgres) {
        await customStatement(
          'SELECT 1 FROM document_sequences WHERE prefix = ? FOR UPDATE',
          [normalizedPrefix],
        );
      }

      // Counter lives on the canonical prefix so a display-prefix change
      // from the settings screen never rewinds the sequence.
      final existing = await (select(
        documentSequences,
      )..where((s) => s.prefix.equals(normalizedPrefix))..limit(1))
          .getSingleOrNull();

      if (existing == null) {
        // First-time backfill: count rows that already share the same
        // canonical prefix or any of its aliases so we don't re-use an
        // existing number. Bounded query (`LIKE prefix%`) and also a
        // scan over aliases so legacy `INV...` rows don't collide with
        // fresh `SINV...` ones.
        final aliasesForThis = _prefixAliases.entries
            .where((e) => e.value == normalizedPrefix)
            .map((e) => e.key)
            .toList()
          ..add(normalizedPrefix);

        int maxExisting = 0;
        for (final alias in aliasesForThis) {
          final count = await (selectOnly(salesInvoices)
                ..addColumns([salesInvoices.id.count()])
                ..where(salesInvoices.invoiceNumber.like('$alias%')))
              .map((row) => row.read(salesInvoices.id.count()))
              .getSingle();
          if ((count ?? 0) > maxExisting) maxExisting = count!;
        }

        // Seed the row at the FIRST number to hand out and let the shared
        // allocation below consume it. The insert must be idempotent: the
        // `FOR UPDATE` above locks nothing when the row does not exist yet, so
        // two connections racing the very first use of a prefix both land here
        // and both try to INSERT. A plain insert makes the loser die on
        // `23505 document_sequences_pkey`, which aborts the whole caller
        // transaction — i.e. the first sale on a newly configured prefix fails.
        // Losing the race is not an error: the winner seeded the identical
        // value, so DO NOTHING and read it back under the lock.
        final seed = maxExisting + 1;
        if (_isPostgres) {
          await customStatement(
            'INSERT INTO document_sequences (prefix, next_value) '
            'VALUES (?, ?) ON CONFLICT (prefix) DO NOTHING',
            [normalizedPrefix, seed],
          );
          // The seed insert above is what the earlier FOR UPDATE could not
          // lock. Take the lock now that the row is guaranteed to exist.
          await customStatement(
            'SELECT 1 FROM document_sequences WHERE prefix = ? FOR UPDATE',
            [normalizedPrefix],
          );
        } else {
          await into(documentSequences).insert(
            DocumentSequencesCompanion.insert(
              prefix: normalizedPrefix,
              nextValue: Value(seed),
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      }

      // Single allocation path for both the freshly seeded and the existing
      // row, so the counter advances in exactly one place under exactly one
      // lock. Re-read rather than reusing `existing`: when this call lost the
      // seed race, or waited on another transaction's FOR UPDATE, the
      // committed value has moved on.
      final seq = await (select(
        documentSequences,
      )..where((s) => s.prefix.equals(normalizedPrefix))..limit(1))
          .getSingleOrNull();

      final nextNumber = seq?.nextValue ?? 1;
      await (update(
        documentSequences,
      )..where((s) => s.prefix.equals(normalizedPrefix))).write(
        DocumentSequencesCompanion(nextValue: Value(nextNumber + 1)),
      );

      // Simplified format: `<DISPLAY>-<counter>` (e.g. `POS-1`, `SINV-42`).
      // Per product request 2026-04: drop the year + 6-digit zero-pad. Counter
      // is unbounded and human-readable.
      //
      // NOTE: this used to claim uniqueness was "guaranteed by the sequence
      // plus the UNIQUE index on invoice_number". There is no such index, on
      // either backend — `SalesInvoices.invoiceNumber` and
      // `PurchaseInvoices.invoiceNumber` are plain `text().withLength(max: 50)`
      // and the partial unique index was deliberately deferred because customer
      // databases may already hold duplicates (see
      // client_issue_m4_duplicate_invoice_no_test.dart). The sequence is the
      // ONLY guarantee, which is why the `FOR UPDATE` lock above is load-bearing
      // rather than defensive.
      return '$displayPrefix-$nextNumber';
    });
  }

  /// 066 (D5-001) — read-only peek at the per-prefix counter, used by tests
  /// to verify counter rollback on caller failure (see
  /// `test/unit/voucher_numbering_atomicity_test.dart`). Returns `0` if no
  /// row exists yet for the prefix (first-time-use state).
  @visibleForTesting
  Future<int> peekNumberingCounter(String prefix) async {
    final normalizedPrefix = _prefixAliases[prefix] ?? prefix;
    final seq = await (select(documentSequences)
          ..where((s) => s.prefix.equals(normalizedPrefix))
          ..limit(1))
        .getSingleOrNull();
    return seq?.nextValue ?? 0;
  }

  // READ-ONLY — Egyptian VAT prohibits auto-renumbering.
  // See specs/066-voucher-numbering-atomicity/contracts/numbering-atomicity.md C-2.
  /// 066 (D5-001) — READ-ONLY diagnostic. Egyptian VAT prohibits
  /// auto-renumbering, so this query reports gaps but offers NO write path.
  /// See specs/066-voucher-numbering-atomicity/contracts/numbering-atomicity.md C-2.
  ///
  /// Returns one row per prefix where `(counterNext - 1) > maxUsedNumber`,
  /// scanning `sales_invoices`, `purchase_invoices`, and `safe_transactions`
  /// for the highest numeric tail (`<prefix>-<n>`).
  Future<List<NumberingGapReport>> auditNumberingGaps() async {
    final sequences = await select(documentSequences).get();
    final results = <NumberingGapReport>[];
    for (final seq in sequences) {
      int maxUsed = 0;

      Future<int> maxNumberInTable(String table, String numberCol,
          {bool checkDeleted = true}) async {
        final deletedClause =
            checkDeleted ? 'AND deleted_at IS NULL' : '';
        final rows = await customSelect(
          "SELECT MAX(CAST(SUBSTR($numberCol, INSTR($numberCol, '-') + 1) "
          "AS INTEGER)) AS max_n FROM $table "
          "WHERE $numberCol LIKE '%-%' $deletedClause "
          "AND SUBSTR($numberCol, 1, INSTR($numberCol, '-') - 1) = ?",
          variables: [Variable.withString(seq.prefix)],
        ).getSingleOrNull();
        if (rows == null) return 0;
        final v = rows.data['max_n'];
        if (v is int) return v;
        if (v is num) return v.toInt();
        return 0;
      }

      final n1 = await maxNumberInTable('sales_invoices', 'invoice_number');
      if (n1 > maxUsed) maxUsed = n1;
      final n2 = await maxNumberInTable('purchase_invoices', 'invoice_number');
      if (n2 > maxUsed) maxUsed = n2;
      final n3 = await maxNumberInTable('safe_transactions', 'voucher_number',
          checkDeleted: false);
      if (n3 > maxUsed) maxUsed = n3;

      final gap = (seq.nextValue - 1) - maxUsed;
      if (gap > 0) {
        results.add(NumberingGapReport(
          prefix: seq.prefix,
          counterNext: seq.nextValue,
          maxUsedNumber: maxUsed,
          gapCount: gap,
        ));
      }
    }
    results.sort((a, b) => b.gapCount.compareTo(a.gapCount));
    return results;
  }

  /// Validates the set of user-configured prefix overrides for invoice
  /// numbering. Returns `null` when every configured prefix is unique
  /// (case-insensitive) across document types; otherwise returns a
  /// user-facing error message listing the conflict. Designed to be
  /// called by the "إعدادات ترقيم المستندات" screen before saving.
  Future<String?> validateInvoicePrefixes() async {
    // Collect current effective prefix for each type — user override if
    // set, otherwise the canonical default.
    final effective = <String, String>{}; // canonical → displayPrefix
    for (final entry in _prefixSettingKeys.entries) {
      final canonical = entry.key;
      final key = entry.value;
      final custom = (await getSettingValue(key))?.trim();
      effective[canonical] =
          (custom != null && custom.isNotEmpty) ? custom : canonical;
    }

    // Detect duplicate display prefixes (case-insensitive).
    final Map<String, List<String>> grouped = {};
    effective.forEach((canonical, display) {
      final k = display.toLowerCase();
      grouped.putIfAbsent(k, () => []).add(canonical);
    });
    for (final e in grouped.entries) {
      if (e.value.length > 1) {
        return 'تعارض فى بادئات الترقيم — البادئة "${effective[e.value.first]}" '
            'مكرّرة على الأنواع: ${e.value.join(', ')}. '
            'يجب أن تكون كل بادئة فريدة.';
      }
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // S01: DAO methods — extracted from UI layer (security hardening)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Ensure modifier tables exist (fallback for pre-v70 DBs).
  Future<void> ensureModifierTables() async {
    // Cluster 030 / Bug C: PostgreSQL doesn't accept SQLite's
    // `INTEGER PRIMARY KEY AUTOINCREMENT` syntax. The previous version
    // passed the SQLite DDL verbatim to PG which crashed every time the
    // server's modifier-management dialog was opened. Branch on
    // `_isPostgres` and emit `SERIAL PRIMARY KEY` (PG) or
    // `INTEGER PRIMARY KEY AUTOINCREMENT` (SQLite). Add a defensive
    // `ALTER TABLE … ADD COLUMN IF NOT EXISTS sort_order` so legacy
    // installs whose table predates the column also self-heal.
    final pkClause = _isPostgres
        ? 'id SERIAL PRIMARY KEY'
        : 'id INTEGER PRIMARY KEY AUTOINCREMENT';
    final boolType = _isPostgres ? 'BOOLEAN' : 'INTEGER';
    final boolFalse = _isPostgres ? 'false' : '0';
    final boolTrue = _isPostgres ? 'true' : '1';

    await customStatement('''
      CREATE TABLE IF NOT EXISTS modifier_groups (
        $pkClause,
        name TEXT NOT NULL,
        type TEXT NOT NULL DEFAULT 'addon',
        min_select INTEGER NOT NULL DEFAULT 0,
        max_select INTEGER NOT NULL DEFAULT 1,
        is_required $boolType NOT NULL DEFAULT $boolFalse,
        is_active $boolType NOT NULL DEFAULT $boolTrue,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS modifier_items (
        $pkClause,
        group_id INTEGER NOT NULL REFERENCES modifier_groups(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        extra_price REAL NOT NULL DEFAULT 0,
        is_default $boolType NOT NULL DEFAULT $boolFalse,
        is_active $boolType NOT NULL DEFAULT $boolTrue,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS product_modifier_groups (
        $pkClause,
        product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
        modifier_group_id INTEGER NOT NULL REFERENCES modifier_groups(id) ON DELETE CASCADE,
        sort_order INTEGER NOT NULL DEFAULT 0,
        UNIQUE(product_id, modifier_group_id)
      )
    ''');

    // Defensive ADD COLUMN — older installs whose modifier_groups was
    // created before sort_order was added still work after the schema
    // is reconciled.
    if (_isPostgres) {
      // ٦‑٢: خادمٌ نُصِّب قبل هذا الإصلاح يحمل شكلَ الخطوة 4.5 القديم —
      //   (id, name, min_selection, max_selection, is_active)
      // وينقصه **أربعةٌ** يكتبها `createModifierGroup` لا واحد، فكانت كلُّ
      // محاولةِ إنشاءِ مجموعةٍ تنهار على PG والميزةُ معطَّلةً بالكامل.
      //
      // ⚠️ و`min_selection`/`max_selection` القديمان يبقيان بلا ضرر: لهما
      // `DEFAULT` فالإدراجُ الذي يتجاهلهما يمرّ. وإعادةُ تسميتهما كانت ستحتاج
      // `RENAME COLUMN` بلا `IF EXISTS` — أثقلَ وأخطرَ من إضافةِ الصحيح.
      for (final stmt in [
        "ALTER TABLE modifier_groups ADD COLUMN IF NOT EXISTS type TEXT NOT NULL DEFAULT 'addon'",
        'ALTER TABLE modifier_groups ADD COLUMN IF NOT EXISTS min_select INTEGER NOT NULL DEFAULT 0',
        'ALTER TABLE modifier_groups ADD COLUMN IF NOT EXISTS max_select INTEGER NOT NULL DEFAULT 1',
        'ALTER TABLE modifier_groups ADD COLUMN IF NOT EXISTS is_required BOOLEAN NOT NULL DEFAULT FALSE',
        'ALTER TABLE modifier_groups ADD COLUMN IF NOT EXISTS sort_order INTEGER NOT NULL DEFAULT 0',
        'ALTER TABLE modifier_items ADD COLUMN IF NOT EXISTS sort_order INTEGER NOT NULL DEFAULT 0',
      ]) {
        try {
          await customStatement(stmt);
        } catch (_) {/* already exists */}
      }
    }
  }

  /// Update safe name, bank info.
  /// Update safe details. PostgreSQL-compatible.
  Future<void> updateSafeDetails({
    required int safeId,
    required String name,
    String? bankName,
    String? accountNumber,
  }) async {
    await (update(safes)..where((s) => s.id.equals(safeId))).write(
      SafesCompanion(
        name: Value(name),
        bankName: Value(bankName),
        accountNumber: Value(accountNumber),
      ),
    );
  }

  /// Set a safe as the default for its branch (scoped per-branch).
  /// PostgreSQL-compatible: uses raw SQL with sqlBool().
  Future<void> setDefaultSafe(int safeId) async {
    final falseVal = sqlBool(false);
    final trueVal = sqlBool(true);

    // Look up the target safe's branch
    final targetSafe = await (select(safes)..where((s) => s.id.equals(safeId))).getSingleOrNull();
    final branchId = targetSafe?.branchId;

    // Clear defaults only within the same branch scope
    if (branchId != null) {
      await customStatement(
        'UPDATE safes SET is_default = $falseVal WHERE branch_id = ?',
        [branchId],
      );
    } else {
      // No branch — clear defaults only among safes with no branch
      await customStatement(
        'UPDATE safes SET is_default = $falseVal WHERE branch_id IS NULL',
      );
    }

    await customStatement(
      'UPDATE safes SET is_default = $trueVal, is_active = $trueVal WHERE id = ?',
      [safeId],
    );
  }

  /// Toggle safe active/inactive. PostgreSQL-compatible.
  Future<void> toggleSafeActive(int safeId, bool isActive) async {
    final boolVal = sqlBool(isActive);
    await customStatement(
      'UPDATE safes SET is_active = $boolVal WHERE id = ?',
      [safeId],
    );
  }

  /// Delete a non-default safe. PostgreSQL-compatible.
  ///
  /// Feature 004 (US1, FR-007): rejects deletion when the safe's linked
  /// CoA sub-account has any journal-entry lines. Mirrors the rule already
  /// applied to parties — preserves audit trail integrity.
  Future<void> deleteSafeById(int safeId) async {
    await transaction(() async {
      // Look up the linked account before mutating anything.
      final safe = await (select(safes)
            ..where((s) => s.id.equals(safeId))
            ..limit(1))
          .getSingleOrNull();
      if (safe == null) return;

      if (safe.linkedAccountId != null) {
        final movementCountRow = await customSelect(
          'SELECT COUNT(*) AS c FROM journal_entry_lines WHERE account_id = ?',
          variables: [Variable.withInt(safe.linkedAccountId!)],
        ).getSingle();
        final count = movementCountRow.read<int>('c');
        if (count > 0) {
          throw Exception(
            'لا يمكن حذف الصندوق "${safe.name}" لأن الحساب المرتبط به '
            'يحتوى على قيود محاسبية ($count قيد). يرجى تصفية الحركات أولاً.',
          );
        }
      }

      await (delete(safes)..where((s) => s.id.equals(safeId) & s.isDefault.equals(false))).go();
    });
  }

  /// Get per-product stock for a specific warehouse. PostgreSQL-compatible.
  Future<Map<int, double>> getWarehouseStockMap(int warehouseId) async {
    final rows = await (select(inventoryBalances)
      ..where((ib) => ib.warehouseId.equals(warehouseId))
    ).get();
    final map = <int, double>{};
    for (final row in rows) {
      map[row.productId] = row.quantity;
    }
    return map;
  }

  /// Get journal entry lines with account info (code + name) for display.
  /// PostgreSQL-compatible: uses Drift selectOnly + join.
  Future<List<Map<String, dynamic>>> getJournalEntryLinesWithAccounts(int entryId) async {
    final query = selectOnly(journalEntryLines).join([
      innerJoin(accounts, accounts.id.equalsExp(journalEntryLines.accountId)),
    ]);
    query.addColumns([
      journalEntryLines.debit,
      journalEntryLines.credit,
      journalEntryLines.description,
      accounts.code,
      accounts.name,
    ]);
    query.where(journalEntryLines.entryId.equals(entryId));
    query.orderBy([OrderingTerm.asc(journalEntryLines.id)]);
    
    final rows = await query.get();
    return rows.map((row) => {
      'debit': row.read(journalEntryLines.debit) ?? 0.0,
      'credit': row.read(journalEntryLines.credit) ?? 0.0,
      'description': row.read(journalEntryLines.description),
      'account_code': row.read(accounts.code),
      'account_name': row.read(accounts.name),
    }).toList();
  }

  /// مَن أنشأ القيدَ — اسمُه المعروض، أو `null` حين لا يُعرَف.
  ///
  /// ═══ ولماذا `created_by` لا سجلُّ النشاط ═══
  ///
  /// `created_by` عمودٌ **دفاعيٌّ** (يُكتَب بعبارةٍ خامّ لأنّ drift لا يعرفه)،
  /// يكتبه المسارُ اليدويُّ ويقرؤه ضابطُ «لا يعتمد القيدَ منشئُه». فهو
  /// الحقيقةُ المخزَّنةُ على الصفّ نفسِه.
  ///
  /// ⚠️ **و`null` ثلاثُ حالاتٍ لا واحدة**، وكلُّها تُعرَض «—» لا اسماً
  /// مخمَّناً:
  ///   ‏• قيدٌ **آليّ**: لا منشئَ بشريّاً أصلاً — مصدرُه مستندُه.
  ///   ‏• وقيدٌ **أقدمُ من العمود** (قبل إضافته).
  ///   ‏• ومستخدمٌ حُذف صفُّه — والربطُ `JOIN` فيُسقطه، وهو الصواب:
  ///     «لا يُعرَف» أصدقُ من رقمٍ بلا اسم.
  Future<String?> getJournalEntryCreator(int entryId) async {
    final row = await customSelect(
      'SELECT u.display_name AS creator '
      'FROM journal_entries e '
      'JOIN users u ON u.id = e.created_by '
      'WHERE e.id = ?',
      variables: [Variable.withInt(entryId)],
      readsFrom: {journalEntries, users},
    ).getSingleOrNull();
    final name = row?.read<String?>('creator');
    return (name == null || name.isEmpty) ? null : name;
  }

  /// Search sales invoices by invoice number (LIKE). PostgreSQL-compatible.
  Future<List<SalesInvoiceData>> searchInvoicesByNumber(String query) async {
    return (select(salesInvoices)
      ..where((s) => s.invoiceNumber.like('%$query%') & s.isDeleted.equals(false))
      ..orderBy([(s) => OrderingTerm.desc(s.invoiceDate)])
      ..limit(20)
    ).get();
  }

  /// Search customers / parties by phone (LIKE). PostgreSQL-compatible.
  Future<List<Party>> searchCustomerByPhone(String phone) async {
    return (select(parties)
      ..where((p) => p.phone.like('%$phone%') & p.isCustomer.equals(true))
      ..limit(1)
    ).get();
  }
}
