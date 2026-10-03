import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart'
    show DriftSqlType, TableUpdate, UpdateKind, Value, Variable;
import 'package:flutter/foundation.dart';
import '../data/database/database.dart';
import '../core/logging/diagnostic_logger.dart';
import 'conflict_resolution_service.dart';
import 'id_namespace_service.dart';
import 'security_service.dart';
import 'server_proxy.dart';
import 'sync_event_bus.dart';

/// P3.1 + P4.3 — Delta Pull Service
///
/// Pulls master-data changes from the server since the last recorded watermark
/// and upserts them into local SQLite. Transaction tables (invoices, payments)
/// are owned by the client's outbox and are NOT pulled here.
///
/// After each successful table pull:
///  - emits [SyncTablePulled] on [SyncEventBus] for UI widgets
///  - calls [AppDatabase.notifyUpdates] so Drift watch() queries react
///
/// Financial rows require manual review when a pending local outbox mutation
/// conflicts with a server change; they must not be silently server-wins.
const Set<String> kFinancialSyncTables = {
  'journal_entries',
  'journal_entry_lines',
  'sales_invoices',
  'purchase_invoices',
  'safe_transactions',
  'parties',
  'commercial_papers',
};

/// Watermarks are stored in the settings table as epoch-second strings under
/// keys of the form `_watermark__<tableName>`.
class DeltaPullService {
  DeltaPullService._();
  static final DeltaPullService instance = DeltaPullService._();

  AppDatabase? _db;
  bool _isPulling = false;

  /// All sync-hardened tables are pulled via delta. Order matters: parents
  /// must appear before their children so that FK references resolve on the
  /// client during upsert. The list mirrors the FK dependency graph that
  /// `SyncService._strategies` uses for ordered fullSync.
  ///
  /// Mirrors the server's `_syncPullTables` allowlist in api_handler.dart.
  static const List<String> pullTables = [
    // ── Tier 0: no FK dependencies ──
    'fiscal_years',
    'cost_centers',
    'accounts',
    'roles',
    'currencies',
    'categories',
    'units',
    'regions',
    'party_groups',
    'safes',
    // ⚠️ `printers` أُخرج من المزامنة — **قرارُ مالك 2026-08-31**.
    // الجدولُ يخلط إعداداً جهازيّاً (`port` = COM3) بإعدادٍ مشترَك
    // (`ip_address`)، و`_upsertRow` يستعمل `INSERT OR REPLACE` — فسحبُه
    // يدهس منفذَ طابعةِ كلِّ طرفيّةٍ بمنفذِ الخادم فتتوقّف الطباعةُ عليها.
    // وتعريفاتُ الطابعات تُضبَط محلّيّاً لكلِّ جهازٍ أصلاً، وهو الواقعُ
    // الفعليُّ اليوم — فالإخراجُ يوافق السلوكَ لا يغيّره.

    // ── Tier 1: depend on Tier 0 ──
    'accounting_periods',   // → fiscal_years
    // v175 / المرحلة ٦ — دفترُ الشيكات. **موضعُه هنا إلزاميٌّ لا تنظيميّ**:
    // `commercial_papers.cheque_book_id` تشير إليه وهي في الطبقة ٣، و
    // `_upsertRow` يكتب بالترتيب و`PRAGMA foreign_keys = ON` في الإنتاج —
    // فشيكٌ يسبق دفترَه يُسقَط صامتاً (الخطأُ مبتلَعٌ بـ`debugPrint`).
    'cheque_books',         // → accounts
    'branches',             // → regions, cost_centers
    'warehouses',           // → branches
    'price_lists',          // → currencies
    'users',                // → roles
    'shifts',
    // ⚠️ `activity_logs` أُخرج من المزامنة — **قرارُ مالك 2026-08-31**.
    // سجلٌّ إلحاقيٌّ بلا سقفٍ زمنيّ: `since = null` على متجرٍ بسنةِ تاريخٍ
    // يتجاوز سقفَ الصفحات (٢٠٠×٥٠٠) فيعيد السحبُ نفسَه كلَّ دورةٍ بلا
    // تقديمِ علامة. وكلُّ جهازٍ يرى ما سُجّل عليه وما وقع بعد انضمامه —
    // وهو الواقعُ الفعليُّ اليوم — والمراجعةُ المركزيّةُ من جهاز الخادم.

    // ── Tier 2: depend on Tier 1 ──
    'parties',              // → accounts, party_groups
    'products',             // → categories, units
    'modifier_groups',      // v176 — بياناتٌ رئيسةٌ عامّة
    'modifier_items',       // → modifier_groups
    'product_modifier_groups', // → products, modifier_groups
    'price_list_items',     // → price_lists, products
    'product_barcodes',     // → products
    'product_units',        // → products, units

    // ── Tier 3: transactional headers ──
    'sales_invoices',       // → parties, warehouses
    'purchase_invoices',    // → parties, warehouses
    'held_orders',          // → parties
    'sales_orders',         // → parties, warehouses
    'purchase_orders',      // → parties, warehouses
    'quotations',           // → parties
    'payments',             // → parties, safes
    'journal_entries',      // → accounts
    'safe_transactions',    // → safes
    'commercial_papers',    // → parties
    // v184 — دفاترُ السندات (المرحلة هـ / E3). الدفترُ قبل أوراقه الملغاة.
    'voucher_books',                  // → branches
    'voucher_book_leaves_cancelled',  // → voucher_books
    'stock_movements',      // → products, warehouses

    // ── Tier 4: transactional items ──
    'sales_invoice_items',     // → sales_invoices, products
    'purchase_invoice_items',  // → purchase_invoices, products
    // v174 / المرحلة ٨ — وسمُ الاستيراد. **موضعُه بعد `purchase_invoices`
    // إلزاميٌّ**: `purchase_invoice_id` مفتاحٌ خارجيٌّ و`_upsertRow`
    // **يبتلع** خطأَه بـ`debugPrint` ويمضي — فوسمٌ يسبق فاتورتَه
    // يُسقَط صامتاً، فتُقرأ الفاتورةُ محلّيّةً إلى الأبد.
    'import_purchase_details', // → purchase_invoices, parties
    'held_order_items',        // → held_orders, products
    'sales_order_items',       // → sales_orders, products
    'purchase_order_items',    // → purchase_orders, products
    'quotation_items',         // → quotations, products
    'payment_allocations',     // → payments

    // ── Tier 5: مستنداتُ الأثر المحاسبيّ (v166 / المرحلة ٢) ──
    //
    // القيدُ كان يُزامَن ومستندُه لا، فدفترُ الخادم يحمل أثراً بلا مصدرٍ
    // يفسّره. والترتيبُ هنا يتبع المفاتيحَ حرفاً — الأبُ قبل ابنه — لأنّ
    // `_upsertRow` يكتب بالترتيب، وابنٌ يسبق أباه يكسر مفتاحَه.
    //
    // ⚠️ و`bill_of_materials` هنا وإن لم تكن من الأحدَ عشرَ الأصليّة:
    //    `manufacturing_orders` و`bom_components` تشيران إليها، وكانت
    //    تبدو مُزامَنةً لأنّ اسمَها يرد في **تعليقٍ** فحسب.
    'asset_categories',        // → accounts
    'op_expense_categories',
    'bill_of_materials',       // → products
    'fixed_assets',            // → asset_categories, cost_centers, accounts
    'manufacturing_orders',    // → bill_of_materials, warehouses
    'bom_components',          // → bill_of_materials, products
     'butchery_templates',     // → products
     'butchery_template_lines', // → butchery_templates, products
     'butchery_orders',        // → butchery_templates, products, warehouses
     'butchery_order_lines',   // → butchery_orders, products
    'op_expenses',             // → op_expense_categories, branches, cost_centers
    'asset_depreciations',     // → fixed_assets
    // v175 / المرحلة ٧ — طلبُ استبعاد أصل. **موضعُه بعد `fixed_assets`
    // إلزاميّ**: يشير إليه بمفتاحٍ خارجيّ، و`_upsertRow` يبتلع خطأَ المفتاح
    // بـ`debugPrint` ويمضي — فطلبٌ يسبق أصلَه يُسقَط صامتاً.
    'asset_disposals',         // → fixed_assets, parties, users, cost_centers
    'mfg_order_costs',         // → manufacturing_orders
    'landed_cost_sheets',      // → purchase_invoices, users
    'landed_cost_items',       // → landed_cost_sheets, parties
    'landed_cost_allocations', // → landed_cost_sheets, products, purchase_invoice_items
    // §٦‑٢ (v172) — مستندُ مرتجع الشراء. نفسُ علّة هذه الطبقة حرفاً: «القيدُ
    // كان يُزامَن ومستندُه لا» — إلّا أنّ المستندَ هنا **لم يكن موجوداً
    // أصلاً**، فتسويةُ ض.ق.م تشتقُّ ضريبتَه من الأستاذ نفسِه. وموضعُه بعد
    // `purchase_invoices` (طبقة ٣) التي يشير إليها.
    'purchase_returns',        // → purchase_invoices, parties, warehouses

    // ── Tier 6: الفئةُ التشغيليّة (v167 / المرحلة ٣) ──
    //
    // حالةُ تشغيلٍ لحظيّةٌ يقرؤها أكثرُ من جهازٍ في آنٍ واحد: طلبُ طاولةٍ
    // يُفتَح على نقطةٍ ويُغلَق من أخرى، وأمرُ تحضيرٍ يُطبَع في المطبخ
    // ويُنجَز من الكاشير، وحجزٌ يُؤخَذ على الاستقبال فلا تُباع الطاولةُ
    // مرّتين. والترتيبُ يتبع المفاتيحَ حرفاً — الأبُ قبل ابنه.
    //
    // ⚠️ و`employees` هنا وليست من الثمانيةَ عشر — نفسُ سابقةِ
    //    `bill_of_materials` في المرحلة ٢. خمسةٌ من جداول الفئة تشير
    //    إليها، وثلاثةٌ منها بإشارةٍ **غيرِ قابلةٍ للإفراغ**
    //    (`route_visits` · `sales_rep_targets` · `sales_rep_collections`).
    //    و`PRAGMA foreign_keys = ON` في الإنتاج، و`_upsertRow` **يبتلع**
    //    خطأَ المفتاح بـ`debugPrint` ويمضي — فبدونها كان كلُّ صفِّ زيارةٍ
    //    أو تحصيلٍ يُسقَط صامتاً ولا يظهر في أيّ اختبار.
    'employees',               // → branches
    'table_sections',
    'kitchen_stations',
    'restaurant_tables',       // → table_sections
    // v174 / قسمُ ٧ — معالمُ القاعة. **وموضعُها بعد `table_sections`
    // إلزاميٌ**: `section_id` مفتاحٌ خارجيٌّ إليه، و`_upsertRow` يبتلع
    // خطأَ المفتاح بـ`debugPrint` ويمضي — فجدارٌ يسبقُ قسمَه
    // يُسقَط صامتاً ولا يظهر في أيّ اختبار.
    'floor_plan_items',        // → table_sections
    'category_station_mappings', // → categories, kitchen_stations
    'booking_services',        // → products, branches
    'booking_resources',       // → employees, branches
    // v185 — المنطقةُ قبل المسار: `sales_routes.area_id` تشير إليها.
    'distribution_areas',      // → branches
    'sales_routes',            // → employees, distribution_areas
    'table_orders',            // → restaurant_tables, users
    'bookings',                // → parties, booking_services, booking_resources, sales_invoices
    'work_orders',             // → table_orders, sales_invoices, users
    'table_order_items',       // → table_orders, products
    'table_reservations',      // → restaurant_tables
    'table_order_payments',    // → table_orders, sales_invoices
    'work_order_items',        // → work_orders, products, users
    'booking_reminders',       // → bookings, users
    'route_visits',            // → sales_routes, parties, employees
    'sales_rep_targets',       // → employees
    'sales_rep_collections',   // → employees, parties
    // v185 — نموذجُ التوزيع (المرحلة و): أبناءُ المسار والمندوب.
    'route_customers',         // → sales_routes, parties
    'route_rep_history',       // → sales_routes, employees
    'rep_resources',           // → employees, warehouses, safes
    // v189 — مسوّداتُ المرتجعات (J2): بعد فواتير البيع والشراء والأطراف.
    'return_drafts',           // → sales/purchase_invoices, parties
    // v191 — ملفُّ الموظف (J4). القسمُ والمسمّى بلا مفاتيحَ خارجيّة
    // (‏`employees.department_id/job_title_id` أعمدةٌ خامّةٌ بلا قيد)،
    // والبدلاتُ والمستنداتُ والسجلُّ أبناءُ `employees` بعدها.
    'hr_departments',
    'hr_job_titles',
    'employee_allowances',     // → employees
    'employee_documents',      // → employees
    'employee_history',        // → employees
    // v192 — الورديّاتُ والحضورُ والإجازات (J4 الجزء ٢): الآباءُ أوّلاً.
    'hr_shifts',
    'hr_shift_assignments',    // → employees, hr_shifts
    'hr_public_holidays',
    'hr_leave_types',
    'hr_leave_requests',       // → employees, hr_leave_types
    'hr_leave_entitlements',   // → employees, hr_leave_types
    'hr_attendance_days',      // → employees

    // ── Tier 7: السجلُّ الرقابيُّ والتشغيلُ العابرُ للأجهزة (v173 / المرحلة ٤) ──
    //
    // ستّةٌ وعشرون جدولاً كان حكمُها في `sync_coverage_guard_test` 🔴:
    // إثباتٌ رقابيٌّ لا يُعاد بناؤه إن ضاع الجهاز (الفاتورةُ الإلكترونيّةُ
    // وسجلُّ الحقول والاعتمادُ وفصلُ المهامّ)، وحالةُ تشغيلٍ يقرؤها أكثرُ من
    // جهازٍ (الجردُ الدوريُّ وطلباتُ الصرف والولاءُ والمطابقةُ البنكيّة).
    // والترتيبُ يتبع المفاتيحَ حرفاً — الأبُ قبل ابنه.
    //
    // ⚠️ و`e_invoice_configs` **ليست هنا عمداً** — تحمل `client_secret`
    //    نصّاً؛ انظر حكمَها في `sync_coverage_guard_test`.
    //
    // ⚠️ **والمسارُ الواردُ وحدَه** كما في المرحلة ٣: لا نقطةَ نهايةٍ لدفع
    //    أيٍّ منها من العميل؛ ما يُكتَب على العميل يبقى عليه.
    'loyalty_programs',
    'delivery_companies',
    'sod_conflicts',
    'approval_workflows',
    'compliance_checks',
    'couriers',                  // → delivery_companies
    'approval_steps',            // → approval_workflows, roles, users
    'customer_loyalty_points',   // → parties, loyalty_programs
    'loyalty_transactions',      // → parties, loyalty_programs
    'warehouse_prices',          // → products, warehouses
    'cycle_count_plans',         // → warehouses, users
    'cycle_count_tasks',         // → cycle_count_plans, users
    'cycle_count_items',         // → cycle_count_tasks, products
    'stock_audits',              // → warehouses, users
    'stock_audit_items',         // → stock_audits, products
    'stock_requisitions',        // → branches, users
    'stock_requisition_items',   // → stock_requisitions, products, units
    'bank_reconciliations',      // → accounts
    'bank_statement_lines',      // → accounts
    'e_invoice_submissions',     // → sales_invoices
    'e_invoice_status_log',      // → e_invoice_submissions
    'field_audit_logs',          // → users
    'failed_autoposts',          // → users
    'approval_requests',         // → approval_workflows, users
    'approval_decisions',        // → approval_requests, approval_steps, users
    'sod_violations',            // → sod_conflicts, users, roles
    // v176 / §٨ — وصفُ المرفق وحدَه. والبايتاتُ (`attachment_blobs`)
    // **خارجَ هذه القائمة وكلِّ قائمةٍ سواها عمداً** — مُسلسِلُ
    // `_getSyncPull` يُسقط كلَّ `List<int>`، فإدخالُها ينفخ
    // حمولةَ السحب بلا أن يصل بايتٌ واحد.
    'attachments',               // → users
  ];

  /// Spec 151 P1-8b — the TRANSACTIONAL delta-pull tables (Tier 3 + Tier 4 +
  /// shift/audit movement tables). The server's `/api/sync/pull` denies every
  /// one of these to a caller with no `X-Session-Token` (see
  /// `_transactionalPullTables` in api_handler.dart — kept in sync with THIS
  /// set). A tokenless client (pre-login) therefore SKIPs them: pulling would
  /// return nothing AND — worse — seeding/advancing their watermark to "now"
  /// would make the post-login pull ask only for rows after now and silently
  /// drop the entire pre-login backlog (the reverted BLOCKER). Left unpulled
  /// and unseeded, DeltaPull backfills them from `since = null` (a full dump)
  /// once a token exists (post-login, scoped to the user's branch; a mirror
  /// mints an admin token at pairing → full). Master/reference tables are
  /// unaffected and provision normally tokenless.
  static const Set<String> branchScopedPullTables = {
    'sales_invoices', 'purchase_invoices', 'held_orders', 'sales_orders',
    'purchase_orders', 'quotations', 'payments', 'journal_entries',
    'safe_transactions', 'commercial_papers', 'stock_movements', 'shifts',
    'sales_invoice_items', 'purchase_invoice_items',
    // v184 — دفاترُ السندات: عهدةُ موظّفٍ وأرقامُ مستنداتٍ ماليّة.
    'voucher_books', 'voucher_book_leaves_cancelled',
    // v174 / المرحلة ٨ — **بياناتُ عملٍ لا مرجعيّة**: البيانُ
    // الجمركيُّ وبوليصةُ الشحن والاعتمادُ المستنديُّ أوراقُ صفقةٍ
    // لا تُسلَّم لمستدعٍ بلا هويّةٍ متحقَّقة — وهي فرعٌ من فاتورةٍ
    // محميّةٍ أصلاً فالتركُ خارجاً يُسرّب ما تحميه أمُّه.
    'import_purchase_details',
    'held_order_items', 'sales_order_items', 'purchase_order_items',
    'quotation_items', 'payment_allocations',
    // v166 / المرحلة ٢ — مستنداتُ الأثر المحاسبيّ. بياناتُ عملٍ لا
    // بياناتٌ مرجعيّة: سجلُّ أصولِ الشركة وتكاليفُها ومصروفاتُها لا
    // يُسلَّم لمستدعٍ بلا هويّةٍ متحقَّقة. والفئاتُ وقوائمُ المكوّنات
    // (`asset_categories` · `op_expense_categories` · `bill_of_materials`
    // · `bom_components`) مرجعيّةٌ عمداً فتبقى خارجَ هذه القائمة ليعمل
    // التزويدُ قبلَ الدخول.
    'landed_cost_sheets', 'landed_cost_items', 'landed_cost_allocations',
    'fixed_assets', 'asset_depreciations', 'op_expenses',
    'manufacturing_orders', 'mfg_order_costs',
     'butchery_orders', 'butchery_order_lines',
    // v175 / المرحلة ٧ — طلبُ استبعاد أصل. **بياناتُ عملٍ لا مرجعيّة**:
    // يحمل ثمنَ بيعٍ ومشترياً وسببَ استبعاد، فلا يُسلَّم لمستدعٍ بلا هويّةٍ
    // متحقَّقة. (وهو خلافُ `cheque_books` المرجعيّ في المرحلة ٦.)
    'asset_disposals',

    // v167 / المرحلة ٣ — الفئةُ التشغيليّة.
    //
    // 🔴 و`employees` هنا **لسببٍ أمنيٍّ لا لسببِ مفاتيح**: الجدولُ يحمل
    //    `salary` و`salary_type`. تركُه مرجعيّاً يعني تسليمَ رواتبِ
    //    الموظّفين إلى مستدعٍ **بلا هويّةٍ متحقَّقة** في التزويد قبل
    //    الدخول. والخمسةُ التي تشير إليه تتبعه هنا لا لتُحمى وحدَها بل
    //    ليصلَ الأبُ قبل أبنائه: مرجعيٌّ يُسحَب تokenless فيسبق أباه
    //    المحميَّ فيسقط مفتاحُه صامتاً.
    //
    // والمرجعيُّ عمداً — `table_sections` · `restaurant_tables` ·
    // **`floor_plan_items`** · `kitchen_stations` ·
    // `category_station_mappings` · `booking_services` — يبقى خارجَ هذه
    // القائمة ليعمل التزويدُ قبل الدخول: شاشةُ الطاولات تحتاج خريطةَ
    // الصالة قبلَ أوّلِ تسجيلِ دخول — **ومعالمُ القاعة هي الخريطة**
    // لا زينتُها: جدارٌ وبابٌ ومطبخٌ لا يحمل سرًّا تجاريّاً يُحمَى.
    'employees',
    'booking_resources',
    'table_orders', 'table_order_items', 'table_reservations',
    'table_order_payments',
    'work_orders', 'work_order_items',
    'bookings', 'booking_reminders',
    'sales_routes', 'route_visits', 'sales_rep_targets',
    'sales_rep_collections',
    // v185 — نموذجُ التوزيع: عملاءُ المسار ومندوبُه وعهدتُه بياناتُ عمل.
    'distribution_areas', 'route_customers', 'route_rep_history',
    'rep_resources',
    // v189 — مسوّداتُ المرتجعات (J2): بياناتُ عمل.
    'return_drafts',
    // v191 — ملفُّ الموظف (J4): رواتبُ وبدلاتٌ ومستنداتٌ شخصيّة — لا تُسلَّم
    // بلا هويّة، كأبيها `employees`.
    'hr_departments', 'hr_job_titles', 'employee_allowances',
    'employee_documents', 'employee_history',
    // v192 — الحضورُ والإجازاتُ والورديّات (J4 الجزء ٢): بياناتُ موظفين.
    'hr_shifts', 'hr_shift_assignments', 'hr_public_holidays',
    'hr_leave_types', 'hr_leave_requests', 'hr_leave_entitlements',
    'hr_attendance_days',

    // v173 / المرحلة ٤ — بياناتُ عملٍ لا تُسلَّم لمستدعٍ بلا هويّة: أرصدةُ
    // الولاء وحركاتُه، وأوراقُ الجرد وطلباتُ الصرف، والمطابقةُ البنكيّة
    // بأسطر كشفها، وتقديماتُ الفاتورة الإلكترونيّة وسجلُّها، وسجلُّ الحقول
    // وفشلُ الترحيل، وطلباتُ الاعتماد وقراراتُه، وانتهاكاتُ فصل المهامّ،
    // وفحوصُ الامتثال.
    //
    // والمرجعيُّ عمداً — `loyalty_programs` · `delivery_companies` ·
    // `couriers` · `warehouse_prices` · `approval_workflows` ·
    // `approval_steps` · `sod_conflicts` — خارجَ القائمة ليعمل التزويدُ
    // قبل الدخول (سعرُ المخزن يسبق أوّلَ بيع، وسيرُ الاعتماد يسبق أوّلَ طلب).
    'customer_loyalty_points', 'loyalty_transactions',
    'cycle_count_plans', 'cycle_count_tasks', 'cycle_count_items',
    'stock_audits', 'stock_audit_items',
    'stock_requisitions', 'stock_requisition_items',
    'bank_reconciliations', 'bank_statement_lines',
    'e_invoice_submissions', 'e_invoice_status_log',
    'field_audit_logs', 'failed_autoposts',
    'approval_requests', 'approval_decisions',
    'sod_violations', 'compliance_checks',
    // v176 / §٨ — **بياناتُ عملٍ لا مرجعيّة**: وصفُ المرفق يحمل
    // اسمَ ملفٍّ وملاحظةً على فاتورةٍ أو قيدٍ — وهو فرعٌ من مستندٍ
    // محميٍّ أصلاً، فالتركُ خارجاً يُسرِّب ما تحميه أمُّه.
    'attachments',
  };

  /// المرحلة ١ (W1) — الجداول الأساسية التي صار الخادم يقصّها على الفرع
  /// (`api_handler._syncPullBranchColumn` + الاشتقاق العكسي لمراكز
  /// التكلفة).
  ///
  /// **منفصلة عمداً عن [branchScopedPullTables]،** فتلك تصف عقداً آخر —
  /// قائمة منع الـtokenless التعاملية، ويثبّتها اختبار تساوٍ صارم مع
  /// نظيرتها على الخادم. خلط المجموعتين يكسر ذلك العقد.
  ///
  /// الفرق في الأثر: الجداول التعاملية **تُتخطّى** كلياً قبل الدخول،
  /// أما هذه فتُسحَب عادياً — التزويد يعتمد عليها — ويُمنع فقط **تقديم
  /// الـwatermark**. لولا ذلك: الخادم يقصّ الرد على سنتينل `-1` للمستدعي
  /// بلا هوية، والعميل يحفظ watermark على رد مقصوص، فيسأل بعد الدخول
  /// عمّا هو أحدث منه فقط وتضيع الصفوف الأقدم نهائياً. وهذا يتكرر عند
  /// **كل إقلاع**، لا عند التزويد الأوّلي فحسب.
  ///
  /// المراجعة النهائية / FR-6 — الخادم بقى يُعيد هذه الجداول **كاملة**
  /// للمستدعي بلا هوية (قرار المالك: البيانات الأساسية تظل كاملة بلا توكن)،
  /// فالرد المقصوص الموصوف أعلاه لم يعد يحدث والحجب لم يعد خط الدفاع
  /// الوحيد. يبقى كحزام فوق حمّالة: كلفته سحبٌ كامل إضافي واحد بعد الدخول،
  /// ومقابله أن أي تشديد مستقبلي على مسار انعدام الهوية لا يُعيد فتح تسميم
  /// العلامة المائية من تلقاء نفسه. اختبارات قائمة تثبّت السلوك — لا تُزِله
  /// بحجة أنه صار زائداً.
  /// جداولُ **الدلتا وحدَها** — لا استراتيجيّةَ لها في
  /// [SyncService.fullSync]، فالإقلاعُ الأوّلُ لا يملؤها.
  ///
  /// ⚠️ **ولذلك لا تُبذَر علامتُها المائيّة أبداً.** [seedWatermarks] يبذر
  /// بحجّةِ أنّ `fullSync` نزّل الجدولَ للتوّ؛ وهي حجّةٌ باطلةٌ هنا. علامةٌ
  /// مبذورةٌ على جدولٍ لم يُملأ تعني أنّ السحبَ التالي يطلب ما تغيّر **بعد**
  /// تلك اللحظة، فكلُّ صفٍّ أقدمَ منها يُتخطّى ولا يُطلَب ثانيةً — نفسُ
  /// «تسميم العلامة» الذي يحذّر منه [branchScopedPullTables] أعلاه، لكن
  /// من بابٍ آخر: ذاك سببُه ردٌّ مقصوص، وهذا سببُه بذرٌ بلا تنزيل.
  ///
  /// وتركُها بلا بذرٍ يعني `since = null` في أوّل سحبِ دلتا = تفريغٌ كامل —
  /// وهو بالضبط ما كانت `fullSync` ستفعله لو كانت لها استراتيجيّة.
  ///
  /// v166 / المرحلة ٢ — مستنداتُ الأثر المحاسبيّ. صارت مُصلَّبةً للمزامنة
  /// (‏`global_id` + أعمدةُ الدلتا الأربعة) فمكانُها مسارُ الدلتا لا مسارُ
  /// الاستراتيجيّات — وذاك شبكةُ أمانٍ للجداول **غيرِ** المصلَّبة، كما يقول
  /// تعليقُ المؤقّت الدوريّ في `main_desktop.dart`.
  static const Set<String> deltaOnlyTables = {
    // v176 / 2026-09-21 — الإضافاتُ والخيارات. لا استراتيجيّةَ لها في
    // `fullSync`، فبذرُ علامتها يعني أنّ السحبَ التالي يطلب ما بعدَ لحظةِ
    // البذر — وكلُّ مجموعةٍ عُرِّفت قبلها **لا تصل الجهازَ أبداً** بلا خطأٍ
    // ولا سجلّ. أمسكه `delta_only_watermark_guard` عند التوصيل.
    'modifier_groups', 'modifier_items', 'product_modifier_groups',

    // v184 — دفاترُ السندات: لا استراتيجيّةَ لها في `fullSync`.
    'voucher_books', 'voucher_book_leaves_cancelled',

    'asset_categories', 'op_expense_categories', 'bill_of_materials',
    'fixed_assets', 'manufacturing_orders', 'bom_components',
     'butchery_templates', 'butchery_template_lines', 'butchery_orders', 'butchery_order_lines',
    'op_expenses', 'asset_depreciations', 'mfg_order_costs',
    'landed_cost_sheets', 'landed_cost_items', 'landed_cost_allocations',

    // v167 / المرحلة ٣ — الفئةُ التشغيليّة. التسعةَ عشرَ كلُّها بلا
    // استراتيجيّةٍ في `fullSync`، فبذرُ علامتِها المائيّة يعني عميلاً لا
    // يرى **طلبَ طاولةٍ أو حجزاً سابقاً لإقلاعه أبداً** — ولا يظهر ذلك
    // في أيّ اختبار: الجدولُ يمتلئ بما يقع بعد الإقلاع فيبدو عاملاً.
    'employees',
    'table_sections', 'restaurant_tables', 'floor_plan_items',
    'table_orders',
    'table_order_items', 'table_reservations', 'table_order_payments',
    'kitchen_stations', 'category_station_mappings',
    'work_orders', 'work_order_items',
    'booking_resources', 'booking_services', 'bookings', 'booking_reminders',
    'sales_routes', 'route_visits', 'sales_rep_targets',
    'sales_rep_collections',
    // v185 — نموذجُ التوزيع: لا استراتيجيّةَ لها في `fullSync`.
    'distribution_areas', 'route_customers', 'route_rep_history',
    'rep_resources',
    // v189 — مسوّداتُ المرتجعات (J2): لا استراتيجيّةَ لها في `fullSync`.
    'return_drafts',
    // v191 — ملفُّ الموظف (J4): لا استراتيجيّةَ لها في `fullSync`.
    'hr_departments', 'hr_job_titles', 'employee_allowances',
    'employee_documents', 'employee_history',
    // v192 — الحضورُ والإجازات (J4 الجزء ٢): لا استراتيجيّةَ لها في `fullSync`.
    'hr_shifts', 'hr_shift_assignments', 'hr_public_holidays',
    'hr_leave_types', 'hr_leave_requests', 'hr_leave_entitlements',
    'hr_attendance_days',

    // ── البند ٦‑٤ (2026-08-31) — ستّةٌ كانت **مبذورةً بلا تنزيل** ────────
    //
    // نفسُ العطب حرفاً، وقد أُغلق مرّتَين قبلَه (v166 وv167) ثمّ انفتح
    // ثالثةً لأنّ الحارسَ **أحاديُّ الاتّجاه**: يفحص أنّ كلَّ اسمٍ هنا
    // موجودٌ في `pullTables`، وأنّ لا جدولَ ذا استراتيجيّةٍ هنا — ولا
    // يفحص العكسَ («بلا استراتيجيّةٍ ⇒ يجب أن يكون هنا»)، وهو عينُ
    // الثقب. أُضيف الاتّجاهُ الثالث في `delta_only_watermark_guard_test`.
    //
    // والأثرُ مقيس: صفرُ استراتيجيّاتٍ تكتب أيّاً منها، و`seedWatermarks`
    // يختمها كلَّها بعد `fullSync` — فيسأل العميلُ عمّا بعد لحظةِ انضمامه
    // ولا يرى **قائمةَ أسعارٍ ولا مجموعةَ أطرافٍ ولا عرضَ سعرٍ سابقاً
    // أبداً**. والخادمُ يقارن بـ`>` صارمة فلا مسارَ تعافٍ تلقائيّ.
    'currencies', 'party_groups', 'price_lists', 'price_list_items',
    'quotations', 'quotation_items',

    // §٦‑٢ (v172) — `purchase_returns` بلا استراتيجيّةٍ في `fullSync` عمداً:
    // جدولٌ مصلَّبٌ للمزامنة (‏`global_id` + أعمدةُ الدلتا) فمكانُه مسارُ
    // الدلتا. وبذرُ علامتِه المائيّة بلا تنزيلٍ كان سيعني عميلاً **لا يرى
    // مرتجعَ شراءٍ سابقاً لإقلاعه أبداً** — فتظهر تسويةُ ض.ق.م عنده فرقاً
    // دائماً على بياناتٍ سليمة.
    'purchase_returns',

    // v173 / المرحلة ٤ — الستّةُ والعشرون كلُّها بلا استراتيجيّةٍ في
    // `fullSync`، فمكانُها مسارُ الدلتا وبذرُ علامتِها المائيّة يعني عميلاً
    // لا يرى مطابقةً بنكيّةً ولا طلبَ اعتمادٍ سابقاً لإقلاعه أبداً.
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

    // v175 / المرحلة ٧ — طلبُ استبعاد أصل. بلا استراتيجيّةٍ في `fullSync`،
    // فبذرُ علامتِه يعني جهازاً ثانياً لا يرى طلباً حُرِّر قبل إقلاعه — وهو
    // مستندٌ يُراجَع ويُعتمَد من جهازٍ غيرِ الذي حرّره.
    'asset_disposals',

    // v174 / المرحلة ٨ — وسمُ الاستيراد. بلا استراتيجيّةٍ في `fullSync`،
    // فبذرُ علامتِه يعني جهازاً ثانياً يرى فاتورةَ الاستيراد **بلا وسمها**:
    // تُعرَض محلّيّةً وتغيب عن شاشتها، ولا شيءَ يقول إنّ الوسمَ لم يصل.
    'import_purchase_details',

    // v175 / المرحلة ٦ — دفترُ الشيكات. بلا استراتيجيّةٍ في `fullSync`،
    // فبذرُ علامتِه يعني جهازاً ثانياً **لا يرى دفتراً فُتح قبل إقلاعه** —
    // فيفتح دفتراً بنفس المدى ويُصدِر شيكَين بنفس الرقم إلى البنك.
    'cheque_books',

    // ⚠️ **`printers` و`activity_logs` مستثنيان عن قصدٍ — قرارٌ لا سهو.**
    //   • `printers` يخلط إعداداً **جهازيّاً** (‏`port` = COM3) بإعدادٍ
    //     مشترَك (‏`ip_address` لطابعة الشبكة). و`_upsertRow` يستعمل
    //     `INSERT OR REPLACE`، ففتحُ سحبِه يدهس منفذَ طابعةِ كلِّ جهازٍ
    //     بمنفذِ الخادم — سدُّ ثقبٍ يفتح عطباً مرئيّاً.
    //   • `activity_logs` سجلٌّ إلحاقيٌّ بلا سقفٍ زمنيّ؛ `since = null`
    //     على متجرٍ بسنةِ تاريخٍ قد يتجاوز سقفَ الصفحات (٢٠٠×٥٠٠) فيبقى
    //     معلَّقاً بلا تقديمِ علامة.
    // كلاهما يبقى مختوماً كما هو اليوم — أي **لا انحدار**، ولا ادّعاءَ
    // إغلاق. يُحسمان بقرارِ مالكٍ في بندٍ مستقلّ.

    // v176 / §٨ — المرفقات. بلا استراتيجيّةٍ في `fullSync`، فبذرُ
    // علامتِها يعني جهازاً ثانياً **لا يرى ورقةً أُرفقت قبل
    // إقلاعِه أبداً** — والمراجِعُ يفتح الفاتورةَ فيراها بلا
    // بيانِها الجمركيّ فيظنُّ أنَّ أحداً لم يُرفِقه.
    'attachments',
  };

  static const Set<String> branchScopedMasterPullTables = {
    'branches', 'warehouses', 'safes', 'cost_centers',
  };

  /// Single source of truth for the watermark guard's decision (used by
  /// [pullTable] below). Extracted so a test can pin the actual *behaviour* —
  /// not just the contents of the two sets it reads — without mocking the
  /// whole pull. A tokenless caller must withhold the watermark for both the
  /// transactional denylist AND the branch-scoped master tables (W1); a
  /// caller with a token, or a table in neither set, never withholds.
  @visibleForTesting
  static bool shouldWithholdWatermark(String table,
          {required bool hasSessionToken}) =>
      !hasSessionToken &&
      (branchScopedPullTables.contains(table) ||
          branchScopedMasterPullTables.contains(table));

  void initialize(AppDatabase db) {
    _db = db;
    _blobSchema = null;
    ConflictResolutionService.instance.initialize(db);
  }

  /// خريطةُ «الأعمدةُ الّتي لا يقدر الخادمُ على إرسالها» — مُشتقّةٌ من مخطَّط
  /// drift نفسِه، لا مكتوبةٌ بيد. انظر [_preserveUnsendableBlobs].
  Map<String, _BlobTableSchema>? _blobSchema;

  Map<String, _BlobTableSchema> get _blobSchemaOfDb {
    final cached = _blobSchema;
    if (cached != null) return cached;
    final built = <String, _BlobTableSchema>{};
    for (final t in _db!.allTables) {
      final blobs = <String>[
        for (final c in t.$columns)
          if (c.type == DriftSqlType.blob) c.name,
      ];
      if (blobs.isEmpty) continue;
      built[t.actualTableName] = _BlobTableSchema(
        blobColumns: blobs,
        hasGlobalId: t.$columns.any((c) => c.name == 'global_id'),
      );
    }
    return _blobSchema = built;
  }

  /// Test-only entry to the otherwise-private inbound upsert path, so an
  /// integration test can exercise DeltaPull row handling (notably the
  /// server→local party-FK remap) without standing up a server / ServerProxy.
  /// Production code never calls this — use [pullTable] / [pullAll].
  @visibleForTesting
  Future<void> upsertRowForTest(String table, Map<String, dynamic> row) =>
      _upsertRow(table, row);

  /// Pull all [pullTables] sequentially. No-op if already pulling.
  Future<void> pullAll() async {
    if (_isPulling || _db == null) return;
    _isPulling = true;
    SyncEventBus.instance.isPulling.value = true;
    SyncEventBus.instance.emit(const SyncPullStarted());
    int totalRows = 0;
    try {
      for (final table in pullTables) {
        totalRows += await pullTable(table);
      }
    } finally {
      _isPulling = false;
      SyncEventBus.instance.isPulling.value = false;
      SyncEventBus.instance.emit(SyncPullCompleted(totalRows));
    }
  }

  /// Pull a specific list of tables sequentially.
  /// Used by shift-close pre-flight to sync the tables that affect
  /// closing aggregates before the report is calculated.
  Future<void> pullMultiple(List<String> tables) async {
    for (final table in tables) {
      await pullTable(table);
    }
  }

  /// Pull a single table. Returns the number of rows applied.
  /// Safe to call directly (e.g. from WebSocket data_changed).
  Future<int> pullTable(String table) async {
    // Spec 151 P1-8b — a branch-scoped transactional table can't be pulled
    // without a session token: the server fail-closes it to zero rows. Skip
    // it entirely (do NOT fetch, do NOT advance its watermark) until a token
    // exists post-login, so DeltaPull backfills the full backlog then.
    if (branchScopedPullTables.contains(table) &&
        !ServerProxy.instance.hasSessionToken()) {
      debugPrint('[DeltaPull] $table skipped — no session token '
          '(branch-scoped; will backfill after login)');
      return 0;
    }
    try {
      final since = await _loadWatermark(table);

      // ── Paged drain ─────────────────────────────────────────────────────
      // The server now bounds every /api/sync/pull response (it used to
      // return the whole table, which froze both ends). Loop pages with a
      // keyset cursor and only advance the watermark AFTER the last page
      // lands — if the loop is interrupted the watermark stays put and the
      // next pull safely re-fetches from the same point (upserts are
      // idempotent).
      var totalApplied = 0;
      int? cursorTs;
      int? cursorId;
      int? serverTime;
      var pages = 0;
      // Only a loop that reached the server's last page may advance the
      // watermark. Any other exit — page cap, network failure, or a row we
      // cannot build a cursor from — must leave it untouched, or the rows we
      // never fetched would be skipped forever.
      var drainedFully = false;

      while (true) {
        if (pages >= _maxPagesPerPull) {
          // Leave the watermark unadvanced so the remainder is picked up on
          // the next cycle rather than silently dropped.
          debugPrint('[DeltaPull] $table: hit page cap ($_maxPagesPerPull) — '
              'remainder deferred to next pull');
          unawaited(DiagnosticLogger.log(
            'DELTA-PULL-CAP',
            'table=$table pages=$pages applied=$totalApplied '
                '— watermark NOT advanced, remainder deferred',
          ));
          return totalApplied;
        }
        pages++;

        final result = await ServerProxy.instance.fetchDelta(
          table,
          since: since,
          limit: _pullPageSize,
          cursorTs: cursorTs,
          cursorId: cursorId,
        );
        // Network/HTTP failure — do NOT advance the watermark.
        if (result == null) return totalApplied;

        final rows =
            (result['rows'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        // Take the clock from the FIRST page. Rows modified while we page
        // through are then re-fetched next cycle instead of being skipped.
        serverTime ??= result['serverTime'] as int?;

        if (rows.isNotEmpty) {
          await _applyRowsChunked(table, rows);
          totalApplied += rows.length;

          // Notify Drift watch() streams so reactive queries re-fire
          // automatically.
          _db!.notifyUpdates({
            TableUpdate(table, kind: UpdateKind.insert),
            TableUpdate(table, kind: UpdateKind.update),
          });
          // Broadcast to SyncEventBus for higher-level UI subscribers
          SyncEventBus.instance.emit(SyncTablePulled(table, rows.length));
          debugPrint('[DeltaPull] $table: applied ${rows.length} rows '
              '(page $pages)');

          // Defensive numeric reads: the wire type varies by server backend
          // (SQLite hands back an int, Postgres can surface a num), and a hard
          // `as int` cast on the wrong one would throw mid-drain.
          final last = rows.last;
          cursorTs = _asInt(last['last_modified_at']) ?? 0;
          cursorId = _asInt(last['id']);
        }

        final hasMore = result['hasMore'] == true;
        if (!hasMore || rows.isEmpty) {
          drainedFully = true;
          break;
        }
        if (cursorId == null) {
          // The server says there is more, but the last row carries no usable
          // id, so the next page cannot be addressed. Stop WITHOUT advancing
          // the watermark so nothing is silently dropped.
          debugPrint('[DeltaPull] $table: hasMore but no cursor id — '
              'watermark NOT advanced');
          unawaited(DiagnosticLogger.log(
            'DELTA-PULL-CURSOR',
            'table=$table hasMore=true but last row had no int id — '
                'watermark NOT advanced, remainder deferred',
          ));
          break;
        }
      }

      if (serverTime != null && drainedFully) {
        // Spec 151 P1-8b watermark guard (defense-in-depth). The early skip
        // above already prevents a branch-scoped tokenless pull from reaching
        // here, but re-check so a future caller that bypasses the skip can
        // never advance a branch-scoped table's watermark on a tokenless pull
        // (which returned zero rows) and strand its backlog.
        //
        // المرحلة ١ (W1) — وُسِّع ليشمل الجداول الأساسية المحصورة. تلك
        // لا تُتخطّى مبكراً (التزويد يحتاجها)، فهذا الحارس هو دفاعها
        // **الوحيد**: بلا هوية يقصّها الخادم على سنتينل `-1`، فحفظ
        // watermark على ذلك الرد يُسقِط الصفوف الأقدم نهائياً.
        //
        // القرار نفسه مُستخرَج في [shouldWithholdWatermark] — تعبير واحد
        // فقط عن القاعدة، ومختبَر مباشرة بدل تخمينه من محتوى المجموعتين.
        final withhold = shouldWithholdWatermark(table,
            hasSessionToken: ServerProxy.instance.hasSessionToken());
        if (!withhold) {
          await _saveWatermark(table, serverTime);
        }
      }
      return totalApplied;
    } catch (e) {
      debugPrint('[DeltaPull] $table error: $e');
      return 0;
    }
  }

  /// Lenient int read for wire values that may arrive as `int`, `num` or a
  /// numeric `String` depending on the server's database backend.
  static int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  /// Rows requested per `/api/sync/pull` page.
  static const int _pullPageSize = 500;

  /// Rows applied per local write transaction. The whole page used to land in
  /// ONE `transaction()`, so a large pull held a write lock and blocked the
  /// UI isolate for the entire batch — the visible "client freeze". Chunking
  /// plus an event-loop yield between chunks keeps the app responsive while a
  /// backlog drains.
  static const int _applyChunkSize = 100;

  /// Safety valve on the paging loop so a server that always answers
  /// `hasMore: true` (bad clock, cursor bug) cannot spin forever. At the
  /// default page size this still drains 100k rows per pull.
  static const int _maxPagesPerPull = 200;

  /// Apply [rows] in bounded transactions, yielding to the event loop between
  /// chunks so Drift stream listeners and the UI get a turn.
  Future<void> _applyRowsChunked(
    String table,
    List<Map<String, dynamic>> rows,
  ) async {
    for (var start = 0; start < rows.length; start += _applyChunkSize) {
      final end = (start + _applyChunkSize) > rows.length
          ? rows.length
          : start + _applyChunkSize;
      final chunk = rows.sublist(start, end);
      await _db!.transaction(() async {
        for (final row in chunk) {
          await _upsertRow(table, row);
        }
      });
      // Hand the event loop back between chunks.
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<SyncOutboxItem?> _pendingOutboxForRow(
    String table,
    int? localId,
    String? globalId,
  ) async {
    if (_db == null) return null;
    final candidates = await (_db!.select(_db!.syncOutbox)
          ..where((item) => item.targetTable.equals(table)))
        .get();
    for (final item in candidates) {
      if (item.status == 'synced') continue;
      if (localId != null && item.recordId == localId.toString()) return item;
      if (globalId != null && globalId.isNotEmpty && item.payload.contains(globalId)) {
        return item;
      }
    }
    return null;
  }

  Future<void> _recordFinancialPendingConflict({
    required String table,
    required Map<String, dynamic> serverRow,
    required SyncOutboxItem pending,
  }) async {
    final recordId = serverRow['id']?.toString() ?? pending.recordId;
    try {
      await _db!.into(_db!.syncConflictLog).insert(
        SyncConflictLogCompanion.insert(
          conflictTable: table,
          recordId: recordId,
          resolution: 'pending_review',
          clientPayload: pending.payload,
          serverPayload: Value(jsonEncode(serverRow)),
          reason: const Value(
            'Financial row has a pending local change; server version withheld for review',
          ),
          clientId: const Value(null),
        ),
      );
      await DiagnosticLogger.log(
        'SYNC-CONFLICT',
        'financial conflict pending review table=$table record=$recordId',
      );
    } catch (error, stack) {
      await DiagnosticLogger.logError(
        'SYNC-CONFLICT',
        'financial conflict record failed for $table/$recordId',
        error,
        stack,
      );
    }
  }

  Future<void> _resignInvoiceRow(String table, int? localId) async {
    if (localId == null) return;
    if (table == 'sales_invoices') {
      await _db!.resignSalesInvoice(localId);
    } else if (table == 'purchase_invoices') {
      await _db!.resignPurchaseInvoice(localId);
    }
  }

  Future<void> _upsertRow(String table, Map<String, dynamic> row) async {
    // Feature 006 / MM.E hot-fix: journal_entries arrives with its child
    // lines embedded under `lines`. Pop them out BEFORE the generic
    // INSERT OR REPLACE so the column list doesn't see a non-column key,
    // then replay them into journal_entry_lines after the header lands.
    // journal_entry_lines has no last_modified_at column of its own and
    // can't ride the generic delta-pull path — without this, the GL
    // screen on mirror / client showed entry headers with empty
    // debit/credit columns.
    final List? embeddedJournalLines =
        (table == 'journal_entries' && row['lines'] is List)
            ? row.remove('lines') as List
            : null;

    final serverId = row['id'] is int ? row['id'] as int : null;
    final globalId = row['global_id'] is String ? row['global_id'] as String : null;

    // Resolve the local id for this server row. For master tables the client
    // adopts the server id directly (local_id == server_id). For rows this
    // client originally created offline, the outbox replay assigned a server
    // id that differs from the local id — we must find the local row via its
    // stable UUID (`global_id`) so that dependent FKs remain intact.
    int? localId = serverId;
    bool foundByGlobalId = false;
    if (globalId != null && globalId.isNotEmpty && serverId != null) {
      try {
        final existing = await _db!.customSelect(
          'SELECT id FROM $table WHERE global_id = ? LIMIT 1',
          variables: [Variable.withString(globalId)],
        ).getSingleOrNull();
        final existingLocalId = existing?.read<int?>('id');
        if (existingLocalId != null) {
          foundByGlobalId = true;
          if (existingLocalId != serverId) {
            localId = existingLocalId;
            // Persist the mapping so FK references in outbox payloads resolve
            // consistently on the next replay.
            await _db!.storeFkMapping(
              tableName: table,
              localId: existingLocalId,
              remoteId: serverId,
              globalId: globalId,
            );
          }
        }
      } catch (e) {
        // Table may not carry `global_id`, or query may fail for other
        // reasons — fall back to id-based upsert below.
        debugPrint('[DeltaPull] global_id lookup $table failed (will fall back): $e');
      }
    }

    // ── Natural-key fallback ───────────────────────────────────────────
    // When a server row's globalId doesn't match any local row, the next
    // line would INSERT OR REPLACE by id — creating a duplicate if the
    // client already has a row with the same natural key (code/barcode
    // for products, phone+name for parties, name for branches/warehouses)
    // but a NULL or different globalId. That duplicate is the root cause
    // of the 3× كيلو ريش bug (and, for branches/warehouses, of BUG 5b's
    // duplicate "الفرع الرئيسي"/"المخزن الرئيسي"). Resolve by adopting
    // the server's globalId onto the existing local row so the
    // subsequent UPDATE merges cleanly.
    if (!foundByGlobalId && serverId != null && globalId != null && globalId.isNotEmpty) {
      try {
        int? naturalLocalId;
        if (table == 'products') {
          final code = row['code'] is String ? row['code'] as String : null;
          final barcode = row['barcode'] is String ? row['barcode'] as String : null;
          if (code != null && code.trim().isNotEmpty) {
            final hit = await _db!.customSelect(
              'SELECT id FROM products WHERE code = ? LIMIT 1',
              variables: [Variable.withString(code.trim())],
            ).getSingleOrNull();
            naturalLocalId = hit?.read<int?>('id');
          }
          if (naturalLocalId == null && barcode != null && barcode.trim().isNotEmpty) {
            final hit = await _db!.customSelect(
              'SELECT id FROM products WHERE barcode = ? LIMIT 1',
              variables: [Variable.withString(barcode.trim())],
            ).getSingleOrNull();
            naturalLocalId = hit?.read<int?>('id');
          }
        } else if (table == 'parties') {
          final code = row['code'] is String ? row['code'] as String : null;
          final name = row['name'] is String ? row['name'] as String : null;
          final phone = row['phone'] is String ? row['phone'] as String : null;
          if (code != null && code.trim().isNotEmpty) {
            final hit = await _db!.customSelect(
              'SELECT id FROM parties WHERE code = ? LIMIT 1',
              variables: [Variable.withString(code.trim())],
            ).getSingleOrNull();
            naturalLocalId = hit?.read<int?>('id');
          }
          if (naturalLocalId == null &&
              name != null && name.trim().isNotEmpty &&
              phone != null && phone.trim().isNotEmpty) {
            final hit = await _db!.customSelect(
              'SELECT id FROM parties WHERE name = ? AND phone = ? LIMIT 1',
              variables: [Variable.withString(name.trim()), Variable.withString(phone.trim())],
            ).getSingleOrNull();
            naturalLocalId = hit?.read<int?>('id');
          }
        } else if (table == 'branches') {
          // Spec 150 / BUG 5b — branches have no code/barcode, so the
          // (trimmed) name is the only natural key. Without this arm a
          // server-origin "الفرع الرئيسي" with a non-deterministic
          // globalId falls straight through to INSERT OR REPLACE and
          // duplicates the locally-seeded row of the same name.
          final name = row['name'] is String ? row['name'] as String : null;
          if (name != null && name.trim().isNotEmpty) {
            final hit = await _db!.customSelect(
              'SELECT id FROM branches WHERE name = ? LIMIT 1',
              variables: [Variable.withString(name.trim())],
            ).getSingleOrNull();
            naturalLocalId = hit?.read<int?>('id');
          }
        } else if (table == 'warehouses') {
          // Spec 150 / BUG 5b — same natural-key gap as branches, for
          // "المخزن الرئيسي".
          final name = row['name'] is String ? row['name'] as String : null;
          if (name != null && name.trim().isNotEmpty) {
            final hit = await _db!.customSelect(
              'SELECT id FROM warehouses WHERE name = ? LIMIT 1',
              variables: [Variable.withString(name.trim())],
            ).getSingleOrNull();
            naturalLocalId = hit?.read<int?>('id');
          }
        }
        if (naturalLocalId != null) {
          // Adopt the server's globalId onto this local row, then treat
          // it as the target of the upsert.
          await _db!.customStatement(
            'UPDATE $table SET global_id = ? WHERE id = ?',
            [globalId, naturalLocalId],
          );
          localId = naturalLocalId;
          await _db!.storeFkMapping(
            tableName: table,
            localId: naturalLocalId,
            remoteId: serverId,
            globalId: globalId,
          );
          debugPrint('[DeltaPull] natural-key merge $table: '
              'adopted globalId=$globalId onto localId=$naturalLocalId '
              '(serverId=$serverId) — prevented duplicate insert.');
        }
      } catch (e) {
        debugPrint('[DeltaPull] natural-key fallback $table failed: $e');
      }
    }

    // A pending local financial mutation is a reviewable conflict. Keep the
    // local row intact for every server change, including soft-deletes.
    if (kFinancialSyncTables.contains(table)) {
      final pending = await _pendingOutboxForRow(table, localId, globalId);
      if (pending != null) {
        await _recordFinancialPendingConflict(
          table: table,
          serverRow: row,
          pending: pending,
        );
        return;
      }
    }

    // Conflict check must precede soft-delete. A local unsynced financial edit
    // must not be erased merely because the server row carries deleted_at.
    // C-04: resolve the per-table policy instead of the blanket newerWins
    // default — server is SoT on client/mirror (R4), so server-authoritative
    // rows must serverWins-heal past a locally-bumped row_version.
    final apply = await ConflictResolutionService.instance.shouldApplyServerRow(
      table,
      row,
      policy: ConflictResolutionService.instance.policyForTable(table),
    );
    if (!apply) return;

    // Soft-delete: server marks rows with deleted_at instead of hard-deleting.
    if (row['deleted_at'] != null) {
      try {
        await _db!.customStatement(
          'UPDATE $table SET deleted_at = ? WHERE id = ?',
          [row['deleted_at'], localId],
        );
      } catch (error, stack) {
        await DiagnosticLogger.logError(
          'SYNC-PULL',
          'soft-delete apply failed for $table id=$localId',
          error,
          stack,
        );
      }
      return;
    }

    // Spec 136 (field 2026-06-14): remap server party FK → LOCAL party id on the
    // mirror's REAL inbound path. The SyncStrategy-layer party remap
    // (purchase/safe_transaction strategies) is DEAD CODE for client/mirror —
    // Tier-3 strategies are skipped and DeltaPull is the path that actually
    // runs. Writing the server's customer_id/supplier_id/party_id raw made
    // getPartyStatement (filters by LOCAL partyId) return nothing → supplier &
    // customer statements empty on the mirror, and clobbered the cwi_commerce
    // local cash-receipt cache row's local partyId on the server echo. Resolve
    // via the parties FK mappings DeltaPull already records (storeFkMapping,
    // ~line 197/269). Falls through unchanged when the party kept the server id.
    const partyFkByTable = {
      'sales_invoices': 'customer_id',
      'purchase_invoices': 'supplier_id',
      'safe_transactions': 'party_id',
    };
    final partyFkCol = partyFkByTable[table];
    if (partyFkCol != null && row[partyFkCol] is int) {
      final serverPartyId = row[partyFkCol] as int;
      final directHit = await _db!.customSelect(
        'SELECT 1 FROM parties WHERE id = ? LIMIT 1',
        variables: [Variable.withInt(serverPartyId)],
      ).getSingleOrNull();
      if (directHit == null) {
        final mapped = await _db!.customSelect(
          "SELECT local_id FROM remote_id_mappings "
          "WHERE table_name = 'parties' AND remote_id = ? LIMIT 1",
          variables: [Variable.withInt(serverPartyId)],
        ).getSingleOrNull();
        final localPartyId = mapped?.read<int?>('local_id');
        if (localPartyId != null && localPartyId != serverPartyId) {
          row = Map.of(row);
          row[partyFkCol] = localPartyId;
          debugPrint('[DeltaPull] $table.$partyFkCol remap server '
              '$serverPartyId → local $localPartyId');
        } else {
          unawaited(DiagnosticLogger.log(
            'SYNC-WARN',
            '$table $partyFkCol=$serverPartyId pulled with no local party '
            'mapping — statement for this party may be incomplete until its '
            'parties row syncs (DeltaPull party-FK remap).',
          ));
        }
      }
    }

    await _preserveUnsendableBlobs(
      table,
      row,
      localId: localId,
      serverId: serverId,
      globalId: globalId,
      onPatched: (patched) => row = patched,
    );

    // If the local row exists with a different id (client-originated record
    // that now carries a server id), UPDATE in place — preserving the local
    // primary key and all FK references to it.
    if (localId != null && serverId != null && localId != serverId) {
      final updateCols = row.keys.where((k) => k != 'id').toList();
      if (updateCols.isEmpty) return;
      final setClause = updateCols.map((c) => '$c = ?').join(', ');
      final values = updateCols.map((c) => row[c]).toList()..add(localId);
      var applied = false;
      try {
        await _db!.customStatement(
          'UPDATE $table SET $setClause WHERE id = ?',
          values,
        );
        applied = true;
      } catch (e) {
        debugPrint('[DeltaPull] in-place update $table local=$localId server=$serverId: $e');
      }
      if (applied) await _resignInvoiceRow(table, localId);
      return;
    }

    // Collision guard — server's numeric id is already occupied locally
    // by a row with a different global_id. Blindly INSERT OR REPLACE would
    // overwrite the user's own offline-created row (the exact symptom the
    // user reported as "لا يرضى يرحل بياناتهم" / "I can't change the id").
    // Renumber the local row into the safe >=1B range, cascading every FK
    // reference, then let the server row take its natural id.
    if (serverId != null) {
      try {
        final collision = await _db!.customSelect(
          'SELECT global_id FROM "$table" WHERE id = ? LIMIT 1',
          variables: [Variable.withInt(serverId)],
        ).getSingleOrNull();
        final existingGid = collision?.read<String?>('global_id');
        if (collision != null &&
            existingGid != null &&
            existingGid.isNotEmpty &&
            existingGid != globalId) {
          await IdNamespaceService.instance.renumberLocalRow(
            _db!,
            table,
            serverId,
          );
        }
      } catch (e) {
        debugPrint('[DeltaPull] collision check $table id=$serverId: $e');
      }
    }

    // ── Users table: preserve local password credentials and roleId ──────────
    // The server's users delta may carry password_hash with an empty
    // password_salt (e.g. when the server stores bcrypt with an embedded salt
    // rather than PBKDF2 with a separate salt column). A bare INSERT OR REPLACE
    // would overwrite the client's good salt with "", breaking every subsequent
    // login until the boot-heal runs.
    //
    // Additionally, if the server's user id=N belongs to a *different* person
    // than the client's local user id=N (created offline before sync assigned
    // server IDs), the raw upsert would silently change the local user's roleId,
    // causing mid-session permission escalation (nav expansion bug).
    //
    // Fix: for the users table, detect an absent/empty server salt and fall
    // back to the existing local credentials so the row is otherwise updated
    // (display name, isActive, defaultScreen, …) without clobbering passwords.
    if (table == 'users') {
      // ── حفظُ الأسرار المحلّيّة حين لا يرسلها الخادم ─────────────────────
      //
      // 🔴 `_upsertRow` يكتب بـ**INSERT OR REPLACE**، فالعمودُ الغائبُ عن
      // الحمولة **يُمحى** لا يُترَك. ولهذا الكتلةُ أدناه ترقّع
      // `password_hash`/`password_salt` من الصفّ المحلّيّ.
      //
      // وصار الخادمُ يحجب أعمدةَ الاعتماد عن مستدعٍ بلا هويّةٍ متحقَّقةٍ
      // ولا نافذةِ اقتران (`_getSyncPull` — قائمةُ منعِ الأعمدة)، ويحجب
      // `pin` **دائماً**. فبلا هذا الترقيع كانت أوّلُ مزامنةٍ تمحو الـPIN
      // ورمزَ البطاقة من كلِّ جهاز — أي أنّ سدَّ ثقبِ تسريبٍ كان سيُنتج
      // إتلافَ بيانات.
      //
      // الترقيعُ **غيرُ مشروطٍ** بحالة الهاش عمداً: الـPIN قد يغيب بينما
      // الهاشُ سليم، فوضعُه داخل فرع «الاعتمادُ ناقص» يتركه مكشوفاً للمحو.
      if (row['pin'] == null || row['card_code'] == null) {
        try {
          final secretRow = await _db!.customSelect(
            'SELECT pin, card_code FROM users WHERE id = ? LIMIT 1',
            variables: [
              Variable.withInt(localId ?? (row['id'] as int? ?? 0)),
            ],
          ).getSingleOrNull();
          if (secretRow != null) {
            row = Map.of(row);
            if (row['pin'] == null) {
              row['pin'] = secretRow.read<String?>('pin');
            }
            if (row['card_code'] == null) {
              row['card_code'] = secretRow.read<String?>('card_code');
            }
          }
        } catch (e) {
          debugPrint('[DeltaPull] users: preserve pin/card_code failed: $e');
        }
      }

      final serveSalt = row['password_salt'];
      final serveHash = row['password_hash'];
      final hashStr = serveHash is String ? serveHash : '';
      final saltStr = serveSalt is String ? serveSalt : '';
      final hashOk = hashStr.isNotEmpty;
      // Argon2id PHC hashes embed their salt in the hash string (format:
      // $argon2id$v=19$m=...,t=...,p=...$saltB64$hashB64). When the server's
      // user has been rehashed to Argon2 (Week-8 upgrade in user_dao.dart),
      // password_salt becomes "" by design. Treat that as a VALID credential
      // form — otherwise the previous "preserve local credentials" branch
      // would silently overwrite the server's authoritative Argon2 hash with
      // a stale local PBKDF2 'admin' hash, blocking the user from logging in
      // with their real password (and triggering the boot-heal loop the
      // operator observed in ${Brand.dbPrefix}_startup_log.txt).
      final isArgon2 = hashStr.startsWith(r'$argon2');
      final saltOk = saltStr.isNotEmpty || isArgon2;

      if (!saltOk || !hashOk) {
        // Server sent incomplete credentials — three cases to handle:
        //   1. Local row exists with valid credentials → preserve them
        //      (existing user; admin's PBKDF2 hash mustn't be overwritten by
        //      the server's bcrypt-style "99-char hash, empty salt" form).
        //   2. Local row exists but is also broken (salt="") → mint a fresh
        //      temp password locally so the user can log in via reset flow.
        //   3. NEW user row from server with no local match → mint a temp
        //      password keyed off the username and force a password change.
        //      Without this, the row lands with salt="" and every login
        //      attempt fails (PBKDF2 verifyPassword bails on empty salt) —
        //      the symptom the user reported as "الكاشير القديم مش راضى يدخل
        //      على النظام من جهاز مرتبط".
        final username = row['username'] as String?;
        try {
          final localRow = await _db!.customSelect(
            'SELECT password_hash, password_salt, role_id '
            'FROM users WHERE id = ? LIMIT 1',
            variables: [Variable.withInt(localId ?? (row['id'] as int? ?? 0))],
          ).getSingleOrNull();

          String? hashToUse;
          String? saltToUse;

          if (localRow != null) {
            final localHash = localRow.read<String?>('password_hash') ?? '';
            final localSalt = localRow.read<String?>('password_salt') ?? '';
            if (localHash.isNotEmpty && localSalt.isNotEmpty) {
              hashToUse = localHash;
              saltToUse = localSalt;
              debugPrint('[DeltaPull] users id=${row['id']}: '
                  'server sent empty salt — preserved local credentials');
            }
          }

          // No usable local credentials — generate a temp password so login
          // is possible. Username + "123" matches the convention used by
          // UserSyncStrategy for the same scenario, keeping behavior
          // consistent across the two sync paths.
          if (hashToUse == null &&
              username != null &&
              username.isNotEmpty &&
              !username.startsWith('__dup_')) {
            final tempPassword = '${username}123';
            saltToUse = SecurityService.generateSalt();
            hashToUse = await SecurityService.hashPasswordArgon2(tempPassword);
            // ⚠️ الكلمة المؤقتة **متوقَّعة** (‏`<username>123`) وأسماء
            //    المستخدمين بتتبعت في `GET /api/users` — يعني مش محتاجة كسر
            //    أصلاً، بتتجرّب على شاشة الدخول على طول. Argon2 ما بيحلّش
            //    التوقّع؛ ده بند مفتوح للمالك (التنصيب المؤقت المطلوب:
            //    قفل الحساب لحد ما الخادم يبعت اعتماداً حقيقياً).
            //    اللي اتقفل هنا: الكلمة نفسها ما بقتش بتتكتب في اللوج —
            //    `debugPrint` بيروح لملف تشخيص على القرص.
            debugPrint('[DeltaPull] users id=${row['id']} '
                'username="$username": no usable credentials — minted temp '
                'password + forcePasswordChange=true');
          }

          if (hashToUse != null && saltToUse != null) {
            row = Map.of(row); // make mutable copy before patching
            row['password_hash'] = hashToUse;
            row['password_salt'] = saltToUse;
            // Force the user to change the temp password on first login when
            // we minted credentials. Preserved local credentials don't need
            // this flag — only newly-minted ones do.
            if (localRow == null ||
                (localRow.read<String?>('password_salt') ?? '').isEmpty) {
              row['force_password_change'] = 1;
            }
          }
        } catch (e) {
          debugPrint('[DeltaPull] users credential handling failed: $e');
        }
      }
    }

    // Normal path: server row wins — INSERT OR REPLACE by id.
    final cols = row.keys.join(', ');
    final placeholders = List.filled(row.length, '?').join(', ');
    var applied = false;
    try {
      await _db!.customStatement(
        'INSERT OR REPLACE INTO $table ($cols) VALUES ($placeholders)',
        row.values.toList(),
      );
      applied = true;
    } catch (e) {
      debugPrint('[DeltaPull] upsert $table id=${row['id']}: $e');
    }

    if (applied) await _resignInvoiceRow(table, localId ?? serverId);

    // Replay embedded journal_entry_lines now that the parent header
    // exists. We DELETE-then-INSERT per entry so a server-side line
    // edit (rare — most entries are auto-posted from invoices) takes
    // effect locally instead of leaving stale lines behind. The
    // journal_entry_lines.entry_id FK has ON DELETE CASCADE on the
    // header, but NOT vice-versa, so deleting just the lines for this
    // entry is safe.
    if (embeddedJournalLines != null && serverId != null) {
      try {
        await _db!.customStatement(
          'DELETE FROM journal_entry_lines WHERE entry_id = ?',
          [serverId],
        );
        for (final raw in embeddedJournalLines) {
          if (raw is! Map) continue;
          final lineRow = Map<String, dynamic>.from(raw);
          // Force entry_id to the server's id (which the header upsert
          // above adopted as the local id). Defensive against a server
          // payload accidentally omitting it.
          lineRow['entry_id'] = serverId;
          final lineCols = lineRow.keys.join(', ');
          final linePlaceholders =
              List.filled(lineRow.length, '?').join(', ');
          await _db!.customStatement(
            'INSERT OR REPLACE INTO journal_entry_lines '
            '($lineCols) VALUES ($linePlaceholders)',
            lineRow.values.toList(),
          );
        }
        if (embeddedJournalLines.isNotEmpty) {
          _db!.notifyUpdates({
            const TableUpdate('journal_entry_lines',
                kind: UpdateKind.insert),
            const TableUpdate('journal_entry_lines',
                kind: UpdateKind.update),
          });
        }
      } catch (e) {
        debugPrint(
          '[DeltaPull] journal_entry_lines replay for entry=$serverId: $e',
        );
      }
    }
  }

  /// يحفظ أعمدةَ الـblob الّتي **لا يقدر** الخادمُ على إرسالها، فلا يمحوها
  /// السحبُ التفاضليّ.
  ///
  /// 🔴 العطلُ الّذي يعالجه: مُسلسِلُ `/api/sync/pull` في `api_handler.dart`
  /// يُسقِط كلَّ قيمةٍ من نوع `List<int>` من الحمولة («Skip blob columns»)،
  /// ويكتب `null` كما هو. فللعمودِ الواحدِ شكلان على السلك:
  ///
  ///   • الخادمُ يملك بايتات ⇒ المفتاحُ **غائبٌ** تماماً.
  ///   • الخادمُ يملك NULL   ⇒ المفتاحُ **حاضرٌ بقيمةِ null**، وهذا هو
  ///     الشكلُ الواقعيُّ اليوم لـ`products.image_data`: لا مسارَ دفعٍ يكتب
  ///     العمودَ إلى الخادم أصلاً (‏`createProduct` في
  ///     `client_write_interceptor.dart` بلا وسيطِ صورة)، فعمودُ الخادم
  ///     NULL دائماً.
  ///
  /// وكلا الشكلين كان يمحو الصورةَ المحلّيّة: `INSERT OR REPLACE` يعيد
  /// العمودَ الغائبَ إلى افتراضه (‏`blob().nullable()` بلا افتراض ⇒ NULL)،
  /// والتحديثُ في المكان يكتب الـnull الحاضرَ حرفاً. وسياسةُ `products`
  /// هي `serverWins` فالصفُّ يُطبَّق بلا مقارنةِ إصدار — أي أنّ كلَّ سحبةٍ
  /// تُعيد صفَّ الصنف كانت تمحو صورتَه، بلا رسالةٍ ولا سجلّ.
  ///
  /// ولهذا فـnull الوارِدُ على عمودِ blob **ليس حذفاً**: القناةُ عاجزةٌ عن
  /// التعبير عن غيرِه، فلا معلومةَ فيه. وحذفُ صورةٍ — إن أُريد لاحقاً —
  /// يحتاج شاهداً صريحاً لا غياباً.
  ///
  /// والنطاقُ **مُشتقٌّ من مخطَّط drift** لا مكتوبٌ بيد: أيُّ عمودِ blob
  /// يُضاف إلى جدولٍ مسحوبٍ يُحمى من يومه — ومنه `receipt_settings.logo_image`
  /// إن دخل [pullTables] يوماً (هو خارجها اليوم فلا انكشافَ له).
  ///
  /// ⚠️ **واسمُ الجدول `receipt_settings` لا `treasury_settings`** كما كُتب
  /// هنا أوّلَ مرّة: الملفُّ `treasury_settings_tables.dart` يحمل أصنافاً
  /// عدّة، والعمودُ على `ReceiptSettings` منها. وتسميةُ الجدول بملفِّه
  /// تُرسل القارئَ إلى جدولٍ لا وجودَ له — وهما العمودان الثنائيّان في
  /// المخطَّط كلِّه: هذا و`products.image_data`.
  ///
  /// انظر `delta_pull_blob_preserve_test.dart`.
  ///
  /// والحفظُ يتبع **الهُويّةَ لا الرقم**: صفٌّ محلّيٌّ يحتلّ نفسَ الرقم
  /// بهُويّةٍ عالميّةٍ مختلفةٍ هو صنفٌ آخرُ سيُعاد ترقيمُه بحارسِ التصادم،
  /// فلا تُورَّث صورتُه إلى صفِّ الخادم.
  Future<void> _preserveUnsendableBlobs(
    String table,
    Map<String, dynamic> row, {
    required int? localId,
    required int? serverId,
    required String? globalId,
    required void Function(Map<String, dynamic>) onPatched,
  }) async {
    final schema = _blobSchemaOfDb[table];
    if (schema == null) return;
    // الغيابُ والـnull سواءٌ — كلاهما «لا معلومة».
    final atRisk =
        schema.blobColumns.where((c) => row[c] == null).toList(growable: false);
    if (atRisk.isEmpty) return;

    final anchorId = localId ?? serverId;
    if (anchorId == null) return;

    try {
      final select = [
        ...atRisk,
        if (schema.hasGlobalId) 'global_id',
      ].join(', ');
      final local = await _db!
          .customSelect(
            'SELECT $select FROM "$table" WHERE id = ? LIMIT 1',
            variables: [Variable.withInt(anchorId)],
          )
          .getSingleOrNull();
      if (local == null) return;

      if (schema.hasGlobalId) {
        final localGid = local.data['global_id'] as String?;
        final incomingGid = globalId ?? '';
        if (localGid != null &&
            localGid.isNotEmpty &&
            incomingGid.isNotEmpty &&
            localGid != incomingGid) {
          // صفٌّ آخرُ يحتلّ الرقم — حارسُ التصادم سيُزحزحه.
          return;
        }
      }

      final patched = Map<String, dynamic>.of(row);
      var kept = 0;
      for (final c in atRisk) {
        final value = local.data[c];
        if (value != null) {
          patched[c] = value;
          kept++;
        }
      }
      if (kept > 0) {
        onPatched(patched);
        debugPrint('[DeltaPull] $table id=$anchorId: preserved $kept local '
            'blob column(s) the server cannot send — ${atRisk.join(", ")}');
      }
    } catch (e) {
      debugPrint('[DeltaPull] $table: preserve blob columns failed: $e');
    }
  }

  // ─── Watermark helpers ───────────────────────────────────────────────────

  Future<DateTime?> _loadWatermark(String table) async {
    final val = await _db!.getSettingValue('_watermark__$table');
    if (val == null || val.isEmpty) return null;
    final epoch = int.tryParse(val);
    return epoch != null
        ? DateTime.fromMillisecondsSinceEpoch(epoch * 1000)
        : null;
  }

  Future<void> _saveWatermark(String table, int epochSeconds) async {
    await _db!.setSetting('_watermark__$table', '$epochSeconds');
  }

  /// Returns the current watermark for every pull table (null = never pulled).
  Future<Map<String, DateTime?>> getAllWatermarks() async {
    final result = <String, DateTime?>{};
    for (final table in pullTables) {
      result[table] = await _loadWatermark(table);
    }
    return result;
  }

  /// Clears all watermarks, forcing a full re-sync on the next [pullAll] call.
  Future<void> resetWatermarks() async {
    for (final table in pullTables) {
      await _db!.setSetting('_watermark__$table', '');
    }
    debugPrint('[DeltaPull] All watermarks reset — next pull will be a full sync');
  }

  /// Seeds every watermark to [epochSeconds] — typically the moment a
  /// bootstrap fullSync finished, so the next [pullAll] cycle only asks for
  /// rows modified *after* the bootstrap instead of redundantly re-pulling
  /// everything the strategies already downloaded.
  Future<void> seedWatermarks(int epochSeconds) async {
    if (_db == null) return;
    // Spec 151 P1-8b — when the bootstrap ran WITHOUT a session token it could
    // not pull the branch-scoped transactional tables (the server fail-closed
    // them), so their watermarks must stay unseeded; otherwise the post-login
    // DeltaPull would ask only for rows after `epochSeconds` and permanently
    // skip the pre-login backlog (the reverted BLOCKER). With a token present
    // (e.g. a mirror that minted an admin token at pairing) the bootstrap
    // pulled everything, so seed all tables as before.
    final hasToken = ServerProxy.instance.hasSessionToken();
    var seeded = 0;
    for (final table in pullTables) {
      if (!hasToken && branchScopedPullTables.contains(table)) continue;
      // v166 — جدولٌ لا تملؤه `fullSync` لا يُبذَر مهما كان التوكن: البذرُ
      // يفترض تنزيلاً لم يقع. انظر [deltaOnlyTables].
      if (deltaOnlyTables.contains(table)) continue;
      await _saveWatermark(table, epochSeconds);
      seeded++;
    }
    debugPrint('[DeltaPull] Seeded $seeded/${pullTables.length} watermarks to '
        '$epochSeconds (hasToken=$hasToken)');
  }

  /// True when at least one watermark has been persisted — used by startup to
  /// pick between full bootstrap and incremental delta pull.
  Future<bool> hasAnyWatermark() async {
    if (_db == null) return false;
    for (final table in pullTables) {
      final val = await _db!.getSettingValue('_watermark__$table');
      if (val != null && val.isNotEmpty) return true;
    }
    return false;
  }
}

/// ما يحتاجه [DeltaPullService] من مخطَّط جدولٍ واحدٍ لحفظِ أعمدةِ الـblob:
/// أسماءُ أعمدةِ الـblob فيه، وهل يحمل `global_id` لتمييزِ الهُويّة.
class _BlobTableSchema {
  const _BlobTableSchema({
    required this.blobColumns,
    required this.hasGlobalId,
  });

  final List<String> blobColumns;
  final bool hasGlobalId;
}
